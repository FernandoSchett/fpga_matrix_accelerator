param(
    [string]$Only = "",
    [int]$N = 0,
    [int]$TileSize = 0,
    [int]$NumMacs = 0,
    [int]$DataWidth = 0,
    [int]$AccWidth = 0,
    [switch]$Quartus,
    [switch]$QuartusFull
)

$ErrorActionPreference = "Stop"

$TestsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $TestsDir
$TestbenchDir = Join-Path $TestsDir "testbenchs"
$ProjectName = "fpga_matrix_accelerator"
$PassMarker = "SIM_RESULT: PASS"

Set-Location $ProjectDir

function Get-ProjectRelativePath {
    param([string]$Path)

    $fullPath = (Resolve-Path -LiteralPath $Path).Path
    $rootPath = (Resolve-Path -LiteralPath $ProjectDir).Path

    if ($fullPath.StartsWith($rootPath)) {
        return $fullPath.Substring($rootPath.Length + 1).Replace("\", "/")
    }

    return $fullPath.Replace("\", "/")
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
    $output | ForEach-Object { Write-Host $_ }

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
    $maxPasses = 6

    for ($pass = 1; $pass -le $maxPasses -and $pending.Count -gt 0; $pass++) {
        Write-Host ""
        Write-Host "Compilacao VHDL - passada $pass"

        $nextPending = @()

        foreach ($source in $pending) {
            if (-not (Test-Path -LiteralPath $source)) {
                throw "Arquivo VHDL nao encontrado: $source"
            }

            Write-Host ""
            Write-Host "$ $Vcom -2008 -work work $source"

            $output = & $Vcom "-2008" "-work" "work" $source 2>&1
            $exitCode = $LASTEXITCODE
            $output | ForEach-Object { Write-Host $_ }

            if ($exitCode -ne 0) {
                $nextPending += $source
            }
        }

        if ($nextPending.Count -eq 0) {
            return
        }

        if ($nextPending.Count -eq $pending.Count) {
            $nextPending | ForEach-Object { Write-Host "  $_" }
            throw "A compilacao VHDL nao avancou. Verifique erros de sintaxe ou dependencias."
        }

        $pending = @($nextPending)
    }

    if ($pending.Count -gt 0) {
        throw "A compilacao VHDL nao terminou apos $maxPasses passadas."
    }
}

function Get-RtlSources {
    $ordered = @(
        "rtl/common/matrix_tiled_pkg.vhd",
        "rtl/common/matrix_accel_config_pkg.vhd",
        "rtl/common/perf_counters.vhd",
        "rtl/common/accelerator_status_leds.vhd",
        "rtl/compute/mac_unit.vhd",
        "rtl/compute/matrix_tiled_compute_core.vhd",
        "rtl/memory/matrix_single_port_ram.vhd",
        "rtl/compute/matrix_mult_tiled_core.vhd",
        "rtl/control/command_interface.vhd",
        "rtl/uart/uart_rx.vhd",
        "rtl/uart/uart_tx.vhd",
        "rtl/top/matrix_accelerator_full_top.vhd"
    )

    foreach ($source in $ordered) {
        if (Test-Path -LiteralPath $source) {
            $source
        }
    }
}

function Invoke-Testbench {
    param([string]$Entity)

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "Rodando testbench: $Entity"
    Write-Host "============================================================"

    $tbPath = Join-Path $TestbenchDir "$Entity.vhd"
    if (-not (Test-Path -LiteralPath $tbPath)) {
        throw "Arquivo de testbench nao encontrado: $tbPath"
    }

    $vlib = Find-Tool -Name "vlib"
    $vmap = Find-Tool -Name "vmap"
    $vcom = Find-Tool -Name "vcom"
    $vsim = Find-Tool -Name "vsim"

    if (Test-Path -LiteralPath "work") {
        Remove-Item -Recurse -Force "work"
    }

    Invoke-Step -Command @($vlib, "work")
    Invoke-Step -Command @($vmap, "work", "work")

    $sources = @(Get-RtlSources)
    $sources += Get-ProjectRelativePath -Path $tbPath
    Invoke-VhdlCompilation -Sources $sources -Vcom $vcom

    $genericArgs = @()
    if ($Entity -eq "tb_matrix_mult_tiled_core") {
        if ($N -gt 0) { $genericArgs += "-gN=$N" }
        if ($TileSize -gt 0) { $genericArgs += "-gTILE_SIZE=$TileSize" }
        if ($NumMacs -gt 0) { $genericArgs += "-gNUM_MACS=$NumMacs" }
        if ($DataWidth -gt 0) { $genericArgs += "-gDATA_WIDTH=$DataWidth" }
        if ($AccWidth -gt 0) { $genericArgs += "-gACC_WIDTH=$AccWidth" }
    }

    $vsimCommand = @(
        $vsim,
        "-c",
        "-quiet"
    ) + $genericArgs + @(
        "work.$Entity",
        "-do",
        "run -all; quit -f"
    )

    $transcript = Invoke-CapturedStep -Command $vsimCommand

    if ($transcript -notlike "*$PassMarker*") {
        throw "A simulacao terminou, mas nao encontrou o marcador: $PassMarker"
    }

    Write-Host ""
    Write-Host "PASS: $Entity executado com sucesso."
}

$tests = @(
    "tb_matrix_mult_tiled_core",
    "tb_tile_compute_engine",
    "tb_perf_counters",
    "tb_command_interface",
    "tb_accelerator_status_leds",
    "tb_matrix_accelerator_full_top"
)

if ($Only -ne "") {
    $tests = @($tests | Where-Object { $_ -eq $Only })
    if ($tests.Count -eq 0) {
        throw "Testbench desconhecido: $Only"
    }
}

if ($Quartus) {
    $quartusMap = Find-QuartusTool -Name "quartus_map"
    Invoke-Step -Command @($quartusMap, "--read_settings_files=on", "--write_settings_files=off", $ProjectName, "-c", $ProjectName)
}

if ($QuartusFull) {
    $quartusSh = Find-QuartusTool -Name "quartus_sh"
    Invoke-Step -Command @($quartusSh, "--flow", "compile", $ProjectName)
}

foreach ($test in $tests) {
    Invoke-Testbench -Entity $test
}

Write-Host ""
Write-Host "PASS: todos os testbenchs selecionados passaram."
