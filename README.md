# FPGA Matrix Accelerator

Acelerador VHDL para multiplicacao densa de matrizes inteiras na DE0-CV / Cyclone V `5CEBA4F23C7`.

## About Curso

Projeto academico para estudar desempenho, recursos e eficiencia de um acelerador `C = A x B` com `INT8` na entrada e acumulacao `INT32`.

- Apresentacao Overleaf: `<coloque-o-link-aqui>`
- Relatorio tecnico: `<coloque-o-link-aqui>`

## Arquitetura Atual

O projeto foi limpo para manter somente o acelerador completo atual:

- Top de sintese: `matrix_accelerator_full_top`
- Core parametrizavel: `matrix_mult_tiled_core`
- Parametros principais: `N`, `TILE_SIZE`, `NUM_MACS`, `DATA_WIDTH`, `ACC_WIDTH`
- Memoria: RAM interna inferida em M10K para A, B e C
- Interface: UART simples para carregar A/B, iniciar, ler C/status/contadores
- Indicacao visual: `LEDR[9:0]`

Nao ha mais fluxo de SDRAM externa nem arquitetura 4x4 legada.

## Pastas

- `rtl/common/`: pacotes, contadores de desempenho e LEDs de status.
- `rtl/compute/`: unidade MAC e core de calculo tiled.
- `rtl/memory/`: RAM interna inferivel para matrizes.
- `rtl/control/`: interface de comandos UART para o acelerador.
- `rtl/uart/`: RX/TX UART.
- `rtl/top/`: top completo da placa.
- `testes/`: testbenches e runner de simulacao.
- `py_matrix_host/`: submodulo Python para gerar matrizes, host UART e validacao.
- `scripts/`: experimentos, parsing de relatorios e coleta de CSV.

## Scripts Principais

Rodar todos os testbenches:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_testbenchs.ps1
```

Rodar somente o testbench tiled:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\testes\scripts\run_tb_matrix_mult_tiled_core.ps1 -N 8 -TileSize 4 -NumMacs 4
```

Rodar todos os experimentos:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_all_experiments.ps1
```

Gerar matrizes pelo host Python:

```powershell
python .\py_matrix_host\main.py generate --n 128 --data-width 8 --acc-width 32 --output-dir .\py_matrix_host\matrix
```

Rodar host em dry-run:

```powershell
python .\py_matrix_host\main.py uart --dry-run --input .\py_matrix_host\matrix\matrix_inputs.txt --expected .\py_matrix_host\matrix\matrix_expected.txt
```

## Quartus

O arquivo `fpga_matrix_accelerator.qsf` aponta para `matrix_accelerator_full_top` e inclui apenas os RTLs usados pela arquitetura atual.
