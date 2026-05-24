# Parameter Optimization

Modulo de experimentos para varrer parametros arquiteturais, compilar no Quartus, coletar metricas, analisar recursos/desempenho e gerar graficos.

## Configuracoes

- `configs/01_compute_sweep.json`: `tile_size` x `num_macs`.
- `configs/02_memory_sweep.json`: parametros de memoria como metadados.
- `configs/03_timing_sweep.json`: pipeline/bancos como metadados.
- `configs/04_precision_sweep.json`: `DATA_WIDTH` x `ACC_WIDTH`.

## Rodar

Da raiz do projeto:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\parameter_optimization\run_sdram_arch_experiments.ps1 -ConfigPath .\parameter_optimization\configs\01_compute_sweep.json
```

Smoke test sem simular nem compilar:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\parameter_optimization\run_sdram_arch_experiments.ps1 -ConfigPath .\parameter_optimization\configs\01_compute_sweep.json -SkipSimulation -SkipQuartus -RunLimit 1
```

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

## Parametros RTL

Conectados ao RTL atual: `N`, `TILE_SIZE`, `NUM_MACS`, `DATA_WIDTH`, `ACC_WIDTH`.

Metadados por enquanto: `MEM_TYPE`, `DATAFLOW`, `BUFFERING_MODE`, `MEMORY_BURST_LEN`, `MAC_PIPELINE_STAGES`, `MEMORY_BANKS_A`, `MEMORY_BANKS_B`.
