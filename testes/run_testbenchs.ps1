param(
    [string]$Only = "",
    [int]$N = 0,
    [int]$TileSize = 0,
    [int]$NumMacs = 0,
    [int]$DataWidth = 0,
    [int]$AccWidth = 0,
    [int]$MemoryBurstLen = 0,
    [int]$MacPipelineStages = -1,
    [int]$MemoryBanksA = 0,
    [int]$MemoryBanksB = 0,
    [int]$VsimRetryCount = 10,
    [int]$VsimRetrySeconds = 30,
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
    param(
        [string[]]$Command,
        [int]$MaxAttempts = 1,
        [int]$RetryDelaySeconds = 0
    )

    Write-Host ""
    Write-Host ("$ " + ($Command -join " "))

    $exe = $Command[0]
    $cmdArgs = @()
    if ($Command.Count -gt 1) {
        $cmdArgs = $Command[1..($Command.Count - 1)]
    }

    $attempt = 1
    while ($true) {
        if ($attempt -gt 1) {
            Write-Host ""
            Write-Host "Tentativa $attempt de $MaxAttempts..."
        }

        $previousErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"
            $output = & $exe @cmdArgs 2>&1 | ForEach-Object { "$_" }
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }

        $output | ForEach-Object { Write-Host $_ }
        $transcriptText = ($output -join [Environment]::NewLine)
        $licenseBusy = $transcriptText -match "License checkout has been disallowed" -or
                       $transcriptText -match "only one session is allowed"

        if ($exitCode -eq 0) {
            return $transcriptText
        }

        if ($licenseBusy -and $attempt -lt $MaxAttempts) {
            Write-Warning "Licenca do Questa ocupada por outra sessao. Aguardando $RetryDelaySeconds segundos antes de tentar novamente."
            Start-Sleep -Seconds $RetryDelaySeconds
            $attempt++
            continue
        }

        if ($licenseBusy) {
            throw "Questa/ModelSim nao conseguiu abrir licenca apos $MaxAttempts tentativa(s). Feche ou aguarde outra simulacao terminar e rode novamente."
        }

        throw "Comando falhou com exit code ${exitCode}: $($Command -join ' ')"
    }
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
        "rtl/common/sigma_hex_display.vhd",
        "rtl/memory/sdram_bus_if.vhd",
        "rtl/compute/mac_unit.vhd",
        "rtl/compute/matrix_tiled_compute_core.vhd",
        "rtl/memory/matrix_single_port_ram.vhd",
        "rtl/memory/matrix_memory_map.vhd",
        "rtl/memory/tile_buffer_m10k.vhd",
        "rtl/memory/sdram_ip_core.vhd",
        "rtl/memory/sdram_controller_wrapper.vhd",
        "rtl/control/memory_manager.vhd",
        "rtl/control/tile_loader.vhd",
        "rtl/control/tile_writer.vhd",
        "rtl/control/sdram_tile_scheduler.vhd",
        "rtl/compute/matrix_mult_tiled_core.vhd",
        "rtl/compute/matrix_mult_sdram_tiled_core.vhd",
        "rtl/control/command_interface.vhd",
        "rtl/uart/uart_rx.vhd",
        "rtl/uart/uart_tx.vhd",
        "rtl/uart/uart_byte_fifo.vhd",
        "rtl/debug/signaltap_debug_core.vhd",
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

    $alteraMfLib = "C:\altera_lite\25.1std\questa_fse\intel\vhdl\altera_mf"
    if (Test-Path -LiteralPath $alteraMfLib) {
        Invoke-Step -Command @($vmap, "altera_mf", $alteraMfLib)
    }

    $sources = @(Get-RtlSources)
    $sources += Get-ProjectRelativePath -Path $tbPath
    Invoke-VhdlCompilation -Sources $sources -Vcom $vcom

    $genericArgs = @()
    if (
        $Entity -eq "tb_matrix_mult_tiled_core" -or
        $Entity -eq "tb_matrix_mult_tiled_core_perf" -or
        $Entity -eq "tb_matrix_accelerator_full_top_uart_protocol"
    ) {
        if ($N -gt 0) { $genericArgs += "-gN=$N" }
        if ($TileSize -gt 0) { $genericArgs += "-gTILE_SIZE=$TileSize" }
        if ($NumMacs -gt 0) { $genericArgs += "-gNUM_MACS=$NumMacs" }
        if ($DataWidth -gt 0) { $genericArgs += "-gDATA_WIDTH=$DataWidth" }
        if ($AccWidth -gt 0) { $genericArgs += "-gACC_WIDTH=$AccWidth" }
        if ($MemoryBurstLen -gt 0) { $genericArgs += "-gMEMORY_BURST_LEN=$MemoryBurstLen" }
        if ($MacPipelineStages -ge 0) { $genericArgs += "-gMAC_PIPELINE_STAGES=$MacPipelineStages" }
        if ($MemoryBanksA -gt 0) { $genericArgs += "-gMEMORY_BANKS_A=$MemoryBanksA" }
        if ($MemoryBanksB -gt 0) { $genericArgs += "-gMEMORY_BANKS_B=$MemoryBanksB" }
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

    $transcript = Invoke-CapturedStep -Command $vsimCommand -MaxAttempts $VsimRetryCount -RetryDelaySeconds $VsimRetrySeconds

    if ($transcript -notlike "*$PassMarker*") {
        throw "A simulacao terminou, mas nao encontrou o marcador: $PassMarker"
    }

    Write-Host ""
    Write-Host "PASS: $Entity executado com sucesso."
}

$tests = @(
    "tb_matrix_mult_tiled_core",
    "tb_matrix_mult_tiled_core_perf",
    "tb_tile_compute_engine",
    "tb_perf_counters",
    "tb_command_interface",
    "tb_uart_byte_fifo",
    "tb_sigma_hex_display",
    "tb_matrix_accelerator_full_top",
    "tb_matrix_accelerator_full_top_uart_protocol"
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
