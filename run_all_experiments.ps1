param(
    [string]$ConfigPath = ".\parameter_optimization\configs\01_compute_sweep.json",
    [switch]$SkipSimulation,
    [switch]$SkipQuartus,
    [switch]$SkipAnalysis,
    [int]$RunLimit = 0
)

$ErrorActionPreference = "Stop"

$experimentScript = Join-Path $PSScriptRoot "parameter_optimization\run_sdram_arch_experiments.ps1"

$experimentParameters = @{
    ConfigPath = $ConfigPath
}

if ($SkipSimulation) { $experimentParameters.SkipSimulation = $true }
if ($SkipQuartus) { $experimentParameters.SkipQuartus = $true }
if ($SkipAnalysis) { $experimentParameters.SkipAnalysis = $true }
if ($RunLimit -gt 0) { $experimentParameters.RunLimit = $RunLimit }

& $experimentScript @experimentParameters
