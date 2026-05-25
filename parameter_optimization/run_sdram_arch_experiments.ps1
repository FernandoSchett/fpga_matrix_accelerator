param(
    [string]$ConfigPath = "",
    [switch]$SkipSimulation,
    [switch]$SkipQuartus,
    [switch]$SkipAnalysis,
    [int]$RunLimit = 0,
    [int]$VsimRetryCount = 10,
    [int]$VsimRetrySeconds = 30
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$optimizationDir = Join-Path $projectRoot "parameter_optimization"
$projectName = "fpga_matrix_accelerator"

function Resolve-ProjectPath {
    param([string]$PathValue)

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        $PathValue = Join-Path $optimizationDir "configs\01_compute_sweep.json"
    }

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return (Resolve-Path -LiteralPath $PathValue).Path
    }

    $currentCandidate = Join-Path (Get-Location) $PathValue
    if (Test-Path -LiteralPath $currentCandidate) {
        return (Resolve-Path -LiteralPath $currentCandidate).Path
    }

    $projectCandidate = Join-Path $projectRoot $PathValue
    if (Test-Path -LiteralPath $projectCandidate) {
        return (Resolve-Path -LiteralPath $projectCandidate).Path
    }

    throw "Arquivo nao encontrado: $PathValue"
}

function Find-Tool {
    param(
        [string]$Name,
        [string]$FallbackPath = ""
    )

    $commandInfo = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -ne $commandInfo) {
        return $commandInfo.Source
    }

    if ($FallbackPath -ne "" -and (Test-Path -LiteralPath $FallbackPath)) {
        return $FallbackPath
    }

    throw "Ferramenta nao encontrada: $Name"
}

function ConvertTo-QsfPath {
    param([string]$PathValue)
    return (Resolve-Path -LiteralPath $PathValue).Path.Replace("\", "/")
}

function Invoke-CapturedCommand {
    param(
        [string[]]$Command,
        [string]$LogPath,
        [string]$WorkingDirectory
    )

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null
    Write-Host ("$ " + ($Command -join " "))

    $previousLocation = Get-Location
    try {
        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
            Set-Location $WorkingDirectory
        }
        $executable = $Command[0]
        $commandArguments = @()
        if ($Command.Count -gt 1) {
            $commandArguments = $Command[1..($Command.Count - 1)]
        }
        $previousErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"
            $output = & $executable @commandArguments 2>&1 | ForEach-Object { "$_" }
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
    }
    finally {
        Set-Location $previousLocation
    }

    $output | Set-Content -LiteralPath $LogPath -Encoding UTF8
    $output | ForEach-Object { Write-Host $_ }

    return @{
        ExitCode = $exitCode
        Text = ($output -join [Environment]::NewLine)
    }
}

function Get-ConfigValue {
    param(
        [hashtable]$Config,
        [string[]]$Names,
        $DefaultValue = $null
    )

    foreach ($name in $Names) {
        if ($Config.ContainsKey($name) -and $null -ne $Config[$name]) {
            return $Config[$name]
        }
    }
    return $DefaultValue
}

function ConvertTo-ConfigHashtable {
    param($JsonObject)

    $result = @{}
    if ($null -eq $JsonObject) {
        return $result
    }
    foreach ($property in $JsonObject.PSObject.Properties) {
        $result[$property.Name] = $property.Value
    }
    return $result
}

function New-RunConfig {
    param(
        [hashtable]$Defaults,
        $SweepItem
    )

    $runConfig = @{}
    foreach ($key in $Defaults.Keys) {
        $runConfig[$key] = $Defaults[$key]
    }
    foreach ($property in $SweepItem.PSObject.Properties) {
        $runConfig[$property.Name] = $property.Value
    }
    return $runConfig
}

function Get-RunName {
    param(
        [int]$RunIndex,
        [hashtable]$RunConfig
    )

    $nValue = Get-ConfigValue -Config $RunConfig -Names @("N") -DefaultValue 128
    $tileSize = Get-ConfigValue -Config $RunConfig -Names @("TILE_SIZE", "tile_size") -DefaultValue 4
    $numMacs = Get-ConfigValue -Config $RunConfig -Names @("NUM_MACS", "num_macs") -DefaultValue 4
    $dataWidth = Get-ConfigValue -Config $RunConfig -Names @("DATA_WIDTH", "data_width") -DefaultValue 8
    $accWidth = Get-ConfigValue -Config $RunConfig -Names @("ACC_WIDTH", "acc_width") -DefaultValue 32
    return ("run_{0:D3}_n{1}_t{2}_m{3}_d{4}_a{5}" -f $RunIndex, $nValue, $tileSize, $numMacs, $dataWidth, $accWidth).ToLower()
}

