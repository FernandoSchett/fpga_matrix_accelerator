param(
    [string[]]$ConfigPath = @(),
    [string]$ConfigsDir = ".\parameter_optimization\configs",
    [switch]$SkipSimulation,
    [switch]$SkipQuartus,
    [switch]$SkipAnalysis,
    [switch]$SkipCompare,
    [switch]$NoResume,
    [int]$RunLimit = 0,
    [int]$VsimRetryCount = 120,
    [int]$VsimRetrySeconds = 30
)

$ErrorActionPreference = "Stop"

$projectRoot = $PSScriptRoot
$runExperimentScript = Join-Path $projectRoot "parameter_optimization\run_experiment.ps1"
$compareScript = Join-Path $projectRoot "parameter_optimization\compare_experiments.py"
$pythonExe = (Get-Command python -ErrorAction Stop).Source

function Resolve-ExperimentConfig {
    param([string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return (Resolve-Path -LiteralPath $PathValue).Path
    }

    return (Resolve-Path -LiteralPath (Join-Path $projectRoot $PathValue)).Path
}

function Get-ExperimentNameFromConfig {
    param([string]$PathValue)

    $configData = Get-Content -LiteralPath $PathValue -Raw | ConvertFrom-Json
    if (-not [string]::IsNullOrWhiteSpace($configData.experiment_name)) {
        return [string]$configData.experiment_name
    }
    return [System.IO.Path]::GetFileNameWithoutExtension($PathValue)
}

if ($ConfigPath.Count -gt 0) {
    $configs = @($ConfigPath | ForEach-Object { Resolve-ExperimentConfig -PathValue $_ })
} else {
    $configsDirAbs = Resolve-ExperimentConfig -PathValue $ConfigsDir
    $configs = @(
        Get-ChildItem -LiteralPath $configsDirAbs -File -Filter "*.json" |
            Sort-Object Name |
            Select-Object -ExpandProperty FullName
    )
}

if ($configs.Count -eq 0) {
    throw "Nenhum JSON de experimento encontrado."
}

$experimentNames = @()
foreach ($config in $configs) {
    $experimentName = Get-ExperimentNameFromConfig -PathValue $config
    $experimentNames += $experimentName
    Write-Host ""
    Write-Host "=== Rodando experimento: $experimentName ==="
    Write-Host "Config: $config"

    $experimentParameters = @{
        ConfigPath = $config
        VsimRetryCount = $VsimRetryCount
        VsimRetrySeconds = $VsimRetrySeconds
    }
    if ($SkipSimulation) { $experimentParameters.SkipSimulation = $true }
    if ($SkipQuartus) { $experimentParameters.SkipQuartus = $true }
    if ($SkipAnalysis) { $experimentParameters.SkipAnalysis = $true }
    if ($NoResume) { $experimentParameters.NoResume = $true }
    if ($RunLimit -gt 0) { $experimentParameters.RunLimit = $RunLimit }

    & $runExperimentScript @experimentParameters
}

if (-not $SkipCompare) {
    Write-Host ""
    Write-Host "=== Comparando experimentos ==="
    $compareArguments = @(
        $compareScript,
        "--experiments"
    ) + $experimentNames + @(
        "--refresh-analysis"
    )
    & $pythonExe @compareArguments
    if ($LASTEXITCODE -ne 0) {
        throw "compare_experiments.py falhou com codigo $LASTEXITCODE."
    }
}
