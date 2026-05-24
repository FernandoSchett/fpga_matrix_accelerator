param(
    [string]$ConfigPath = "scripts/experiment_config.json",
    [string]$ResultsDir = "results",
    [int]$N = 0,
    [int]$DataWidth = 0,
    [int]$AccWidth = 0,
    [int]$TileSize = 0,
    [int]$NumMacs = 0,
    [int]$MemoryBurstLen = 0,
    [int]$SimulationN = 0,
    [int]$MaxSimulationCycles = 5000000,
    [switch]$RunSimulation,
    [switch]$RunHostDryRun,
    [switch]$SkipGenerateMatrices,
    [switch]$SkipQuartus
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir
$ProjectName = "fpga_matrix_accelerator"

Set-Location $ProjectDir

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

function Get-Clog2 {
    param([int]$Value)

    $result = 0
    $limit = 1
    while ($limit -lt $Value) {
        $limit *= 2
        $result += 1
    }
    return $result
}

function Get-NextPowerOfTwo {
    param([int]$Value)

    $result = 1
    while ($result -lt $Value) {
        $result *= 2
    }
    return $result
}

function Convert-ToQsfPath {
    param([string]$Path)
    return (Resolve-Path -LiteralPath $Path).Path.Replace("\", "/")
}

function Invoke-CapturedCommand {
    param(
        [string[]]$Command,
        [string]$LogPath,
        [string]$WorkingDirectory = $ProjectDir,
        [switch]$AllowFailure
    )

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null
    Write-Host ""
    Write-Host ("$ " + ($Command -join " "))

    $previousLocation = Get-Location
    try {
        Set-Location $WorkingDirectory
        $output = & $Command[0] $Command[1..($Command.Count - 1)] 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        Set-Location $previousLocation
    }

    $output | Set-Content -LiteralPath $LogPath -Encoding UTF8
    $output | ForEach-Object { Write-Host $_ }

    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "Comando falhou com exit code ${exitCode}: $($Command -join ' ')"
    }

    return @{
        ExitCode = $exitCode
        Text     = ($output -join [Environment]::NewLine)
    }
}

function Get-JsonProperty {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Default
    )

    if ($null -eq $Object) {
        return $Default
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        return $Default
    }

    return $property.Value
}

function Get-SourceList {
    param([string]$WrapperPath)

    $relativeSources = @(
        "rtl/common/matrix_tiled_pkg.vhd",
        "rtl/common/matrix_accel_config_pkg.vhd",
        "rtl/common/perf_counters.vhd",
        "rtl/common/accelerator_status_leds.vhd",
        "rtl/compute/mac_unit.vhd",
        "rtl/compute/mac_array.vhd",
        "rtl/compute/accumulator_reduce.vhd",
        "rtl/compute/matrix_tiled_compute_core.vhd",
        "rtl/memory/matrix_single_port_ram.vhd",
        "rtl/memory/tile_buffer_m10k.vhd",
        "rtl/memory/sdram_model.vhd",
        "rtl/memory/sdram_sim_wrapper.vhd",
        "rtl/memory/sdram_ip_wrapper.vhd",
        "rtl/memory/sdram_bus_if.vhd",
        "rtl/memory/matrix_memory_map.vhd",
        "rtl/control/tile_loader.vhd",
        "rtl/control/tile_store.vhd",
        "rtl/control/tile_scheduler.vhd",
        "rtl/control/accelerator_controller.vhd",
        "rtl/control/command_interface.vhd",
        "rtl/uart/uart_rx.vhd",
        "rtl/uart/uart_tx.vhd",
        "rtl/uart/uart_protocol.vhd",
        "rtl/top/matrix_accelerator_sdram_core_top.vhd",
        "rtl/top/matrix_accelerator_full_top.vhd"
    )

    $sources = @()
    foreach ($relativeSource in $relativeSources) {
        $path = Join-Path $ProjectDir $relativeSource
        if (Test-Path -LiteralPath $path) {
            $sources += $path
        }
    }

    $sources += $WrapperPath
    return $sources
}

