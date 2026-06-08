# Parameter Optimization

Modulo de experimentos do acelerador. Ele roda sweeps, compila no Quartus, coleta relatorios, calcula metricas e gera graficos.

Este diretorio e um repositorio Git proprio. Depois de clonar o projeto principal, inicialize/atualize submodulos quando ele virar submodulo remoto:

```powershell
git submodule update --init --recursive
```

## Fases

- `configs/01_compute_unit_sweep.json`: otimiza apenas `compute_unit_top`, sem matriz completa e sem memoria no caminho critico.
- `configs/02_memory_access_sweep.json`: otimiza acesso/memoria no top completo, usando a melhor compute unit escolhida na fase 01.
- `configs/legacy/`: sweeps antigos e exploratorios.

## Entradas

- `main.py`: entrada Python para rodar um experimento JSON.
- `run_experiment.ps1`: runner PowerShell de um experimento.
- `compare_experiments.py`: compara resultados entre experimentos.
- `analysis/parse_quartus_reports.py`: extrai dados dos relatorios Quartus.
- `analysis/collect_results.py`: gera CSV/JSON consolidados.
- `analysis/run_analysis.py`: gera graficos e relatorio.

## Como Rodar

Primeiro, compute unit:

```powershell
python .\parameter_optimization\main.py --config-path .\parameter_optimization\configs\01_compute_unit_sweep.json
```

Depois, memoria:

```powershell
python .\parameter_optimization\main.py --config-path .\parameter_optimization\configs\02_memory_access_sweep.json
```

Rodar tudo que esta em `configs/` e comparar:

```powershell
.\run_all_experiments.ps1
```

Smoke test sem Quartus/simulacao:

```powershell
python .\parameter_optimization\main.py --config-path .\parameter_optimization\configs\01_compute_unit_sweep.json --skip-simulation --skip-quartus --run-limit 1
```

## Saidas

Tudo fica em:

```text
parameter_optimization/results/<experiment_name>/
```

Principais arquivos:

- `experiment_results.csv`
- `experiment_summary.json`
- `resource_speed_analysis.json`
- `analysis_report.md`
- `plots/*.png`

Comparacao global:

- `results/compare_experiments/all_experiment_results.csv`
- `results/compare_experiments/comparison_summary.json`
- `results/compare_experiments/comparison_report.md`
- `results/compare_experiments/plots/*.png`

## Parametros

Conectados no sweep compute-only: `TILE_SIZE`, `NUM_MACS`, `DATA_WIDTH`, `ACC_WIDTH`, `MAC_PIPELINE_STAGES`.

Conectados no top completo: `N`, `TILE_SIZE`, `NUM_MACS`, `DATA_WIDTH`, `ACC_WIDTH`, `MEM_TYPE`, `DATAFLOW`, `BUFFERING_MODE`, `MEMORY_BURST_LEN`, `MAC_PIPELINE_STAGES`, `MEMORY_BANKS_A`, `MEMORY_BANKS_B`, `SDRAM_ADDR_W`, `SDRAM_DATA_W`, `SDRAM_SIMULATION_MODEL`, `ACCUMULATE_C`.
