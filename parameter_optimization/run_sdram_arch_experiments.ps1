param(
    [Parameter(Mandatory=$true)]
    [string]$ConfigPath,
    [switch]$SkipSimulation,
    [switch]$SkipQuartus
)

$ErrorActionPreference = "Stop"

$workspaceRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$paramOptDir = Join-Path $workspaceRoot "parameter_optimization"
$ConfigPathAbs = if ([System.IO.Path]::IsPathRooted($ConfigPath)) { $ConfigPath } else { Join-Path (Get-Location) $ConfigPath }

if (-not (Test-Path $ConfigPathAbs)) {
    throw "Arquivo de configuracao nao encontrado: $ConfigPathAbs"
}

$configData = Get-Content $ConfigPathAbs | ConvertFrom-Json
$experimentName = $configData.experiment_name
if ([string]::IsNullOrWhiteSpace($experimentName)) {
    throw "O JSON de configuracao deve conter 'experiment_name'."
}

$resultsDir = Join-Path $paramOptDir "results\$experimentName"
$runsDir = Join-Path $resultsDir "runs"
New-Item -ItemType Directory -Force -Path $runsDir | Out-Null

$defaults = $configData.defaults
$sweep = $configData.sweep

Write-Host "Iniciando experimento: $experimentName"
Write-Host "Descricao: $($configData.description)"

$runIndex = 1
foreach ($sweepItem in $sweep) {
    $runConfig = @{}
    
    # Apply defaults
    if ($null -ne $defaults) {
        foreach ($prop in $defaults.psobject.properties) {
            $runConfig[$prop.Name] = $prop.Value
        }
    }
    
    # Apply sweep item overrides
    foreach ($prop in $sweepItem.psobject.properties) {
        $runConfig[$prop.Name] = $prop.Value
    }
    
    $runId = "run_$($runIndex.ToString('000'))"
    $runDir = Join-Path $runsDir $runId
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null
    
    $runConfigJson = Join-Path $runDir "config.json"
    $runConfig | ConvertTo-Json -Depth 5 | Set-Content -Path $runConfigJson
    
    # Validation against RTL generics
    $validGenerics = @("N", "TILE_SIZE", "NUM_MACS", "DATA_WIDTH", "ACC_WIDTH")
    foreach ($key in $runConfig.Keys) {
        if ($key -ne "MEM_TYPE" -and $key -ne "DATAFLOW" -and $key -ne "TOP_ENTITY" -and $key -notin $validGenerics) {
            Write-Warning "Parametro '$key' existe so no JSON e nao esta conectado ao RTL. Sera tratado como metadado."
        }
    }
    
    Write-Host "-> Executando $runId ($($sweepItem | ConvertTo-Json -Compress))"
    
    # TODO: generate wrapper VHDL based on $runConfig, call quartus_sh/quartus_map, run tests, etc.
    # We will simulate Quartus compilation dummy text for the mock if skipping
    
    $quartusOutDir = Join-Path $runDir "quartus_output"
    New-Item -ItemType Directory -Force -Path $quartusOutDir | Out-Null
    
    # Emulating quartus output
    $dummyReport = Join-Path $quartusOutDir "matrix_accelerator.map.rpt"
    "Fmax: 100.0 MHz`nALMs: 50%`n" | Set-Content -Path $dummyReport
    
    # Call python parse_quartus_reports
    $pythonCmd = "python"
    $parseScript = Join-Path $paramOptDir "parse_quartus_reports.py"
    & $pythonCmd $parseScript --run-dir $runDir
    
    $runIndex++
}

# Collect results
$collectScript = Join-Path $paramOptDir "collect_results.py"
& $pythonCmd $collectScript --runs-dir $runsDir --output-csv (Join-Path $resultsDir "experiment_results.csv")

# Run analysis
$analysisScript = Join-Path $paramOptDir "analysis\run_analysis.py"
& $pythonCmd $analysisScript --experiment-dir $resultsDir
