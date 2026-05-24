# FPGA Matrix Accelerator

Acelerador VHDL para multiplicacao densa de matrizes inteiras na DE0-CV / Cyclone V `5CEBA4F23C7`.

## About

Projeto academico para estudar custo, desempenho e eficiencia de um acelerador `C = A x B` com entradas inteiras e acumulacao inteira.

- Curso: `<coloque-o-nome-do-curso-aqui>`
- Apresentacao Overleaf: `<coloque-o-link-aqui>`
- Relatorio tecnico: `<coloque-o-link-aqui>`

## Primeiro Passo

Este repositorio usa submodulo para o host Python. Depois de clonar:

```powershell
git submodule update --init --recursive
```

## Arquitetura Atual

- Top de sintese: `matrix_accelerator_full_top`
- Core parametrizavel: `matrix_mult_tiled_core`
- Generics conectados ao RTL: `N`, `TILE_SIZE`, `NUM_MACS`, `DATA_WIDTH`, `ACC_WIDTH`
- Memoria: RAM interna inferida em M10K para A, B e C
- Interface: UART com FIFO `SCFIFO`
- Debug: SignalTap HDL wrapper
- Visual: `LEDR[9:0]` e `HEX5..HEX0` mostrando `SIGMAX` durante execucao

## Pastas

- `rtl/common/`: pacotes, contadores, LEDs de status e display `SIGMAX`.
- `rtl/compute/`: MAC, compute core e core tiled.
- `rtl/memory/`: RAM interna inferivel.
- `rtl/control/`: protocolo de comandos do acelerador.
- `rtl/uart/`: UART RX/TX e FIFO UART.
- `rtl/debug/`: wrapper SignalTap.
- `rtl/top/`: top-level da placa.
- `testes/`: testbenches e runner.
- `py_matrix_host/`: submodulo Python para matriz/golden model/UART.
- `parameter_optimization/`: varredura de parametros, coleta, analise e graficos.

## Testes

Rodar todos os testbenches:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_testbenchs.ps1
```

Rodar apenas um testbench:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_testbenchs.ps1 -Only tb_matrix_mult_tiled_core
```

Rodar com parametros:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_testbenchs.ps1 -Only tb_matrix_mult_tiled_core -N 8 -TileSize 4 -NumMacs 4
```

## Quartus

Compilar o projeto principal:

```powershell
C:\altera_lite\25.1std\quartus\bin64\quartus_sh.exe --flow compile fpga_matrix_accelerator -c fpga_matrix_accelerator
```

O arquivo principal e `fpga_matrix_accelerator.qsf`. Os pinos de UART (`uart_rx_i`, `uart_tx_o`) precisam ser definidos conforme o conector/adaptador usado na placa.

## Parameter Optimization

Tudo do fluxo de experimentos fica em `parameter_optimization/`. Nada deve ser salvo em `results/` na raiz.

Configuracoes:

- `parameter_optimization/configs/01_compute_sweep.json`: varia `tile_size` e `num_macs`.
- `parameter_optimization/configs/02_memory_sweep.json`: varia parametros de memoria como metadados.
- `parameter_optimization/configs/03_timing_sweep.json`: varia pipeline/bancos como metadados.
- `parameter_optimization/configs/04_precision_sweep.json`: varia `DATA_WIDTH` e `ACC_WIDTH`.

Rodar uma fase:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\parameter_optimization\run_sdram_arch_experiments.ps1 -ConfigPath .\parameter_optimization\configs\01_compute_sweep.json
```

Rodar pelo atalho da raiz:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_all_experiments.ps1 -ConfigPath .\parameter_optimization\configs\01_compute_sweep.json
```

Coletar resultados manualmente:

```powershell
python .\parameter_optimization\collect_results.py --runs-dir .\parameter_optimization\results\01_compute_sweep\runs --output-csv .\parameter_optimization\results\01_compute_sweep\experiment_results.csv
```

Gerar analise e graficos:

```powershell
python .\parameter_optimization\analysis\run_analysis.py --experiment-dir .\parameter_optimization\results\01_compute_sweep
```

Saidas principais:

- `parameter_optimization/results/<experiment_name>/experiment_results.csv`
- `parameter_optimization/results/<experiment_name>/experiment_summary.json`
- `parameter_optimization/results/<experiment_name>/resource_speed_analysis.json`
- `parameter_optimization/results/<experiment_name>/analysis_report.md`
- `parameter_optimization/results/<experiment_name>/plots/`

## Parametros

Conectados ao VHDL hoje:

- `N`
- `TILE_SIZE`
- `NUM_MACS`
- `DATA_WIDTH`
- `ACC_WIDTH`

Apenas metadados/configuracao por enquanto:

- `MEM_TYPE`
- `DATAFLOW`
- `BUFFERING_MODE`
- `MEMORY_BURST_LEN`
- `MAC_PIPELINE_STAGES`
- `MEMORY_BANKS_A`
- `MEMORY_BANKS_B`