function Get-ParameterConnectivity {
    param([hashtable]$RunConfig)

    $connected = @("N", "TILE_SIZE", "tile_size", "NUM_MACS", "num_macs", "DATA_WIDTH", "data_width", "ACC_WIDTH", "acc_width")
    $metadata = @("MEM_TYPE", "mem_type", "DATAFLOW", "dataflow", "BUFFERING_MODE", "buffering_mode", "MEMORY_BURST_LEN", "memory_burst_len", "MAC_PIPELINE_STAGES", "mac_pipeline_stages", "MEMORY_BANKS_A", "memory_banks_a", "MEMORY_BANKS_B", "memory_banks_b", "TOP_ENTITY", "top_entity")

    $warnings = @()
    foreach ($key in $RunConfig.Keys) {
        if ($key -notin $connected -and $key -notin $metadata) {
            $warnings += "Parametro '$key' nao foi reconhecido pelo fluxo; sera mantido como metadado."
        }
    }

    return $warnings
}

function Get-MetadataOnlyKeys {
    param(
        [hashtable]$Defaults,
        [array]$Sweep
    )

    $metadata = @("MEM_TYPE", "mem_type", "DATAFLOW", "dataflow", "BUFFERING_MODE", "buffering_mode", "MEMORY_BURST_LEN", "memory_burst_len", "MAC_PIPELINE_STAGES", "mac_pipeline_stages", "MEMORY_BANKS_A", "memory_banks_a", "MEMORY_BANKS_B", "memory_banks_b")
    $present = New-Object System.Collections.Generic.HashSet[string]

    foreach ($key in $Defaults.Keys) {
        if ($key -in $metadata) {
            [void]$present.Add($key)
        }
    }

    foreach ($sweepItem in $Sweep) {
        foreach ($property in $sweepItem.PSObject.Properties) {
            if ($property.Name -in $metadata) {
                [void]$present.Add($property.Name)
            }
        }
    }

    return @($present)
}

function New-BoardWrapper {
    param(
        [string]$PathValue,
        [string]$EntityName,
        [hashtable]$RunConfig
    )

    $nValue = [int](Get-ConfigValue -Config $RunConfig -Names @("N") -DefaultValue 128)
    $tileSize = [int](Get-ConfigValue -Config $RunConfig -Names @("TILE_SIZE", "tile_size") -DefaultValue 4)
    $numMacs = [int](Get-ConfigValue -Config $RunConfig -Names @("NUM_MACS", "num_macs") -DefaultValue 4)
    $dataWidth = [int](Get-ConfigValue -Config $RunConfig -Names @("DATA_WIDTH", "data_width") -DefaultValue 8)
    $accWidth = [int](Get-ConfigValue -Config $RunConfig -Names @("ACC_WIDTH", "acc_width") -DefaultValue 32)

    $content = @"
library ieee;
use ieee.std_logic_1164.all;

entity $EntityName is
    port (
        clk : in std_logic;
        rst : in std_logic;
        uart_rx_i : in std_logic;
        uart_tx_o : out std_logic;
        start_button : in std_logic;
        LEDR : out std_logic_vector(9 downto 0);
        HEX0 : out std_logic_vector(6 downto 0);
        HEX1 : out std_logic_vector(6 downto 0);
        HEX2 : out std_logic_vector(6 downto 0);
        HEX3 : out std_logic_vector(6 downto 0);
        HEX4 : out std_logic_vector(6 downto 0);
        HEX5 : out std_logic_vector(6 downto 0)
    );
end entity $EntityName;

architecture rtl of $EntityName is
begin
    u_top : entity work.matrix_accelerator_full_top
        generic map (
            N => $nValue,
            TILE_SIZE => $tileSize,
            NUM_MACS => $numMacs,
            DATA_WIDTH => $dataWidth,
            ACC_WIDTH => $accWidth,
            ENABLE_SIGNALTAP => false
        )
        port map (
            clk => clk,
            rst => rst,
            uart_rx_i => uart_rx_i,
            uart_tx_o => uart_tx_o,
            start_button => start_button,
            LEDR => LEDR,
            HEX0 => HEX0,
            HEX1 => HEX1,
            HEX2 => HEX2,
            HEX3 => HEX3,
            HEX4 => HEX4,
            HEX5 => HEX5
        );
end architecture rtl;
"@
    Set-Content -LiteralPath $PathValue -Value $content -Encoding ASCII
}

