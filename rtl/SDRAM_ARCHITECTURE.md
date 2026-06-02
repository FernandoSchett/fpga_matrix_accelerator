# SDRAM Matrix Accelerator Architecture

Objetivo final: usar a SDRAM externa da DE0-CV como memoria principal para as matrizes completas `A`, `B` e `C`. A memoria M10K interna guarda apenas tiles/buffers perto dos MACs/DSPs.

O compute core nao acessa SDRAM a cada MAC. Fluxo correto: SDRAM guarda matriz completa, `tile_loader` move blocos para M10K, compute usa M10K, `tile_writer` grava o tile `C` atualizado de volta na SDRAM.

## Estado Atual do RTL

A migracao basica para SDRAM esta integrada:

- `top/matrix_accelerator_full_top.vhd` instancia `matrix_mult_sdram_tiled_core`.
- O top expoe portas fisicas `DRAM_*` da DE0-CV.
- `memory/sdram_controller_wrapper.vhd` tem dois modos:
  - `SIMULATION_MODEL=true`: memoria byte-addressed emulada para testbench.
  - `SIMULATION_MODEL=false`: adaptador para IP SDRAM externo `sdram_ip_core`.
- `memory/sdram_ip_core.vhd` adapta a interface interna byte-addressed/Avalon-like para o IP SDRAM 16-bit.
- `ip/stffrdhrn_sdram_controller/` contem o IP SDR SDRAM vendorizado usado no hardware.
- `control/command_interface.vhd` usa handshake `host_cmd_valid`/`host_cmd_ready`; `READ_C` espera `host_rd_valid`.
- `control/memory_manager.vhd` arbitra host, writer e loader no barramento SDRAM.
- `control/tile_loader.vhd` carrega um painel de tiles `A`/`B` da SDRAM e inicializa `C` com zero quando `ACCUMULATE_C=false`.
- `control/tile_writer.vhd` grava o tile `C` final na SDRAM.
- `control/sdram_tile_scheduler.vhd` agenda loops tiled `i`, `j` e paineis em `k`.
- `memory/tile_buffer_m10k.vhd` e usado como buffer local de tile, nao como matriz completa.
- `compute/matrix_mult_sdram_tiled_core.vhd` instancia varios bancos M10K de `A` e `B` via `MEMORY_BANKS_A/B`; `C` permanece um tile acumulador M10K.

`matrix_mult_tiled_core` continua no repo como legado/teste, mas nao e mais o caminho principal do top.

## Mapa do Projeto

```text
rtl/common/
  matrix_tiled_pkg.vhd          utilitarios: clog2, ceil_div, row_major_addr
  matrix_accel_config_pkg.vhd   defaults e IDs A/B/C
  perf_counters.vhd             contadores de ciclos/eventos
  sigma_hex_display.vhd         display
  accelerator_status_leds.vhd   LEDs de status

rtl/uart/
  uart_rx.vhd                   RX serial
  uart_tx.vhd                   TX serial
  uart_byte_fifo.vhd            FIFO UART em M10K/SCFIFO

rtl/control/
  command_interface.vhd         UART: LOAD_A, LOAD_B, START, READ_C, counters
  memory_manager.vhd            arbitro do barramento SDRAM
  tile_loader.vhd               SDRAM -> M10K tiles
  tile_writer.vhd               M10K C tile -> SDRAM
  sdram_tile_scheduler.vhd      FSM dos tiles

rtl/memory/
  matrix_single_port_ram.vhd    legado: RAM interna de matriz completa
  sdram_bus_if.vhd              constantes da interface SDRAM
  sdram_ip_core.vhd             wrapper Avalon-like para IP SDRAM 16-bit
  sdram_controller_wrapper.vhd  modelo sim + adaptador fisico para IP
  matrix_memory_map.vhd         mapa byte das matrizes
  tile_buffer_m10k.vhd          buffer local por tile

rtl/ip/
  stffrdhrn_sdram_controller/   IP SDR SDRAM BSD usado no caminho fisico

rtl/compute/
  mac_unit.vhd                  MAC assinado
  matrix_tiled_compute_core.vhd compute de um tile usando vetores achatados
  matrix_mult_tiled_core.vhd    legado: RAM completa interna
  matrix_mult_sdram_tiled_core.vhd arquitetura SDRAM + M10K

rtl/top/
  matrix_accelerator_full_top.vhd top da placa
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

Capacidade:

```text
N=512:  A=256 KiB, B=256 KiB, C=1 MiB, total ~= 1.5 MiB
N=1024: A=1 MiB,   B=1 MiB,   C=4 MiB, total ~= 6 MiB
```

Isso justifica SDRAM como memoria principal. Exemplo `TILE_SIZE=16` em M10K:

```text
A_tile int8 por banco = 16*16*1 = 256 B
B_tile int8 por banco = 16*16*1 = 256 B
C_tile int32          = 16*16*4 = 1024 B
total com 4 bancos A/B ~= 4*(256+256) + 1024 = 3072 B
```

## Fluxo FSM Atual

```text
UART LOAD_A -> command_interface -> matrix_mult_sdram_tiled_core
            -> memory_manager -> sdram_controller_wrapper -> SDRAM[A]

