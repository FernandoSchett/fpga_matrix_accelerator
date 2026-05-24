# fpga_matrix_accelerator

Acelerador VHDL para multiplicacao densa de matrizes inteiras no Quartus,
mirando a placa DE0-CV / Cyclone V `5CEBA4F23C7`.

## Arquiteturas

- `rtl/matriz_4x4/`: arquitetura 4x4 funcional, validada por testbench.
- `rtl/matrix_tiled/`: arquitetura parametrizavel com RAM interna inferivel.

O top novo e `matrix_mult_tiled_top`, com generics:

- `N`
- `TILE_SIZE`
- `NUM_MACS`
- `DATA_WIDTH`
- `ACC_WIDTH`

A configuracao-alvo inicial e `N=128`, `DATA_WIDTH=8`, `ACC_WIDTH=32` e
memoria interna para `RAM_A`, `RAM_B` e `RAM_C`.

## Simulacao

Rodar todos os testbenches:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_testbenchs.ps1 -SkipGenerate
```

Rodar apenas o testbench parametrizavel:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\testes\run_tb_matrix_mult_tiled_top.ps1 -N 8 -TileSize 4 -NumMacs 4 -DataWidth 8 -AccWidth 32
```

O testbench tiled imprime:

```text
Ciclos de execucao: <valor>
```

## Experimentos

O script abaixo gera uma revisao Quartus por configuracao, roda simulacao,
extrai ciclos e gera um CSV de comparacao:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\experiments\run_tiled_arch_experiments.ps1
```

Saida esperada:

```text
experiments/results/matrix_tiled_experiments.csv
```
