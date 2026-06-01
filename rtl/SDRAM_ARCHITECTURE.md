# SDRAM Matrix Accelerator Architecture

Objetivo final: usar a SDRAM externa da DE0-CV como memoria principal para as matrizes completas `A`, `B` e `C`. A memoria M10K interna deve guardar apenas tiles/blocos ativos perto dos MACs/DSPs.

O compute core nao deve acessar SDRAM a cada MAC. O fluxo correto e: SDRAM guarda matriz completa, `tile_loader` move blocos para M10K, compute usa M10K, `tile_writer` grava o tile `C` atualizado de volta na SDRAM.

## Estado Atual do RTL

O projeto ja tem os blocos conceituais da arquitetura SDRAM:

- `memory/sdram_bus_if.vhd`: constantes comuns de selecao e comando.
- `memory/sdram_controller_wrapper.vhd`: stub sintetizavel para futuro IP SDRAM do Quartus/Platform Designer.
- `memory/matrix_memory_map.vhd`: calcula enderecos byte row-major.
- `memory/tile_buffer_m10k.vhd`: buffer local de tile em M10K.
- `control/memory_manager.vhd`: arbitra host, loader e writer no barramento SDRAM.
- `control/tile_loader.vhd`: carrega tiles `A`, `B` e opcionalmente `C` da SDRAM.
- `control/tile_writer.vhd`: grava tile `C` de volta na SDRAM.
- `control/sdram_tile_scheduler.vhd`: agenda loops tiled `i`, `j`, `k`.

Porem o top-level atual ainda instancia `matrix_mult_tiled_core`, que usa `matrix_single_port_ram` para armazenar `A`, `B` e `C` completos em M10K. Assim, o RTL compila, mas ainda nao implementa o objetivo final SDRAM.

## Mapa do Projeto

```text
rtl/common/
  matrix_tiled_pkg.vhd          utilitarios: clog2, ceil_div, row_major_addr
  matrix_accel_config_pkg.vhd   defaults e IDs A/B/C
  perf_counters.vhd             contadores de ciclos/eventos
  sigma_hex_display.vhd         display fixo
  accelerator_status_leds.vhd   LEDs de status

rtl/uart/
  uart_rx.vhd                   RX serial
  uart_tx.vhd                   TX serial
  uart_byte_fifo.vhd            FIFO UART em M10K/SCFIFO

rtl/control/
  command_interface.vhd         protocolo UART: LOAD_A, LOAD_B, START, READ_C
  memory_manager.vhd            arbitro SDRAM conceitual
  tile_loader.vhd               SDRAM -> M10K tiles
  tile_writer.vhd               M10K C tile -> SDRAM
  sdram_tile_scheduler.vhd      FSM dos tiles

rtl/memory/
  matrix_single_port_ram.vhd    memoria interna atual de matriz completa
  sdram_bus_if.vhd              constantes da interface SDRAM
  sdram_controller_wrapper.vhd  stub do controlador SDRAM
  matrix_memory_map.vhd         mapa byte das matrizes
  tile_buffer_m10k.vhd          buffer local por tile

rtl/compute/
  mac_unit.vhd                  MAC assinado
  matrix_tiled_compute_core.vhd compute de um tile usando vetores achatados
  matrix_mult_tiled_core.vhd    core antigo: RAM completa interna + tiles locais

rtl/top/
  matrix_accelerator_full_top.vhd top atual da placa
```

## Mapa SDRAM

Layout row-major em bytes:

```text
BASE_A = 0
BASE_B = BASE_A + N*N*sizeof(INT8)
BASE_C = BASE_B + N*N*sizeof(INT8)
```

Endereco:

```text
A[row,col] = BASE_A + (row*N + col)
B[row,col] = BASE_B + (row*N + col)
C[row,col] = BASE_C + (row*N + col)*4
```

Capacidade necessaria:

```text
N=512:  A=256 KiB, B=256 KiB, C=1 MiB, total ~= 1.5 MiB
N=1024: A=1 MiB,   B=1 MiB,   C=4 MiB, total ~= 6 MiB
```

Isso justifica SDRAM como memoria principal. M10K deve guardar somente tiles. Exemplo `TILE_SIZE=16`:

```text
A_tile int8  = 16*16*1 = 256 B
B_tile int8  = 16*16*1 = 256 B
C_tile int32 = 16*16*4 = 1024 B
total por buffer simples ~= 1.5 KiB
```

Mesmo com double buffering, o uso de M10K continua pequeno comparado a matriz completa.

## Fluxo Final

```text
UART LOAD_A -> command_interface -> memory_manager -> SDRAM[A]
UART LOAD_B -> command_interface -> memory_manager -> SDRAM[B]
START
  scheduler gera tile_i, tile_j, tile_k
  tile_loader carrega A_tile, B_tile e C_tile da SDRAM para buffers M10K
  compute core processa somente dados dos buffers M10K
  tile_writer grava C_tile atualizado em SDRAM[C]
DONE
READ_C -> command_interface -> memory_manager -> SDRAM[C] -> UART
```

## FSM Conceitual

```text
IDLE
START_LOAD
WAIT_LOAD
START_COMPUTE
WAIT_COMPUTE
NEXT_K
START_WRITE
WAIT_WRITE
NEXT_TILE
DONE
```

Regra para `C`:

- Se `tile_k = 0`, carregar `C_tile` zerado ou ler `C` inicializado com zero.
- Para `tile_k > 0`, preservar acumulacao parcial em `C_tile`.
- A versao atual do `sdram_tile_scheduler` escreve `C` somente depois do ultimo `k`, o que e melhor para reduzir trafego SDRAM.

## Interface Entre Blocos

`command_interface` deve deixar de assumir read latency fixa da RAM interna. Para SDRAM, ele precisa de handshake:

```text
host_valid, host_write, host_addr, host_wdata, host_be
host_ready, host_rvalid, host_rdata
```

`memory_manager` arbitra prioridades:

```text
1. Host UART durante LOAD_A, LOAD_B, READ_C, quando acelerador parado
2. tile_writer durante processamento
3. tile_loader durante processamento
```

O top-level final deve instanciar:

```text
command_interface
memory_manager
sdram_controller_wrapper
sdram_tile_scheduler
tile_loader
tile_writer
tile_buffer_m10k para A
tile_buffer_m10k para B
tile_buffer_m10k para C
matrix_tiled_compute_core adaptado para ler buffers M10K
```

## Erros e Lacunas Encontrados

1. `matrix_accelerator_full_top.vhd` ainda instancia `matrix_mult_tiled_core`, nao a arquitetura SDRAM.
2. `matrix_mult_tiled_core.vhd` ainda instancia tres `matrix_single_port_ram` com profundidade `N*N`; isso viola o objetivo para `N=512/1024`.
3. `MEM_TYPE` existe como generic, mas `matrix_mult_tiled_core` avisa que qualquer valor diferente de `internal_fpga_ram` nao muda o datapath.
4. `command_interface.vhd` usa `HOST_READ_LATENCY` fixo. SDRAM real precisa `host_ready/host_rvalid`.
5. `memory_manager.vhd`, `tile_loader.vhd`, `tile_writer.vhd` e `sdram_tile_scheduler.vhd` compilam, mas ainda nao estao conectados no top.
6. `sdram_controller_wrapper.vhd` e stub: leituras nunca retornam dados validos. Serve para compilar, nao para executar.
7. O protocolo host envia endereco linear de elemento. O RTL SDRAM final deve traduzir para endereco byte por matriz.
8. O script de simulacao precisa compilar os novos blocos SDRAM para evitar regressao silenciosa.
9. Ainda faltam testbenches unitarios para `memory_manager`, `tile_loader`, `tile_writer` e `sdram_tile_scheduler`.
10. Ainda faltam sinais fisicos SDRAM no top-level e pin assignments da SDRAM externa.

## Plano de Implementacao

Fase 1: infraestrutura testavel

- Adicionar blocos SDRAM ao script de simulacao.
- Criar modelo simples de SDRAM para testbench, com handshake `cmd_valid/cmd_ready/rd_valid`.
- Criar testes unitarios para mapa de memoria, loader, writer e manager.

Fase 2: top SDRAM basico

- Adicionar generics `SDRAM_ADDR_WIDTH`, `SDRAM_DATA_WIDTH`, `BASE_A_BYTES`, `BASE_B_BYTES`, `BASE_C_BYTES`.
- Alterar `command_interface` para handshake de memoria.
- Conectar `LOAD_A`, `LOAD_B` e `READ_C` ao `memory_manager`.
- Instanciar buffers M10K `A`, `B`, `C`.
- Adaptar `matrix_tiled_compute_core` para interface de buffers ou criar wrapper que empacota/desempacota tiles.
- Conectar scheduler, loader, compute e writer.
- Manter `matrix_mult_tiled_core` antigo como modo legado, se util para comparacao.

Fase 3: IP SDRAM real da DE0-CV

- Trocar stub por IP Quartus/Platform Designer ou controlador validado da Terasic.
- Expor sinais fisicos SDRAM no top-level.
- Adicionar pins e constraints corretos no `.qsf`/`.sdc`.
- Validar `N=512` primeiro, depois `N=1024`.

Fase 4: desempenho

- Agrupar acessos em bursts, evitando uma transacao SDRAM por elemento.
- Usar empacotamento de quatro `int8` por palavra SDRAM de 32 bits para `A`/`B`.
- Manter `C` como palavra `int32`.
- Medir ciclos de load, compute e store separadamente.

## Evolucao: Double Buffering

Versao basica usa buffer simples:

```text
LOAD tile atual -> COMPUTE tile atual -> WRITE C
```

Versao evoluida usa dois bancos de buffers:

```text
buffer 0: compute tile atual
buffer 1: carrega proximo tile
swap
```

Beneficio: SDRAM trabalha enquanto MACs processam. Custo: dobra M10K dos buffers, aumenta FSM e exige controle de hazards:

- nao sobrescrever buffer em uso pelo compute;
- nao ler `C_tile` velho enquanto writer ainda grava;
- manter ordem correta de `tile_i`, `tile_j`, `tile_k`;
- tratar bordas se futuramente `N` nao for multiplo de `TILE_SIZE`.

## Criterio de Pronto

A arquitetura SDRAM pode ser considerada implementada quando:

- `LOAD_A` e `LOAD_B` gravam diretamente na SDRAM;
- `START` processa usando apenas tiles em M10K;
- `C` completo fica na SDRAM ao final;
- `READ_C` le da SDRAM via UART;
- `matrix_mult_tiled_core` antigo nao e mais o caminho principal para `MEM_TYPE = "external_sdram"`;
- testbench com modelo SDRAM passa para pelo menos uma matriz pequena;
- sintese da placa passa com IP/pinos SDRAM reais.