function New-CoreWrapper {
    param(
        [string]$Path,
        [string]$EntityName,
        [int]$N,
        [int]$TileSize,
        [int]$NumMacs,
        [int]$DataWidth,
        [int]$AccWidth,
        [int]$SdramAddrWidth,
        [int]$SdramDepth
    )

    $content = @"
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.matrix_accel_config_pkg.all;

entity $EntityName is
    port (
        clk : in std_logic;
        rst : in std_logic;

        host_wr_en     : in std_logic;
        host_matrix_sel : in std_logic_vector(1 downto 0);
        host_addr      : in unsigned($($SdramAddrWidth - 1) downto 0);
        host_data_in   : in std_logic_vector(31 downto 0);

        host_rd_en     : in std_logic;
        host_rd_addr   : in unsigned($($SdramAddrWidth - 1) downto 0);
        host_data_out  : out std_logic_vector(31 downto 0);

        start : in std_logic;
        busy  : out std_logic;
        done  : out std_logic;

        status_word : out std_logic_vector(31 downto 0)
    );
end entity $EntityName;

architecture rtl of $EntityName is
    signal perf_total_cycles        : unsigned(63 downto 0);
    signal perf_load_cycles         : unsigned(63 downto 0);
    signal perf_compute_cycles      : unsigned(63 downto 0);
    signal perf_store_cycles        : unsigned(63 downto 0);
    signal perf_num_tiles_processed : unsigned(63 downto 0);
    signal perf_num_mac_ops_issued  : unsigned(63 downto 0);
    signal load_active              : std_logic;
    signal compute_active           : std_logic;
    signal store_active             : std_logic;
    signal tile_done                : std_logic;
begin
    status_word <= std_logic_vector(perf_total_cycles(31 downto 0) xor
                                    perf_load_cycles(31 downto 0) xor
                                    perf_compute_cycles(31 downto 0) xor
                                    perf_store_cycles(31 downto 0) xor
                                    perf_num_tiles_processed(31 downto 0) xor
                                    perf_num_mac_ops_issued(31 downto 0));

    u_top : entity work.matrix_accelerator_sdram_core_top
        generic map (
            N                => $N,
            TILE_SIZE        => $TileSize,
            NUM_MACS         => $NumMacs,
            DATA_WIDTH       => $DataWidth,
            ACC_WIDTH        => $AccWidth,
            SDRAM_DATA_WIDTH => 32,
            SDRAM_ADDR_WIDTH => $SdramAddrWidth,
            SDRAM_DEPTH      => $SdramDepth,
            READ_LATENCY     => 3,
            WRITE_LATENCY    => 2
        )
        port map (
            clk => clk,
            rst => rst,
            host_wr_en     => host_wr_en,
            host_matrix_sel => host_matrix_sel,
            host_addr      => host_addr,
            host_data_in   => host_data_in,
            host_rd_en     => host_rd_en,
            host_rd_addr   => host_rd_addr,
            host_data_out  => host_data_out,
            start => start,
            busy  => busy,
            done  => done,
            perf_total_cycles        => perf_total_cycles,
            perf_load_cycles         => perf_load_cycles,
            perf_compute_cycles      => perf_compute_cycles,
            perf_store_cycles        => perf_store_cycles,
            perf_num_tiles_processed => perf_num_tiles_processed,
            perf_num_mac_ops_issued  => perf_num_mac_ops_issued,
            load_active              => load_active,
            compute_active           => compute_active,
            store_active             => store_active,
            tile_done                => tile_done
        );
end architecture rtl;
"@

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    Set-Content -LiteralPath $Path -Value $content -Encoding ASCII
}

