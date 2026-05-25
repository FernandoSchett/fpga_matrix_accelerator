# FPGA Matrix Accelerator em VHDL

Projeto de implementacao e avaliacao de um acelerador de multiplicacao densa de matrizes em FPGA, usando VHDL no Quartus para a DE0-CV / Cyclone V `5CEBA4F23C7`.

O acelerador calcula:

```text
C = A x B
```

A configuracao principal usa matrizes `N x N`, entradas inteiras `INT8`, acumulacao `INT32`, RAM interna M10K inferida, UART com FIFO e instrumentacao por LEDs/SignalTap. O objetivo e comparar configuracoes arquiteturais variando `TILE_SIZE`, `NUM_MACS` e outros parametros de experimento.

Relatorio em desenvolvimento: [Overleaf](<coloque-o-link-aqui>).

Relatorio tecnico: [PDF/Docs](<coloque-o-link-aqui>).

## Primeiro Uso

O host Python fica em submodulo. Depois de clonar:

```powershell
git submodule update --init --recursive
```

## Estrutura

- `rtl/common/`: pacotes, contadores de desempenho, LEDs de status e display `SIGMAX`.
- `rtl/compute/`: MAC, compute core e multiplicador tiled.
- `rtl/memory/`: RAM interna inferivel para A, B e C.
- `rtl/control/`: interface de comandos do acelerador.
- `rtl/uart/`: UART RX/TX e FIFO `SCFIFO`.
- `rtl/debug/`: wrapper SignalTap.
- `rtl/top/matrix_accelerator_full_top.vhd`: top-level da placa.
- `testes/`: testbenches e script para simulacao.
- `py_matrix_host/`: submodulo Python para golden model, UART e validacao.
- `parameter_optimization/`: experimentos, coleta, analise e graficos.

## Scripts

- `run_testbenchs.ps1`: roda os testbenches VHDL.
- `run_all_experiments.ps1`: atalho para rodar experimentos arquiteturais.
- `parameter_optimization/run_experiment.ps1`: executa uma fase de sweep a partir de JSON.
- `parameter_optimization/main.py`: entrada Python do fluxo de um experimento.
- `parameter_optimization/compare_experiments.py`: compara varios sweeps e aponta a melhor configuracao global.
- `parameter_optimization/analysis/parse_quartus_reports.py`: extrai recursos, Fmax e dados dos relatorios Quartus.
- `parameter_optimization/analysis/collect_results.py`: consolida runs em CSV e JSON.
- `parameter_optimization/analysis/run_analysis.py`: gera graficos e relatorio de analise.
- `py_matrix_host/main.py`: gera matrizes, golden model e fluxo UART/dry-run.

## Como Rodar

Rodar todos os testbenches:

```powershell
.\run_testbenchs.ps1
```

Rodar um testbench parametrizado:

```powershell
.\run_testbenchs.ps1 -Only tb_matrix_mult_tiled_core -N 8 -TileSize 4 -NumMacs 4
```

Medir apenas ciclos de execucao, sem carregar/conferir toda a matriz:

```powershell
.\run_testbenchs.ps1 -Only tb_matrix_mult_tiled_core_perf -N 128 -TileSize 2 -NumMacs 1
```

Compilar no Quartus:

```powershell
C:\altera_lite\25.1std\quartus\bin64\quartus_sh.exe --flow compile fpga_matrix_accelerator -c fpga_matrix_accelerator
```

Rodar o sweep principal:

```powershell
.\parameter_optimization\run_experiment.ps1 -ConfigPath .\parameter_optimization\configs\01_compute_sweep.json
```

Rodar todos os sweeps de `parameter_optimization/configs/` e comparar no final:

```powershell
.\run_all_experiments.ps1
```

Gerar matrizes e golden model:

```powershell
python .\py_matrix_host\main.py generate --n 128 --data-width 8 --acc-width 32 --output-dir .\py_matrix_host\matrix
```

Rodar host em dry-run:

```powershell
python .\py_matrix_host\main.py uart --dry-run --input .\py_matrix_host\matrix\matrix_inputs.txt --expected .\py_matrix_host\matrix\matrix_expected.txt
```

## Parameter Optimization

Configuracoes:

- `configs/01_compute_sweep.json`: varia `tile_size` e `num_macs`.
- `configs/02_run18_alm_boundary_sweep.json`: varia acumulador/pipeline ao redor da melhor configuracao.
- `configs/03_run18_memory_banking_sweep.json`: varia bancos e buffering.
- `configs/04_run18_elite_combo_sweep.json`: combina as melhores hipoteses.

Parametros conectados ao RTL atual:

- `N`
- `TILE_SIZE`
- `NUM_MACS`
- `DATA_WIDTH`
- `ACC_WIDTH`
- `MEM_TYPE`
- `DATAFLOW`
- `BUFFERING_MODE`
- `MEMORY_BURST_LEN`
- `MAC_PIPELINE_STAGES`
- `MEMORY_BANKS_A`
- `MEMORY_BANKS_B`

## Saidas

- `output_files/`: relatorios e bitstream gerados pelo Quartus.
- `parameter_optimization/results/<experiment_name>/runs/`: dados individuais de cada run.
- `parameter_optimization/results/<experiment_name>/experiment_results.csv`: CSV consolidado.
- `parameter_optimization/results/<experiment_name>/experiment_summary.json`: resumo do experimento.
- `parameter_optimization/results/<experiment_name>/resource_speed_analysis.json`: analise de recursos e desempenho.
- `parameter_optimization/results/<experiment_name>/analysis_report.md`: relatorio automatico.
- `parameter_optimization/results/<experiment_name>/plots/`: graficos em PNG.
- `parameter_optimization/results/compare_experiments/`: comparacao global dos sweeps.

## Metricas Principais

- `fmax_mhz`: frequencia maxima estimada pelo Quartus.
- `exec_cycles`: ciclos medidos pelo testbench.
- `gops_eff_exact`: GOPS efetivo usando contagem exata de operacoes.
- `gops_eff_approx`: GOPS efetivo usando aproximacao `2 x N^3`.
- `gops_peak`: pico teorico baseado em `NUM_MACS` e `fmax_mhz`.
- `peak_efficiency`: eficiencia em relacao ao pico teorico.
- `resource_pressure_pct`: pressao maxima entre ALMs, DSPs, memoria e pinos.
- `routing_pressure_score`: indicador heuristico de risco de roteamento.
- `performance_per_resource_score`: desempenho normalizado por pressao de recurso.

## Observacoes

- A UART fisica ainda depende do pin assignment do adaptador usado.
- Os displays `HEX5..HEX0` mostram `SIGMAX` enquanto o acelerador esta ocupado.
- `LEDR` mostra heartbeat, busy, compute, progresso, done e erro.