UART LOAD_B -> command_interface -> matrix_mult_sdram_tiled_core
            -> memory_manager -> sdram_controller_wrapper -> SDRAM[B]

START
  scheduler gera tile_i, tile_j, tile_k_base e panel_count
  tile_loader carrega panel_count tiles de A para bancos A_M10K[0..panel_count-1]
  tile_loader carrega panel_count tiles de B para bancos B_M10K[0..panel_count-1]
  se tile_k_base=0:
    ACCUMULATE_C=false -> zera C_tile em M10K
    ACCUMULATE_C=true  -> le C_tile da SDRAM
  para cada banco valido no painel:
    compute wrapper empacota A_bank, B_bank e C_tile em vetores
    matrix_tiled_compute_core calcula C_tile += A_bank * B_bank
    resultado volta para C_buffer M10K
  se k ainda nao terminou:
    proximo painel k recarrega A/B e preserva C_buffer parcial
  se ultimo painel k:
    tile_writer grava C_tile final em SDRAM[C]
DONE

READ_C -> command_interface emite host_cmd_valid ate host_cmd_ready
       -> depois aguarda host_rd_valid
       -> memory_manager -> SDRAM[C] -> UART
```

FSM do scheduler:

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

## Pontos Corrigidos

- Top-level agora tem portas fisicas SDRAM e pinout DE0-CV no `.qsf`.
- Top-level usa `matrix_mult_sdram_tiled_core`, nao `matrix_mult_tiled_core`.
- Host escreve `A`/`B` direto na SDRAM via `memory_manager`.
- Host le `C` final da SDRAM via comando aceito por `host_cmd_ready` e retorno `host_rd_valid`.
- `sdram_controller_wrapper` retorna leitura real no modelo de sim e usa IP SDRAM externo no hardware.
- Enderecamento e byte-addressed: `A`/`B` usam `int8`; `C` usa `int32`.
- Escrita `int8` em barramento 32-bit usa byte address + DQM no IP SDRAM 16-bit fisico.
- `C` inicial zera no primeiro `k` quando `ACCUMULATE_C=false`.
- `tile_buffer_m10k` single-port nao alimenta MACs diretamente; o wrapper empacota o tile antes do compute, evitando conflito de portas.
- `MEMORY_BANKS_A/B` agora criam bancos reais de M10K para painel em `k`; o loader enche varios tiles A/B antes do compute consumir o painel.
- `perf_counters` recebe `mac_ops_issued` real do compute core, nao `NUM_MACS` durante todo `busy`.

## Lacunas Restantes

- Panel buffering atual e um painel em `k` para um unico tile `C`. Ainda nao e block buffering 2D mantendo varios tiles de `C` e reutilizando paineis A/B em varios tiles de saida.
- IP SDRAM fisico e basico: single-beat, sem burst, sem row cache e sem PLL/phase shift dedicado para `DRAM_CLK`.
- Timing de I/O SDRAM ainda nao esta totalmente fechado no SDC; o Quartus compila, mas reporta design nao totalmente constrained.
- `matrix_tiled_compute_core` ainda usa vetores achatados; wrapper faz pack/unpack sequencial dos M10K. Correto para funcionalidade, lento para tiles grandes.
- `memory_manager` ainda e arbitro simples, sem filas profundas nem burst coalescing.
- Testes cobrem caminho UART/top com modelo SDRAM pequeno; ainda faltam testes unitarios dedicados para loader/writer/manager/IP fisico.
- Double buffering ainda nao esta implementado.

## Evolucao: Double Buffering

Versao basica:

```text
LOAD tile atual -> COMPUTE tile atual -> WRITE C
```

Versao evoluida:

```text
buffer 0: compute tile atual
buffer 1: carrega proximo tile
swap
```

Requisitos:

- duplicar buffers M10K de `A` e `B`, e possivelmente `C`;
- manter flags `load_bank`, `compute_bank`, `store_bank`;
- nao sobrescrever buffer em uso pelo compute;
- nao ler `C_tile` velho enquanto writer grava;
- manter ordem correta de `tile_i`, `tile_j`, `tile_k`;
- agrupar acessos SDRAM em bursts.

## Criterio de Pronto

Basico funcional:

- `LOAD_A` e `LOAD_B` gravam diretamente na SDRAM;
- `START` processa usando tiles M10K;
- `C` completo fica na SDRAM ao final;
- `READ_C` le da SDRAM via UART;
- testbench top UART passa com modelo SDRAM;
- fluxo Quartus gera `.sof`.

Para hardware robusto:

- validar SDRAM fisica na placa com padrao write/read antes do acelerador;
- fechar constraints de SDRAM I/O;
- adicionar PLL/phase shift dedicado para `DRAM_CLK`, se precisar margem real;
- adicionar burst/double buffering para desempenho.
