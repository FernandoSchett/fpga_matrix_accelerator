param(
    [string]$Only = "",
    [string]$EnvFile = "",
    [switch]$Quartus,
    [switch]$QuartusFull,
    [switch]$SkipGenerate
)

$ErrorActionPreference = "Stop"

$TestsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $TestsDir
$TestbenchDir = Join-Path $TestsDir "testbenchs"

$ProjectName = "fpga_matrix_accelerator"
$PassMarker = "SIM_RESULT: PASS"

Set-Location $ProjectDir

if ($EnvFile -eq "") {
    $EnvFile = Join-Path $ProjectDir "py_matrix_host\.env"
}

function Get-ProjectRelativePath {
    param([string]$Path)

    $fullPath = (Resolve-Path -LiteralPath $Path).Path
    $rootPath = (Resolve-Path -LiteralPath $ProjectDir).Path

    if ($fullPath.StartsWith($rootPath)) {
        return $fullPath.Substring($rootPath.Length + 1).Replace("\", "/")
    }

    return $fullPath.Replace("\", "/")
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

    $normalized = $PathValue.Replace("\", "/")

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

    $exe = $Command[0]
    $cmdArgs = @()

    if ($Command.Count -gt 1) {
        $cmdArgs = $Command[1..($Command.Count - 1)]
    }

    & $exe @cmdArgs

    if ($LASTEXITCODE -ne 0) {
        throw "Comando falhou com exit code ${LASTEXITCODE}: $($Command -join ' ')"
    }
}

function Invoke-CapturedStep {
    param([string[]]$Command)

    Write-Host ""
    Write-Host ("$ " + ($Command -join " "))

    $exe = $Command[0]
    $cmdArgs = @()

    if ($Command.Count -gt 1) {
        $cmdArgs = $Command[1..($Command.Count - 1)]
    }

    $output = & $exe @cmdArgs 2>&1
    $exitCode = $LASTEXITCODE

    $output | ForEach-Object {
        Write-Host $_
    }

    if ($exitCode -ne 0) {
        throw "Comando falhou com exit code ${exitCode}: $($Command -join ' ')"
    }

    return ($output -join [Environment]::NewLine)
}

function Invoke-VhdlCompilation {
    param(
        [string[]]$Sources,
        [string]$Vcom
    )

    $pending = @($Sources)
    $maxPasses = 5

    for ($pass = 1; $pass -le $maxPasses -and $pending.Count -gt 0; $pass++) {
        Write-Host ""
        Write-Host "Compilacao VHDL - passada $pass"

        $nextPending = @()
        $failures = @{}

        foreach ($source in $pending) {
            if (-not (Test-Path -LiteralPath $source)) {
                throw "Arquivo VHDL nao encontrado: $source"
            }

            Write-Host ""
            Write-Host "$ $Vcom -2008 -work work $source"

            $output = & $Vcom "-2008" "-work" "work" $source 2>&1
            $exitCode = $LASTEXITCODE

            $output | ForEach-Object {
                Write-Host $_
            }

            if ($exitCode -ne 0) {
                $nextPending += $source
                $failures[$source] = ($output -join [Environment]::NewLine)
            }
        }

        if ($nextPending.Count -eq 0) {
            return
        }

        if ($nextPending.Count -eq $pending.Count) {
            Write-Host ""
            Write-Host "Os seguintes arquivos nao compilaram:"
            $nextPending | ForEach-Object {
                Write-Host "  $_"
            }

            throw "A compilacao VHDL nao avancou. Verifique erros de sintaxe ou dependencias ausentes."
        }

        $pending = @($nextPending)
    }

    if ($pending.Count -gt 0) {
        throw "A compilacao VHDL nao terminou apos $maxPasses passadas."
    }
}

function Get-RtlSources {
    if (-not (Test-Path -LiteralPath "rtl")) {
        throw "Pasta rtl nao encontrada na raiz do projeto."
    }

    return Get-ChildItem -Path "rtl" -Recurse -Filter "*.vhd" |
        Sort-Object FullName |
        ForEach-Object {
            Get-ProjectRelativePath -Path $_.FullName
        }
}

function Get-EnvGenericArgs {
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
        throw "Config invalida: COLS_A precisa ser igual a ROWS_B."
    }

    if (($rowsA -ne 2) -or ($colsA -ne 2) -or ($rowsB -ne 2) -or ($colsB -ne 2)) {
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

    return @(
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

function Invoke-Testbench {
    param(
        [string]$Entity,
        [bool]$UseEnvGenerics = $false,
        [bool]$GenerateVectors = $false
    )

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "Rodando testbench: $Entity"
    Write-Host "============================================================"

    $tbPath = Join-Path $TestbenchDir "$Entity.vhd"

    if (-not (Test-Path -LiteralPath $tbPath)) {
        throw "Arquivo de testbench nao encontrado: $tbPath"
    }

    $genericArgs = @()

    if ($UseEnvGenerics) {
        if ($GenerateVectors -and -not $SkipGenerate) {
            Invoke-Step -Command @("python", "py_matrix_host\main.py", "--env-file", $EnvFile)
        }

        $genericArgs = Get-EnvGenericArgs
    }

    $rtlSources = Get-RtlSources
    $tbRelativePath = Get-ProjectRelativePath -Path $tbPath

    $sources = @()
    $sources += $rtlSources
    $sources += $tbRelativePath

    $vlib = Find-Tool -Name "vlib"
    $vmap = Find-Tool -Name "vmap"
    $vcom = Find-Tool -Name "vcom"
    $vsim = Find-Tool -Name "vsim"

    if (Test-Path -LiteralPath "work") {
        Remove-Item -Recurse -Force "work"
    }

    Invoke-Step -Command @($vlib, "work")
    Invoke-Step -Command @($vmap, "work", "work")

    Invoke-VhdlCompilation -Sources $sources -Vcom $vcom

    $vsimCommand = @($vsim, "-c", "-quiet") + $genericArgs + @(
        "work.$Entity",
        "-do",
        "run -all; quit -f"
    )

    $transcript = Invoke-CapturedStep -Command $vsimCommand

    if ($transcript -notlike "*$PassMarker*") {
        throw "A simulacao terminou, mas nao encontrou o marcador de sucesso: $PassMarker"
    }

    Write-Host ""
    Write-Host "PASS: $Entity executado com sucesso."
}

$tests = @(
    [pscustomobject]@{
        Entity = "tb_matrix_mult_top"
        UseEnvGenerics = $true
        GenerateVectors = $true
    },
    [pscustomobject]@{
        Entity = "tb_matrix_mult_4x4_top"
        UseEnvGenerics = $false
        GenerateVectors = $false
    },
    [pscustomobject]@{
        Entity = "tb_matrix_mult_tiled_top"
        UseEnvGenerics = $false
        GenerateVectors = $false
    }
)

if ($Quartus) {
    $quartusMap = Find-QuartusTool -Name "quartus_map"
    Invoke-Step -Command @($quartusMap, "--read_settings_files=on", "--write_settings_files=off", $ProjectName, "-c", $ProjectName)
}

if ($QuartusFull) {
    $quartusSh = Find-QuartusTool -Name "quartus_sh"
    Invoke-Step -Command @($quartusSh, "--flow", "compile", $ProjectName)
}

if ($Only -ne "") {
    $tests = @($tests | Where-Object { $_.Entity -eq $Only })

    if ($tests.Count -eq 0) {
        throw "Testbench desconhecido: $Only"
    }
}

foreach ($test in $tests) {
    Invoke-Testbench `
        -Entity $test.Entity `
        -UseEnvGenerics $test.UseEnvGenerics `
        -GenerateVectors $test.GenerateVectors
}

Write-Host ""
Write-Host "PASS: todos os testbenchs selecionados passaram."