function New-CoreWrapper {
    param(
        [string]$PathValue,
        [string]$EntityName,
        [hashtable]$RunConfig
    )

    $nValue = [int](Get-ConfigValue -Config $RunConfig -Names @("N") -DefaultValue 128)
    $tileSize = [int](Get-ConfigValue -Config $RunConfig -Names @("TILE_SIZE", "tile_size") -DefaultValue 4)
    $numMacs = [int](Get-ConfigValue -Config $RunConfig -Names @("NUM_MACS", "num_macs") -DefaultValue 4)
    $dataWidth = [int](Get-ConfigValue -Config $RunConfig -Names @("DATA_WIDTH", "data_width") -DefaultValue 8)
    $accWidth = [int](Get-ConfigValue -Config $RunConfig -Names @("ACC_WIDTH", "acc_width") -DefaultValue 32)

    $content = @"
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.matrix_tiled_pkg.all;

entity $EntityName is
    port (
        clk : in std_logic;
        rst : in std_logic;
        wr_en : in std_logic;
        matrix_sel : in std_logic;
        wr_addr : in unsigned(clog2($nValue*$nValue)-1 downto 0);
        data_in : in signed($dataWidth-1 downto 0);
        start : in std_logic;
        busy : out std_logic;
        done : out std_logic;
        result_addr : in unsigned(clog2($nValue*$nValue)-1 downto 0);
        data_out : out signed($accWidth-1 downto 0)
    );
end entity $EntityName;

architecture rtl of $EntityName is
begin
    u_core : entity work.matrix_mult_tiled_core
        generic map (
            N => $nValue,
            TILE_SIZE => $tileSize,
            NUM_MACS => $numMacs,
            DATA_WIDTH => $dataWidth,
            ACC_WIDTH => $accWidth
        )
        port map (
            clk => clk,
            rst => rst,
            wr_en => wr_en,
            matrix_sel => matrix_sel,
            wr_addr => wr_addr,
            data_in => data_in,
            start => start,
            busy => busy,
            done => done,
            result_addr => result_addr,
            data_out => data_out
        );
end architecture rtl;
"@
    Set-Content -LiteralPath $PathValue -Value $content -Encoding ASCII
}

function New-ExperimentQpf {
    param(
        [string]$PathValue,
        [string]$Revision
    )

    $content = @"
QUARTUS_VERSION = "25.1"
DATE = "generated by parameter_optimization/run_sdram_arch_experiments.ps1"

PROJECT_REVISION = "$Revision"
"@
    Set-Content -LiteralPath $PathValue -Value $content -Encoding ASCII
}

