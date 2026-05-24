param(
    [Parameter(Mandatory = $true)]
    [string]$TestName,

    [Parameter(Mandatory = $true)]
    [string]$TestbenchEntity,

    [Parameter(Mandatory = $true)]
    [string[]]$Sources,

    [string]$EnvFile = "",
    [switch]$GenerateVectors,
    [switch]$SkipGenerate,
    [switch]$UseEnvGenerics,
    [switch]$Require2x2Env,
    [switch]$Quartus,
    [switch]$QuartusFull
)

$ErrorActionPreference = "Stop"

$TestsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $TestsDir
$ProjectName = "fpga_matrix_accelerator"
$PassMarker = "SIM_RESULT: PASS"

Set-Location $ProjectDir

if ($EnvFile -eq "") {
    $EnvFile = Join-Path $ProjectDir "py_matrix_host\.env"
}

function Read-DotEnv {
    param([string]$Path)

    $config = @{}

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Arquivo .env nao encontrado: $Path"
    }

    foreach ($rawLine in Get-Content -LiteralPath $Path) {
        $line = $rawLine.Trim()

        if ($line.Length -eq 0 -or $line.StartsWith("#")) {
            continue
        }

        $parts = $line.Split("=", 2)
        if ($parts.Count -ne 2) {
            throw "Linha invalida no .env: $rawLine"
        }

        $key = $parts[0].Trim()
        $value = $parts[1].Trim().Trim('"').Trim("'")

        if ($key.Length -eq 0) {
            throw "Chave vazia no .env: $rawLine"
        }

        $config[$key] = $value
    }

    return $config
}

function Get-ConfigValue {
    param(
        [hashtable]$Config,
        [string]$Key,
        [string]$Default
    )

    if ($Config.ContainsKey($Key)) {
        return $Config[$Key]
    }

    return $Default
}

function Get-ConfigInt {
    param(
        [hashtable]$Config,
        [string]$Key,
        [int]$Default
    )

    $value = Get-ConfigValue -Config $Config -Key $Key -Default ([string]$Default)
    return [int]$value
}

function Convert-MatrixHostPathForSimulation {
    param([string]$PathValue)

    $normalized = $PathValue.Replace('\', '/')

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $normalized
    }

    if ($normalized.StartsWith("py_matrix_host/")) {
        return $normalized
    }

    return "py_matrix_host/$normalized"
}

function Find-Tool {
    param(
        [string]$Name,
        [string]$FallbackPath = ""
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    if ($FallbackPath -ne "" -and (Test-Path -LiteralPath $FallbackPath)) {
        return $FallbackPath
    }

    throw "Ferramenta nao encontrada no PATH: $Name"
}

function Find-QuartusTool {
    param([string]$Name)

    return Find-Tool -Name $Name -FallbackPath "C:\altera_lite\25.1std\quartus\bin64\$Name.exe"
}

function Invoke-Step {
    param([string[]]$Command)

    Write-Host ""
    Write-Host ("$ " + ($Command -join " "))

    & $Command[0] $Command[1..($Command.Count - 1)]

    if ($LASTEXITCODE -ne 0) {
        throw "Comando falhou com exit code ${LASTEXITCODE}: $($Command -join ' ')"
    }
}

function Invoke-CapturedStep {
    param([string[]]$Command)

    Write-Host ""
    Write-Host ("$ " + ($Command -join " "))

    $output = & $Command[0] $Command[1..($Command.Count - 1)] 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }

    if ($exitCode -ne 0) {
        throw "Comando falhou com exit code ${exitCode}: $($Command -join ' ')"
    }

    return ($output -join [Environment]::NewLine)
}

Write-Host ""
Write-Host "============================================================"
Write-Host "Rodando testbench: $TestName"
Write-Host "Entidade: $TestbenchEntity"
Write-Host "============================================================"

$genericArgs = @()

