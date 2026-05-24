param(
    [switch]$SkipSimulation,
    [switch]$SkipQuartus
)

$ErrorActionPreference = "Stop"

$args = @{}
if ($SkipSimulation) { $args.SkipSimulation = $true }
if ($SkipQuartus) { $args.SkipQuartus = $true }

& (Join-Path $PSScriptRoot "scripts\run_tiled_arch_experiments.ps1") @args