function New-ExperimentQsf {
    param(
        [string]$PathValue,
        [string]$TopEntity,
        [string]$OutputDirectory,
        [string]$WrapperPath,
        [bool]$UseBoardPins
    )

    $rtlFiles = @(
        "rtl/common/matrix_tiled_pkg.vhd",
        "rtl/common/matrix_accel_config_pkg.vhd",
        "rtl/common/perf_counters.vhd",
        "rtl/common/accelerator_status_leds.vhd",
        "rtl/common/sigma_hex_display.vhd",
        "rtl/compute/mac_unit.vhd",
        "rtl/compute/matrix_tiled_compute_core.vhd",
        "rtl/memory/matrix_single_port_ram.vhd",
        "rtl/control/command_interface.vhd",
        "rtl/uart/uart_rx.vhd",
        "rtl/uart/uart_tx.vhd",
        "rtl/uart/uart_byte_fifo.vhd",
        "rtl/debug/signaltap_debug_core.vhd",
        "rtl/compute/matrix_mult_tiled_core.vhd",
        "rtl/top/matrix_accelerator_full_top.vhd"
    )

    $lines = @(
        'set_global_assignment -name FAMILY "Cyclone V"',
        'set_global_assignment -name DEVICE 5CEBA4F23C7',
        "set_global_assignment -name TOP_LEVEL_ENTITY $TopEntity",
        "set_global_assignment -name PROJECT_OUTPUT_DIRECTORY `"$($OutputDirectory.Replace('\', '/'))`"",
        'set_global_assignment -name NUM_PARALLEL_PROCESSORS 8',
        'set_global_assignment -name VHDL_INPUT_VERSION VHDL_2008',
        "set_global_assignment -name SDC_FILE `"$((ConvertTo-QsfPath (Join-Path $projectRoot 'fpga_matrix_accelerator.sdc')))`""
    )

    foreach ($rtlFile in $rtlFiles) {
        $fullPath = Join-Path $projectRoot $rtlFile
        if (Test-Path -LiteralPath $fullPath) {
            $lines += "set_global_assignment -name VHDL_FILE `"$(ConvertTo-QsfPath $fullPath)`""
        }
    }
    $lines += "set_global_assignment -name VHDL_FILE `"$(ConvertTo-QsfPath $WrapperPath)`""

    if ($UseBoardPins) {
        $mainQsf = Join-Path $projectRoot "fpga_matrix_accelerator.qsf"
        $pinLines = Get-Content -LiteralPath $mainQsf | Where-Object {
            $_ -match "^(set_location_assignment|set_instance_assignment)" -or $_ -match "PARTITION_HIERARCHY"
        }
        $lines += ""
        $lines += $pinLines
    }

    Set-Content -LiteralPath $PathValue -Value $lines -Encoding ASCII
}

function Get-ExperimentName {
    param($ConfigData, [string]$ConfigPathAbs)

    if (-not [string]::IsNullOrWhiteSpace($ConfigData.experiment_name)) {
        return $ConfigData.experiment_name
    }
    return [System.IO.Path]::GetFileNameWithoutExtension($ConfigPathAbs)
}

$configPathAbs = Resolve-ProjectPath -PathValue $ConfigPath
$configData = Get-Content -LiteralPath $configPathAbs -Raw | ConvertFrom-Json
$experimentName = Get-ExperimentName -ConfigData $configData -ConfigPathAbs $configPathAbs
$defaults = ConvertTo-ConfigHashtable -JsonObject $configData.defaults
$sweep = @($configData.sweep)

if ($sweep.Count -eq 0) {
    throw "O JSON precisa conter uma lista 'sweep'."
}

$resultsDir = Join-Path $optimizationDir "results\$experimentName"
$runsDir = Join-Path $resultsDir "runs"
New-Item -ItemType Directory -Force -Path $runsDir | Out-Null

$pythonExe = Find-Tool -Name "python"
$quartusSh = $null
if (-not $SkipQuartus) {
    $quartusSh = Find-Tool -Name "quartus_sh" -FallbackPath "C:\altera_lite\25.1std\quartus\bin64\quartus_sh.exe"
}

Write-Host "Experimento: $experimentName"
Write-Host "Config: $configPathAbs"
Write-Host "Resultados: $resultsDir"

$metadataOnlyKeys = Get-MetadataOnlyKeys -Defaults $defaults -Sweep $sweep
if ($metadataOnlyKeys.Count -gt 0) {
    Write-Warning ("Parametros ainda tratados como metadado neste RTL: " + (($metadataOnlyKeys | Sort-Object) -join ", "))
}

$runIndex = 1
foreach ($sweepItem in $sweep) {
    if ($RunLimit -gt 0 -and $runIndex -gt $RunLimit) {
        break
    }

    $runConfig = New-RunConfig -Defaults $defaults -SweepItem $sweepItem
    $connectivityWarnings = Get-ParameterConnectivity -RunConfig $runConfig

    $baseTopEntity = [string](Get-ConfigValue -Config $runConfig -Names @("TOP_ENTITY", "top_entity") -DefaultValue "matrix_accelerator_full_top")
    $useBoardTop = $true
    if ($baseTopEntity -eq "matrix_mult_tiled_core") {
        $useBoardTop = $false
    } elseif ($baseTopEntity -ne "matrix_accelerator_full_top") {
        $connectivityWarnings += "TOP_ENTITY '$baseTopEntity' nao existe no RTL atual; usando matrix_accelerator_full_top."
        $baseTopEntity = "matrix_accelerator_full_top"
    }

    $runId = Get-RunName -RunIndex $runIndex -RunConfig $runConfig
    $runDir = Join-Path $runsDir $runId
    $generatedDir = Join-Path $runDir "generated"
    $quartusLogsDir = Join-Path $runDir "quartus_logs"
    $quartusOutputDir = Join-Path $runDir "quartus_output"
    $simulationLogsDir = Join-Path $runDir "simulation_logs"
    $hostLogsDir = Join-Path $runDir "host_logs"

    New-Item -ItemType Directory -Force -Path $runDir, $generatedDir, $quartusLogsDir, $quartusOutputDir, $simulationLogsDir, $hostLogsDir | Out-Null

    $topEntity = "$($baseTopEntity)_$runId"
    $wrapperPath = Join-Path $generatedDir "$topEntity.vhd"
    if ($useBoardTop) {
        New-BoardWrapper -PathValue $wrapperPath -EntityName $topEntity -RunConfig $runConfig
    } else {
        New-CoreWrapper -PathValue $wrapperPath -EntityName $topEntity -RunConfig $runConfig
    }

    $runConfig["RUN_ID"] = $runId
    $runConfig["TOP_ENTITY_GENERATED"] = $topEntity
    $runConfig["CONNECTED_RTL_PARAMETERS"] = @("N", "TILE_SIZE", "NUM_MACS", "DATA_WIDTH", "ACC_WIDTH")
    $runConfig["METADATA_ONLY_PARAMETERS"] = @("MEM_TYPE", "DATAFLOW", "BUFFERING_MODE", "MEMORY_BURST_LEN", "MAC_PIPELINE_STAGES", "MEMORY_BANKS_A", "MEMORY_BANKS_B")
    $runConfig["WARNINGS"] = $connectivityWarnings
    $runConfig | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runDir "config.json") -Encoding UTF8

    $revisionName = "${projectName}_$runId"
    New-ExperimentQpf -PathValue (Join-Path $runDir "$revisionName.qpf") -Revision $revisionName
    New-ExperimentQsf -PathValue (Join-Path $runDir "$revisionName.qsf") -TopEntity $topEntity -OutputDirectory $quartusOutputDir -WrapperPath $wrapperPath -UseBoardPins $useBoardTop

    foreach ($warning in $connectivityWarnings) {
        Write-Warning "${runId}: $warning"
    }

    if (-not $SkipSimulation) {
        $nValue = [string](Get-ConfigValue -Config $runConfig -Names @("N") -DefaultValue 128)
        $tileSize = [string](Get-ConfigValue -Config $runConfig -Names @("TILE_SIZE", "tile_size") -DefaultValue 4)
        $numMacs = [string](Get-ConfigValue -Config $runConfig -Names @("NUM_MACS", "num_macs") -DefaultValue 4)
        $dataWidth = [string](Get-ConfigValue -Config $runConfig -Names @("DATA_WIDTH", "data_width") -DefaultValue 8)
        $accWidth = [string](Get-ConfigValue -Config $runConfig -Names @("ACC_WIDTH", "acc_width") -DefaultValue 32)
        $simCommand = @(
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            (Join-Path $projectRoot "run_testbenchs.ps1"),
            "-Only",
            "tb_matrix_mult_tiled_core_perf",
            "-N",
            $nValue,
            "-TileSize",
            $tileSize,
            "-NumMacs",
            $numMacs,
            "-DataWidth",
            $dataWidth,
            "-AccWidth",
            $accWidth,
            "-VsimRetryCount",
            [string]$VsimRetryCount,
            "-VsimRetrySeconds",
            [string]$VsimRetrySeconds
        )
        Invoke-CapturedCommand -Command $simCommand -LogPath (Join-Path $simulationLogsDir "simulation.log") -WorkingDirectory $projectRoot | Out-Null
    }

    if (-not $SkipQuartus) {
        $quartusCommand = @($quartusSh, "--flow", "compile", $revisionName)
        Invoke-CapturedCommand -Command $quartusCommand -LogPath (Join-Path $quartusLogsDir "quartus_compile.log") -WorkingDirectory $runDir | Out-Null
    }

    $parseScript = Join-Path $optimizationDir "parse_quartus_reports.py"
    & $pythonExe $parseScript --reports-dir $quartusOutputDir --run-dir $runDir --output (Join-Path $runDir "parsed_quartus.json")
    if ($LASTEXITCODE -ne 0) {
        throw "parse_quartus_reports.py falhou para $runId"
    }

    $runIndex++
}

$collectScript = Join-Path $optimizationDir "collect_results.py"
$csvPath = Join-Path $resultsDir "experiment_results.csv"
& $pythonExe $collectScript --runs-dir $runsDir --output-csv $csvPath
if ($LASTEXITCODE -ne 0) {
    throw "collect_results.py falhou."
}

if (-not $SkipAnalysis) {
    $analysisScript = Join-Path $optimizationDir "analysis\run_analysis.py"
    & $pythonExe $analysisScript --experiment-dir $resultsDir
    if ($LASTEXITCODE -ne 0) {
        throw "run_analysis.py falhou."
    }
}

Write-Host ""
Write-Host "Experimento finalizado: $experimentName"
Write-Host "CSV: $csvPath"