if ($GenerateVectors -or $UseEnvGenerics -or $Require2x2Env) {
    $config = Read-DotEnv -Path $EnvFile

    $numTests = Get-ConfigInt -Config $config -Key "NUM_TESTS" -Default 1
    $dataWidth = Get-ConfigInt -Config $config -Key "DATA_WIDTH" -Default 16
    $accWidth = Get-ConfigInt -Config $config -Key "ACC_WIDTH" -Default 32
    $rowsA = Get-ConfigInt -Config $config -Key "ROWS_A" -Default 2
    $colsA = Get-ConfigInt -Config $config -Key "COLS_A" -Default 2
    $rowsB = Get-ConfigInt -Config $config -Key "ROWS_B" -Default $colsA
    $colsB = Get-ConfigInt -Config $config -Key "COLS_B" -Default 2
    $inputFileConfig = Get-ConfigValue -Config $config -Key "MATRIX_INPUT_FILE" -Default "matrix/matrix_inputs.txt"
    $outputFileConfig = Get-ConfigValue -Config $config -Key "MATRIX_OUTPUT_FILE" -Default "matrix/matrix_outputs.txt"
    $inputFile = Convert-MatrixHostPathForSimulation -PathValue $inputFileConfig
    $outputFile = Convert-MatrixHostPathForSimulation -PathValue $outputFileConfig

    if ($colsA -ne $rowsB) {
        throw "Config invalida: COLS_A precisa ser igual a ROWS_B para calcular A x B."
    }

    if ($Require2x2Env -and (($rowsA -ne 2) -or ($colsA -ne 2) -or ($rowsB -ne 2) -or ($colsB -ne 2))) {
        throw "Este testbench suporta somente A 2x2 e B 2x2. Ajuste ROWS_A=2, COLS_A=2, ROWS_B=2, COLS_B=2 no .env."
    }

    Write-Host "Configuracao:"
    Write-Host "  NUM_TESTS=$numTests"
    Write-Host "  DATA_WIDTH=$dataWidth"
    Write-Host "  ACC_WIDTH=$accWidth"
    Write-Host "  A=${rowsA}x${colsA}"
    Write-Host "  B=${rowsB}x${colsB}"
    Write-Host "  INPUT=$inputFile"
    Write-Host "  OUTPUT=$outputFile"

    if ($GenerateVectors -and -not $SkipGenerate) {
        Invoke-Step @("python", "py_matrix_host\main.py", "--env-file", $EnvFile)
    }

    if ($UseEnvGenerics) {
        $genericArgs = @(
            "-gDATA_WIDTH=$dataWidth",
            "-gACC_WIDTH=$accWidth",
            "-gNUM_TESTS=$numTests",
            "-gROWS_A=$rowsA",
            "-gCOLS_A=$colsA",
            "-gROWS_B=$rowsB",
            "-gCOLS_B=$colsB",
            "-gINPUT_FILE=$inputFile",
            "-gOUTPUT_FILE=$outputFile"
        )
    }
}

if ($Quartus) {
    $quartusMap = Find-QuartusTool -Name "quartus_map"
    Invoke-Step @($quartusMap, "--read_settings_files=on", "--write_settings_files=off", $ProjectName, "-c", $ProjectName)
}

if ($QuartusFull) {
    $quartusSh = Find-QuartusTool -Name "quartus_sh"
    Invoke-Step @($quartusSh, "--flow", "compile", $ProjectName)
}

$vlib = Find-Tool -Name "vlib"
$vmap = Find-Tool -Name "vmap"
$vcom = Find-Tool -Name "vcom"
$vsim = Find-Tool -Name "vsim"

if (-not (Test-Path -LiteralPath "work")) {
    Invoke-Step @($vlib, "work")
}

Invoke-Step @($vmap, "work", "work")

foreach ($source in $Sources) {
    Invoke-Step @($vcom, "-2008", "-work", "work", $source)
}

$vsimCommand = @($vsim, "-c", "-quiet") + $genericArgs + @(
    "work.$TestbenchEntity",
    "-do",
    "run -all; quit -f"
)

$transcript = Invoke-CapturedStep $vsimCommand

if ($transcript -notlike "*$PassMarker*") {
    throw "A simulacao terminou, mas nao encontrou o marcador de sucesso: $PassMarker"
}

Write-Host ""
Write-Host "PASS: $TestName executado com sucesso."