function New-ExperimentTb {
    param(
        [string]$Path,
        [string]$EntityName,
        [int]$N,
        [int]$TileSize,
        [int]$NumMacs,
        [int]$DataWidth,
        [int]$AccWidth,
        [int]$SdramAddrWidth,
        [int]$SdramDepth,
        [int]$MaxCycles
    )

    $content = @"
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library work;
use work.matrix_accel_config_pkg.all;

entity $EntityName is
end entity $EntityName;

architecture sim of $EntityName is
    constant CLK_PERIOD       : time := 10 ns;
    constant N_VALUE          : positive := $N;
    constant TILE_SIZE_VALUE  : positive := $TileSize;
    constant NUM_MACS_VALUE   : positive := $NumMacs;
    constant DATA_WIDTH_VALUE : positive := $DataWidth;
    constant ACC_WIDTH_VALUE  : positive := $AccWidth;
    constant SDRAM_ADDR_WIDTH : positive := $SdramAddrWidth;
    constant SDRAM_DEPTH      : positive := $SdramDepth;

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';
    signal host_wr_en      : std_logic := '0';
    signal host_matrix_sel : std_logic_vector(1 downto 0) := MATRIX_ID_A;
    signal host_addr       : unsigned(SDRAM_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal host_data_in    : std_logic_vector(31 downto 0) := (others => '0');
    signal host_rd_en      : std_logic := '0';
    signal host_rd_addr    : unsigned(SDRAM_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal host_data_out   : std_logic_vector(31 downto 0);
    signal start           : std_logic := '0';
    signal busy            : std_logic;
    signal done            : std_logic;
    signal perf_total_cycles        : unsigned(63 downto 0);
    signal perf_load_cycles         : unsigned(63 downto 0);
    signal perf_compute_cycles      : unsigned(63 downto 0);
    signal perf_store_cycles        : unsigned(63 downto 0);
    signal perf_num_tiles_processed : unsigned(63 downto 0);
    signal perf_num_mac_ops_issued  : unsigned(63 downto 0);

    function a_value(constant row_idx : natural; constant col_idx : natural) return integer is
    begin
        return (row_idx + (2 * col_idx) + 1) mod 8;
    end function;

    function b_value(constant row_idx : natural; constant col_idx : natural) return integer is
    begin
        return ((3 * row_idx) + col_idx + 2) mod 8;
    end function;

    function c_expected(constant row_idx : natural; constant col_idx : natural) return integer is
        variable acc : integer := 0;
    begin
        for k_idx in 0 to N_VALUE-1 loop
            acc := acc + a_value(row_idx, k_idx) * b_value(k_idx, col_idx);
        end loop;
        return acc;
    end function;

    procedure host_write(
        signal wr_en      : out std_logic;
        signal matrix_sel : out std_logic_vector(1 downto 0);
        signal addr_sig   : out unsigned;
        signal data_sig   : out std_logic_vector;
        constant sel      : std_logic_vector(1 downto 0);
        constant addr_nat : natural;
        constant value    : integer
    ) is
    begin
        matrix_sel <= sel;
        addr_sig   <= to_unsigned(addr_nat, addr_sig'length);
        data_sig   <= std_logic_vector(to_signed(value, data_sig'length));
        wr_en      <= '1';
        wait until rising_edge(clk);
        wr_en <= '0';
        for cycle_idx in 0 to 4 loop
            wait until rising_edge(clk);
        end loop;
    end procedure;

    procedure host_read_c(
        signal rd_en      : out std_logic;
        signal rd_addr    : out unsigned;
        signal data_sig   : in std_logic_vector;
        constant addr_nat : natural;
        variable value    : out integer
    ) is
    begin
        rd_addr <= to_unsigned(addr_nat, rd_addr'length);
        rd_en   <= '1';
        wait until rising_edge(clk);
        rd_en <= '0';
        for cycle_idx in 0 to 8 loop
            wait until rising_edge(clk);
        end loop;
        value := to_integer(signed(data_sig));
    end procedure;
begin
    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.matrix_accelerator_sdram_core_top
        generic map (
            N                => N_VALUE,
            TILE_SIZE        => TILE_SIZE_VALUE,
            NUM_MACS         => NUM_MACS_VALUE,
            DATA_WIDTH       => DATA_WIDTH_VALUE,
            ACC_WIDTH        => ACC_WIDTH_VALUE,
            SDRAM_DATA_WIDTH => 32,
            SDRAM_ADDR_WIDTH => SDRAM_ADDR_WIDTH,
            SDRAM_DEPTH      => SDRAM_DEPTH,
            READ_LATENCY     => 1,
            WRITE_LATENCY    => 1
        )
        port map (
            clk => clk,
            rst => rst,
            host_wr_en => host_wr_en,
            host_matrix_sel => host_matrix_sel,
            host_addr => host_addr,
            host_data_in => host_data_in,
            host_rd_en => host_rd_en,
            host_rd_addr => host_rd_addr,
            host_data_out => host_data_out,
            start => start,
            busy => busy,
            done => done,
            perf_total_cycles => perf_total_cycles,
            perf_load_cycles => perf_load_cycles,
            perf_compute_cycles => perf_compute_cycles,
            perf_store_cycles => perf_store_cycles,
            perf_num_tiles_processed => perf_num_tiles_processed,
            perf_num_mac_ops_issued => perf_num_mac_ops_issued,
            load_active => open,
            compute_active => open,
            store_active => open,
            tile_done => open
        );

    stim_proc : process
        variable addr        : natural;
        variable got_value   : integer;
        variable exec_cycles : natural;
    begin
        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait until rising_edge(clk);

        for row_idx in 0 to N_VALUE-1 loop
            for col_idx in 0 to N_VALUE-1 loop
                addr := row_idx * N_VALUE + col_idx;
                host_write(host_wr_en, host_matrix_sel, host_addr, host_data_in, MATRIX_ID_A, addr, a_value(row_idx, col_idx));
                host_write(host_wr_en, host_matrix_sel, host_addr, host_data_in, MATRIX_ID_B, addr, b_value(row_idx, col_idx));
            end loop;
        end loop;

        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        exec_cycles := 0;
        for cycle_idx in 0 to $MaxCycles loop
            wait until rising_edge(clk);
            exec_cycles := exec_cycles + 1;
            exit when done = '1';
        end loop;

        assert done = '1'
            report "matrix_accelerator_sdram_core_top nao finalizou."
            severity failure;

        report "Ciclos de execucao: " & integer'image(exec_cycles) severity note;
        report "load_cycles: " & integer'image(to_integer(perf_load_cycles)) severity note;
        report "compute_cycles: " & integer'image(to_integer(perf_compute_cycles)) severity note;
        report "store_cycles: " & integer'image(to_integer(perf_store_cycles)) severity note;

        for row_idx in 0 to N_VALUE-1 loop
            for col_idx in 0 to N_VALUE-1 loop
                addr := row_idx * N_VALUE + col_idx;
                host_read_c(host_rd_en, host_rd_addr, host_data_out, addr, got_value);
                assert got_value = c_expected(row_idx, col_idx)
                    report "Resultado incorreto no core top SDRAM gerado."
                    severity failure;
            end loop;
        end loop;

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;
end architecture sim;
"@

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    Set-Content -LiteralPath $Path -Value $content -Encoding ASCII
}

function New-ExperimentQsf {
    param(
        [string]$Path,
        [string]$TopEntity,
        [string]$OutputDirectory,
        [string[]]$Sources
    )

    $outputQsfPath = $OutputDirectory.Replace("\", "/")
    $lines = @(
        'set_global_assignment -name FAMILY "Cyclone V"',
        'set_global_assignment -name DEVICE 5CEBA4F23C7',
        "set_global_assignment -name TOP_LEVEL_ENTITY $TopEntity",
        "set_global_assignment -name PROJECT_OUTPUT_DIRECTORY $outputQsfPath",
        'set_global_assignment -name NUM_PARALLEL_PROCESSORS 8',
        'set_global_assignment -name EDA_SIMULATION_TOOL "Questa Altera FPGA (VHDL)"',
        'set_global_assignment -name POWER_BOARD_THERMAL_MODEL "NONE (CONSERVATIVE)"'
    )

    foreach ($source in $Sources) {
        $lines += ('set_global_assignment -name VHDL_FILE "' + (Convert-ToQsfPath $source) + '"')
    }

    Set-Content -LiteralPath $Path -Value ($lines -join [Environment]::NewLine) -Encoding ASCII
}

function New-ExperimentQpf {
    param(
        [string]$Path,
        [string]$Revision
    )

    $content = @"
QUARTUS_VERSION = "25.1"
DATE = "generated by scripts/run_sdram_arch_experiments.ps1"

PROJECT_REVISION = "$Revision"
"@

    Set-Content -LiteralPath $Path -Value $content -Encoding ASCII
}

function Invoke-GeneratedSimulation {
    param(
        [string]$RunDir,
        [string[]]$Sources,
        [string]$TbPath,
        [string]$TbEntity,
        [string]$LogPath
    )

    $vlib = Find-Tool -Name "vlib"
    $vmap = Find-Tool -Name "vmap"
    $vcom = Find-Tool -Name "vcom"
    $vsim = Find-Tool -Name "vsim"
    $workDir = Join-Path $RunDir "sim_work"
    New-Item -ItemType Directory -Force -Path $workDir | Out-Null

    Invoke-CapturedCommand -Command @($vlib, "work") -LogPath (Join-Path $RunDir "simulation_logs\vlib.log") -WorkingDirectory $workDir | Out-Null
    Invoke-CapturedCommand -Command @($vmap, "work", "work") -LogPath (Join-Path $RunDir "simulation_logs\vmap.log") -WorkingDirectory $workDir | Out-Null

    $sourceIndex = 0
    foreach ($source in $Sources) {
        $sourceIndex += 1
        $sourceName = [System.IO.Path]::GetFileNameWithoutExtension($source)
        $compileLog = Join-Path $RunDir ("simulation_logs\vcom_{0:00}_{1}.log" -f $sourceIndex, $sourceName)
        $compileResult = Invoke-CapturedCommand -Command @($vcom, "-2008", "-work", "work", $source) -LogPath $compileLog -WorkingDirectory $workDir -AllowFailure
        if ($compileResult.ExitCode -ne 0) {
            throw "Falha ao compilar fonte de simulacao: $source"
        }
    }
    Invoke-CapturedCommand -Command @($vcom, "-2008", "-work", "work", $TbPath) -LogPath (Join-Path $RunDir "simulation_logs\vcom_tb.log") -WorkingDirectory $workDir | Out-Null

    $result = Invoke-CapturedCommand -Command @($vsim, "-c", "-quiet", "work.$TbEntity", "-do", "run -all; quit -f") -LogPath $LogPath -WorkingDirectory $workDir -AllowFailure
    if ($result.ExitCode -ne 0 -or $result.Text -notlike "*SIM_RESULT: PASS*") {
        throw "Simulacao falhou ou nao encontrou SIM_RESULT: PASS"
    }
}

$configFullPath = Resolve-Path -LiteralPath $ConfigPath
$configRoot = Get-Content -LiteralPath $configFullPath -Raw | ConvertFrom-Json
$defaults = Get-JsonProperty -Object $configRoot -Name "defaults" -Default $null
$sweep = Get-JsonProperty -Object $configRoot -Name "sweep" -Default $configRoot

$defaultN = [int](Get-JsonProperty -Object $defaults -Name "N" -Default 128)
$defaultDataWidth = [int](Get-JsonProperty -Object $defaults -Name "DATA_WIDTH" -Default 8)
$defaultAccWidth = [int](Get-JsonProperty -Object $defaults -Name "ACC_WIDTH" -Default 32)
$memType = [string](Get-JsonProperty -Object $defaults -Name "MEM_TYPE" -Default "external_sdram_with_internal_tile_buffers")
$dataflow = [string](Get-JsonProperty -Object $defaults -Name "DATAFLOW" -Default "output_stationary")
$bufferingMode = [string](Get-JsonProperty -Object $defaults -Name "BUFFERING_MODE" -Default "single")
$macPipelineStages = Get-JsonProperty -Object $defaults -Name "MAC_PIPELINE_STAGES" -Default $null
$memoryBanksA = Get-JsonProperty -Object $defaults -Name "MEMORY_BANKS_A" -Default 1
$memoryBanksB = Get-JsonProperty -Object $defaults -Name "MEMORY_BANKS_B" -Default 1
$topEntityBase = [string](Get-JsonProperty -Object $defaults -Name "TOP_ENTITY" -Default "matrix_accelerator_sdram_core_top")

if ($N -le 0) { $N = $defaultN }
if ($DataWidth -le 0) { $DataWidth = $defaultDataWidth }
if ($AccWidth -le 0) { $AccWidth = $defaultAccWidth }
if ($SimulationN -lt 0) { throw "-SimulationN nao pode ser negativo" }

$baseResultsDir = Join-Path $ProjectDir $ResultsDir
$runsDir = Join-Path $baseResultsDir "runs"
New-Item -ItemType Directory -Force -Path $runsDir | Out-Null

$configs = @()
foreach ($item in $sweep) {
    $itemTile = [int](Get-JsonProperty -Object $item -Name "tile_size" -Default 0)
    $itemMacs = [int](Get-JsonProperty -Object $item -Name "num_macs" -Default 0)
    if ($TileSize -gt 0 -and $itemTile -ne $TileSize) { continue }
    if ($NumMacs -gt 0 -and $itemMacs -ne $NumMacs) { continue }
    if ($itemTile -le 0 -or $itemMacs -le 0) { continue }
    $configs += $item
}

if ($configs.Count -eq 0) {
    throw "Nenhuma configuracao encontrada. Confira -TileSize/-NumMacs e $ConfigPath."
}

$quartusSh = $null
if (-not $SkipQuartus) {
    $quartusSh = Find-QuartusTool -Name "quartus_sh"
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

foreach ($config in $configs) {
    $tile = [int](Get-JsonProperty -Object $config -Name "tile_size" -Default 0)
    $macs = [int](Get-JsonProperty -Object $config -Name "num_macs" -Default 0)
    $burst = if ($MemoryBurstLen -gt 0) { $MemoryBurstLen } else { Get-JsonProperty -Object $config -Name "memory_burst_len" -Default $null }

    if (($N % $tile) -ne 0) {
        throw "N=$N precisa ser divisivel por TILE_SIZE=$tile."
    }

    $runId = "sdram_n${N}_t${tile}_m${macs}_$timestamp"
    if ($null -ne $burst -and "$burst" -ne "") {
        $runId = "${runId}_b${burst}"
    }
    $baseRunId = $runId
    $runSuffix = 1
    while (Test-Path -LiteralPath (Join-Path $runsDir $runId)) {
        $runId = "{0}_{1:00}" -f $baseRunId, $runSuffix
        $runSuffix += 1
    }

    $runDir = Join-Path $runsDir $runId
    $generatedDir = Join-Path $runDir "generated"
    $quartusLogsDir = Join-Path $runDir "quartus_logs"
    $quartusReportsDir = Join-Path $runDir "quartus_reports"
    $simulationLogsDir = Join-Path $runDir "simulation_logs"
    $hostLogsDir = Join-Path $runDir "host_logs"
    New-Item -ItemType Directory -Force -Path $generatedDir, $quartusLogsDir, $quartusReportsDir, $simulationLogsDir, $hostLogsDir | Out-Null

    $requiredDepth = 3 * $N * $N + 16
    $sdramDepth = Get-NextPowerOfTwo -Value $requiredDepth
    if ($sdramDepth -lt 262144) { $sdramDepth = 262144 }
    $sdramAddrWidth = Get-Clog2 -Value $sdramDepth

    $wrapperEntity = "matrix_accel_sdram_n${N}_t${tile}_m${macs}"
    $wrapperPath = Join-Path $generatedDir "$wrapperEntity.vhd"
    New-CoreWrapper -Path $wrapperPath -EntityName $wrapperEntity -N $N -TileSize $tile -NumMacs $macs -DataWidth $DataWidth -AccWidth $AccWidth -SdramAddrWidth $sdramAddrWidth -SdramDepth $sdramDepth

    $runConfig = [ordered]@{
        run_id = $runId
        top_entity = $wrapperEntity
        base_top_entity = $topEntityBase
        N = $N
        tile_size = $tile
        num_macs = $macs
        data_width = $DataWidth
        acc_width = $AccWidth
        mem_type = $memType
        dataflow = $dataflow
        buffering_mode = $bufferingMode
        memory_burst_len = $burst
        mac_pipeline_stages = $macPipelineStages
        memory_banks_a = $memoryBanksA
        memory_banks_b = $memoryBanksB
        sdram_addr_width = $sdramAddrWidth
        sdram_depth = $sdramDepth
        generated_wrapper = $wrapperPath
        simulation_n = if ($RunSimulation) { if ($SimulationN -gt 0) { $SimulationN } else { $N } } else { $null }
    }
    $runConfig | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runDir "config.json") -Encoding UTF8

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "Run $runId"
    Write-Host "N=$N TILE_SIZE=$tile NUM_MACS=$macs"
    Write-Host "============================================================"

    if (-not $SkipGenerateMatrices) {
        $matrixOutDir = Join-Path $hostLogsDir "matrix"
        Invoke-CapturedCommand -Command @(
            "python", "py_matrix_host\main.py",
            "--n", "$N",
            "--data-width", "$DataWidth",
            "--acc-width", "$AccWidth",
            "--seed", "123",
            "--num-tests", "1",
            "--output-dir", $matrixOutDir
        ) -LogPath (Join-Path $hostLogsDir "golden_model.log") | Out-Null

        if ($RunHostDryRun) {
            Invoke-CapturedCommand -Command @(
                "python", "py_matrix_host\host_uart.py",
                "--dry-run",
                "--input", (Join-Path $matrixOutDir "matrix_inputs.txt"),
                "--expected", (Join-Path $matrixOutDir "matrix_expected.txt"),
                "--log-dir", $hostLogsDir,
                "--run-id", "host_$runId",
                "--tile-size", "$tile",
                "--num-macs", "$macs"
            ) -LogPath (Join-Path $hostLogsDir "host_dry_run.log") | Out-Null
        }
    }

    $sources = Get-SourceList -WrapperPath $wrapperPath

    if ($RunSimulation) {
        $simN = if ($SimulationN -gt 0) { $SimulationN } else { $N }
        if (($simN % $tile) -ne 0) {
            throw "SimulationN=$simN precisa ser divisivel por TILE_SIZE=$tile."
        }
        $simDepth = Get-NextPowerOfTwo -Value (3 * $simN * $simN + 16)
        $simAddrWidth = Get-Clog2 -Value $simDepth
        $tbEntity = "tb_${wrapperEntity}"
        $tbPath = Join-Path $generatedDir "$tbEntity.vhd"
        New-ExperimentTb -Path $tbPath -EntityName $tbEntity -N $simN -TileSize $tile -NumMacs $macs -DataWidth $DataWidth -AccWidth $AccWidth -SdramAddrWidth $simAddrWidth -SdramDepth $simDepth -MaxCycles $MaxSimulationCycles
        Invoke-GeneratedSimulation -RunDir $runDir -Sources ($sources | Where-Object { $_ -ne $wrapperPath }) -TbPath $tbPath -TbEntity $tbEntity -LogPath (Join-Path $simulationLogsDir "simulation.log")
    }

    $projectRevision = "${ProjectName}_$runId"
    $qpfPath = Join-Path $runDir "$projectRevision.qpf"
    $qsfPath = Join-Path $runDir "$projectRevision.qsf"
    New-ExperimentQpf -Path $qpfPath -Revision $projectRevision
    New-ExperimentQsf -Path $qsfPath -TopEntity $wrapperEntity -OutputDirectory (Join-Path $quartusReportsDir "output_files") -Sources $sources

    if (-not $SkipQuartus) {
        Invoke-CapturedCommand -Command @($quartusSh, "--flow", "compile", $projectRevision) -LogPath (Join-Path $quartusLogsDir "quartus_flow.log") -WorkingDirectory $runDir -AllowFailure | Out-Null
    }

    Invoke-CapturedCommand -Command @(
        "python", "scripts\parse_quartus_reports.py",
        "--reports-dir", $quartusReportsDir,
        "--output", (Join-Path $runDir "parsed_quartus.json")
    ) -LogPath (Join-Path $quartusLogsDir "parse_quartus_reports.log") | Out-Null
}

Invoke-CapturedCommand -Command @(
    "python", "scripts\collect_results.py",
    "--runs-dir", $runsDir,
    "--output-csv", (Join-Path $baseResultsDir "experiment_results.csv")
) -LogPath (Join-Path $baseResultsDir "collect_results.log") | Out-Null

Write-Host ""
Write-Host "Experimentos finalizados."
Write-Host "CSV final: $(Join-Path $baseResultsDir 'experiment_results.csv')"
