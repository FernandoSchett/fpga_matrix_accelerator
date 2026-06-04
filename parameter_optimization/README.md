# Parameter Optimization

Modulo de experimentos para varrer parametros arquiteturais, compilar no Quartus, coletar metricas, analisar recursos/desempenho e gerar graficos.

## Configuracoes

- `configs/01_compute_sweep.json`: `tile_size` x `num_macs`.
- `configs/02_run18_alm_boundary_sweep.json`: varia `ACC_WIDTH` e pipeline ao redor da melhor config do compute sweep.
- `configs/03_run18_memory_banking_sweep.json`: varia bancos/buffering para estudar memoria.
- `configs/04_run18_elite_combo_sweep.json`: combina as melhores hipoteses de compute, precisao e memoria.

## Rodar

Rodar um experimento a partir de um JSON:

```powershell
.\parameter_optimization\run_experiment.ps1 -ConfigPath .\parameter_optimization\configs\01_compute_sweep.json
```

Se o experimento parar no meio, rode o mesmo comando de novo. O runner pula os runs ja processados, descarta o ultimo run existente e recomeca dele.

Para forcar do inicio:

```powershell
.\parameter_optimization\run_experiment.ps1 -ConfigPath .\parameter_optimization\configs\01_compute_sweep.json -NoResume
```

Smoke test sem simular nem compilar:

```powershell
.\parameter_optimization\run_experiment.ps1 -ConfigPath .\parameter_optimization\configs\01_compute_sweep.json -SkipSimulation -SkipQuartus -RunLimit 1
```

Rodar todos os JSONs em `configs/` e comparar no final:

```powershell
.\run_all_experiments.ps1
```

Comparar todos os experimentos ja gerados e achar a melhor configuracao global:

```powershell
python .\parameter_optimization\compare_experiments.py
```

Comparar sweeps especificos:

```powershell
python .\parameter_optimization\compare_experiments.py --experiments 02_run18_alm_boundary_sweep 03_run18_memory_banking_sweep 04_run18_elite_combo_sweep
```

Recalcular os CSVs a partir das pastas `runs/` antes de comparar:

```powershell
python .\parameter_optimization\compare_experiments.py --refresh
```

Para coletar consumo estimado, rode ou reexecute o sweep com Quartus. O runner gera QSF com `FLOW_ENABLE_POWER_ANALYZER ON`, entao o `quartus_sh --flow compile` tambem executa o Power Analyzer:

```powershell
.\parameter_optimization\run_experiment.ps1 -ConfigPath .\parameter_optimization\configs\01_compute_sweep.json -NoResume
```

Resultados antigos em que o log diz `Skipped module Power Analyzer` nao possuem potencia. Neles, `--refresh` so atualiza o CSV com campos vazios; para preencher `power_total_mw`, `gops_per_watt` e energia, recompile o experimento.

## Saidas

Tudo fica em:

```text
parameter_optimization/results/<experiment_name>/
```

Arquivos principais:

- `experiment_results.csv`
- `experiment_summary.json`
- `resource_speed_analysis.json`
- `analysis_report.md`
- `plots/*.png`

Colunas principais novas:

- `power_total_mw`, `power_core_dynamic_mw`, `power_core_static_mw`, `power_io_mw`: potencia estimada pelo Quartus Power Analyzer.
- `gops_per_watt`: GOPS efetivo aproximado dividido pela potencia total em watts.
- `energy_est_mj`: energia estimada por execucao completa da matriz, calculada como potencia total x tempo de execucao.
- `energy_per_op_approx_nj`, `energy_per_op_exact_nj`: energia estimada por operacao.

Comparacao global:

- `results/compare_experiments/all_experiment_results.csv`
- `results/compare_experiments/comparison_summary.json`
- `results/compare_experiments/comparison_report.md`
- `results/compare_experiments/plots/*.png`

## Entradas

- `main.py`: entrada Python para rodar um experimento.
- `run_experiment.ps1`: runner PowerShell para um experimento.
- `compare_experiments.py`: compara os CSVs dos experimentos e escolhe a melhor configuracao global.
- `analysis/parse_quartus_reports.py`: extrai dados dos relatorios Quartus.
- `analysis/collect_results.py`: consolida runs em CSV/JSON.
- `analysis/run_analysis.py`: gera analise e graficos por experimento.

## Parametros RTL

Conectados ao RTL atual: `N`, `TILE_SIZE`, `NUM_MACS`, `DATA_WIDTH`, `ACC_WIDTH`, `MEM_TYPE`, `DATAFLOW`, `BUFFERING_MODE`, `MEMORY_BURST_LEN`, `MAC_PIPELINE_STAGES`, `MEMORY_BANKS_A`, `MEMORY_BANKS_B`.
