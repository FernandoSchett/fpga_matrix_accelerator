param(
    [int]$N = 128,
    [int]$DataWidth = 8,
    [int]$AccWidth = 32,
    [string]$OutputDir = "",
    [switch]$SkipSimulation,
    [switch]$SkipQuartus
)

$ErrorActionPreference = "Stop"

$OptimizationDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $OptimizationDir
$ProjectName = "fpga_matrix_accelerator"
$MemType = "internal_block_memory"

if ($OutputDir -eq "") {
    $OutputDir = Join-Path $OptimizationDir "results\tiled_arch"
} elseif (-not [System.IO.Path]::IsPathRooted($OutputDir)) {
    $OutputDir = Join-Path $OptimizationDir $OutputDir
}

Set-Location $ProjectDir

$configs = @(
    @{ TileSize = 2; NumMacs = 1 },
    @{ TileSize = 2; NumMacs = 2 },
    @{ TileSize = 2; NumMacs = 4 },
    @{ TileSize = 4; NumMacs = 1 },
    @{ TileSize = 4; NumMacs = 2 },
    @{ TileSize = 4; NumMacs = 4 },
    @{ TileSize = 8; NumMacs = 4 },
    @{ TileSize = 8; NumMacs = 8 }
)

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

function Get-Clog2 {
    param([int]$Value)

    $result = 0
    $limit = 1

    while ($limit -lt $Value) {
        $limit = $limit * 2
        $result = $result + 1
    }

    return $result
}

function Convert-ReportNumber {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    return [double]($Value -replace ",", "" -replace "%", "")
}

function Get-RegexValue {
    param(
        [string]$Text,
        [string[]]$Patterns,
        [int]$Group = 1
    )

    foreach ($pattern in $Patterns) {
        $match = [regex]::Match($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Multiline)
        if ($match.Success) {
            return $match.Groups[$Group].Value.Trim()
        }
    }

    return $null
}

function Get-ResourceTriple {
    param(
        [string]$Text,
        [string[]]$Patterns
    )

    foreach ($pattern in $Patterns) {
        $match = [regex]::Match($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Multiline)
        if ($match.Success) {
            return @{
                Used  = Convert-ReportNumber $match.Groups[1].Value
                Total = Convert-ReportNumber $match.Groups[2].Value
                Pct   = Convert-ReportNumber $match.Groups[3].Value
            }
        }
    }

    return @{ Used = $null; Total = $null; Pct = $null }
}

function Get-MaxMhz {
    param([string]$Text)

    $matches = [regex]::Matches($Text, "([0-9]+(?:\.[0-9]+)?)\s*MHz", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $max = $null

    foreach ($match in $matches) {
        $value = [double]$match.Groups[1].Value

        if ($null -eq $max -or $value -gt $max) {
            $max = $value
        }
    }

    return $max
}

function Invoke-CapturedCommand {
    param(
        [string[]]$Command,
        [string]$LogPath,
        [string]$WorkingDirectory = ""
    )

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null

    Write-Host ""
    Write-Host ("$ " + ($Command -join " "))

    $previousLocation = Get-Location

    try {
        if ($WorkingDirectory -ne "") {
            Set-Location $WorkingDirectory
        }

        $output = & $Command[0] $Command[1..($Command.Count - 1)] 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        Set-Location $previousLocation
    }

    $output | Set-Content -LiteralPath $LogPath -Encoding UTF8
    $output | ForEach-Object { Write-Host $_ }

    return @{
        ExitCode = $exitCode
        Text     = ($output -join [Environment]::NewLine)
    }
}

function Convert-ToQsfPath {
    param([string]$Path)

    return (Resolve-Path -LiteralPath $Path).Path.Replace("\", "/")
}

function New-ExperimentWrapper {
    param(
        [string]$Path,
        [string]$EntityName,
        [int]$N,
        [int]$TileSize,
        [int]$NumMacs,
        [int]$DataWidth,
        [int]$AccWidth
    )

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

        wr_en      : in std_logic;
        matrix_sel : in std_logic;
        wr_addr    : in unsigned(clog2($N*$N)-1 downto 0);
        data_in    : in signed($DataWidth-1 downto 0);

        start : in std_logic;
        busy  : out std_logic;
        done  : out std_logic;

        result_addr : in unsigned(clog2($N*$N)-1 downto 0);
        data_out    : out signed($AccWidth-1 downto 0)
    );
end entity $EntityName;

architecture rtl of $EntityName is
begin

    u_top : entity work.matrix_mult_tiled_top
        generic map (
            N          => $N,
            TILE_SIZE  => $TileSize,
            NUM_MACS   => $NumMacs,
            DATA_WIDTH => $DataWidth,
            ACC_WIDTH  => $AccWidth
        )
        port map (
            clk => clk,
            rst => rst,

            wr_en      => wr_en,
            matrix_sel => matrix_sel,
            wr_addr    => wr_addr,
            data_in    => data_in,

            start => start,
            busy  => busy,
            done  => done,

            result_addr => result_addr,
            data_out    => data_out
        );

end architecture rtl;
"@

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    Set-Content -LiteralPath $Path -Value $content -Encoding ASCII
}

function New-ExperimentQsf {
    param(
        [string]$Path,
        [string]$TopEntity,
        [string]$OutputDirectory,
        [string]$WrapperPath
    )

    $pkgPath = Convert-ToQsfPath (Join-Path $ProjectDir "rtl\matrix_tiled\pkg\matrix_tiled_pkg.vhd")
    $macPath = Convert-ToQsfPath (Join-Path $ProjectDir "rtl\matriz_4x4\blocks\mac_unit.vhd")
    $ramPath = Convert-ToQsfPath (Join-Path $ProjectDir "rtl\matrix_tiled\memory\matrix_single_port_ram.vhd")
    $corePath = Convert-ToQsfPath (Join-Path $ProjectDir "rtl\matrix_tiled\compute\matrix_tiled_compute_core.vhd")
    $topPath = Convert-ToQsfPath (Join-Path $ProjectDir "rtl\matrix_tiled\matrix_mult_tiled_top.vhd")
    $wrapperQsfPath = Convert-ToQsfPath $WrapperPath
    $outputQsfPath = $OutputDirectory.Replace("\", "/")

    $content = @"
set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CEBA4F23C7
set_global_assignment -name TOP_LEVEL_ENTITY $TopEntity
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY $outputQsfPath
set_global_assignment -name NUM_PARALLEL_PROCESSORS 8
set_global_assignment -name VHDL_FILE "$pkgPath"
set_global_assignment -name VHDL_FILE "$macPath"
set_global_assignment -name VHDL_FILE "$ramPath"
set_global_assignment -name VHDL_FILE "$corePath"
set_global_assignment -name VHDL_FILE "$topPath"
set_global_assignment -name VHDL_FILE "$wrapperQsfPath"
"@

    Set-Content -LiteralPath $Path -Value $content -Encoding ASCII
}

function New-ExperimentQpf {
    param(
        [string]$Path,
        [string]$ProjectRevision
    )

    $content = @"
QUARTUS_VERSION = "25.1"
DATE = "generated by parameter_optimization/run_tiled_arch_experiments.ps1"

PROJECT_REVISION = "$ProjectRevision"
"@

    Set-Content -LiteralPath $Path -Value $content -Encoding ASCII
}

function Read-QuartusReports {
    param([string]$RunDir)

    $files = Get-ChildItem -LiteralPath $RunDir -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @(".rpt", ".summary") }

    if ($files.Count -eq 0) {
        return ""
    }

    return (($files | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join [Environment]::NewLine)
}

$quartusSh = $null
if (-not $SkipQuartus) {
    $quartusSh = Find-Tool -Name "quartus_sh" -FallbackPath "C:\altera_lite\25.1std\quartus\bin64\quartus_sh.exe"
}

$rows = @()
$tiledTestScriptCandidates = @(
    Join-Path $ProjectDir "testes\scripts\run_tb_matrix_mult_tiled_top.ps1",
    Join-Path $ProjectDir "testes\run_tb_matrix_mult_tiled_top.ps1"
)
$tiledTestScript = $null
foreach ($candidate in $tiledTestScriptCandidates) {
    if (Test-Path -LiteralPath $candidate) {
        $tiledTestScript = $candidate
        break
    }
}

if (-not $SkipSimulation -and $null -eq $tiledTestScript) {
    throw "Script de simulacao tiled nao encontrado em testes\scripts\run_tb_matrix_mult_tiled_top.ps1 nem em testes\run_tb_matrix_mult_tiled_top.ps1"
}

$baseOutputDir = $OutputDir
New-Item -ItemType Directory -Force -Path $baseOutputDir | Out-Null

foreach ($config in $configs) {
    $tileSize = [int]$config.TileSize
    $numMacs = [int]$config.NumMacs
    $runId = "N${N}_T${tileSize}_M${numMacs}"
    $runIdLower = $runId.ToLower()
    $topEntity = "matrix_mult_tiled_top_$runIdLower"
    $runDir = Join-Path $baseOutputDir $runId
    $generatedDir = Join-Path $runDir "generated"
    $quartusOutDir = Join-Path $runDir "quartus_output"
    $wrapperPath = Join-Path $generatedDir "$topEntity.vhd"
    $quartusProject = "${ProjectName}_$runIdLower"
    $qpfPath = Join-Path $runDir "$quartusProject.qpf"
    $qsfPath = Join-Path $runDir "$quartusProject.qsf"
    $simLogPath = Join-Path $runDir "simulation.log"
    $quartusLogPath = Join-Path $runDir "quartus_compile.log"

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "Run $runId"
    Write-Host "============================================================"

    New-Item -ItemType Directory -Force -Path $runDir, $generatedDir, $quartusOutDir | Out-Null
    New-ExperimentWrapper -Path $wrapperPath -EntityName $topEntity -N $N -TileSize $tileSize -NumMacs $numMacs -DataWidth $DataWidth -AccWidth $AccWidth
    New-ExperimentQpf -Path $qpfPath -ProjectRevision $quartusProject
    New-ExperimentQsf -Path $qsfPath -TopEntity $topEntity -OutputDirectory $quartusOutDir -WrapperPath $wrapperPath

    $execCycles = $null
    if (-not $SkipSimulation) {
        $simCommand = @(
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            $tiledTestScript,
            "-N",
            "$N",
            "-TileSize",
            "$tileSize",
            "-NumMacs",
            "$numMacs",
            "-DataWidth",
            "$DataWidth",
            "-AccWidth",
            "$AccWidth"
        )

        $simResult = Invoke-CapturedCommand -Command $simCommand -LogPath $simLogPath
        $cyclesText = Get-RegexValue -Text $simResult.Text -Patterns @("Ciclos de execucao:\s*([0-9]+)")

        if ($null -ne $cyclesText) {
            $execCycles = [double]$cyclesText
        }
    }

    $flowStatus = "skipped"
    if (-not $SkipQuartus) {
        $quartusCommand = @($quartusSh, "--flow", "compile", $quartusProject)
        $quartusResult = Invoke-CapturedCommand -Command $quartusCommand -LogPath $quartusLogPath -WorkingDirectory $runDir

        if ($quartusResult.ExitCode -eq 0) {
            $flowStatus = "success"
        } else {
            $flowStatus = "failed"
        }
    }

    $reports = Read-QuartusReports -RunDir $runDir
    $flowFromReport = Get-RegexValue -Text $reports -Patterns @("Flow Status\s*:\s*(.+)")
    if ($null -ne $flowFromReport) {
        $flowStatus = $flowFromReport
    }

    $alms = Get-ResourceTriple -Text $reports -Patterns @(
        "Total\s+ALMs\s*:\s*([0-9,]+)\s*/\s*([0-9,]+)\s*\(\s*([0-9.]+)\s*%\s*\)",
        "Adaptive\s+Logic\s+Modules.*?:\s*([0-9,]+)\s*/\s*([0-9,]+)\s*\(\s*([0-9.]+)\s*%\s*\)"
    )
    $pins = Get-ResourceTriple -Text $reports -Patterns @(
        "Total\s+pins\s*:\s*([0-9,]+)\s*/\s*([0-9,]+)\s*\(\s*([0-9.]+)\s*%\s*\)"
    )
    $dsps = Get-ResourceTriple -Text $reports -Patterns @(
        "Total\s+DSP\s+Blocks\s*:\s*([0-9,]+)\s*/\s*([0-9,]+)\s*\(\s*([0-9.]+)\s*%\s*\)",
        "DSP\s+block.*?:\s*([0-9,]+)\s*/\s*([0-9,]+)\s*\(\s*([0-9.]+)\s*%\s*\)"
    )
    $memoryBits = Get-ResourceTriple -Text $reports -Patterns @(
        "Total\s+block\s+memory\s+bits\s*:\s*([0-9,]+)\s*/\s*([0-9,]+)\s*\(\s*([0-9.]+)\s*%\s*\)",
        "Block\s+memory\s+bits.*?:\s*([0-9,]+)\s*/\s*([0-9,]+)\s*\(\s*([0-9.]+)\s*%\s*\)"
    )

    $aluts = Convert-ReportNumber (Get-RegexValue -Text $reports -Patterns @(
        "Combinational\s+ALUTs\s*:\s*([0-9,]+)",
        "Total\s+combinational\s+functions\s*:\s*([0-9,]+)"
    ))
    $registers = Convert-ReportNumber (Get-RegexValue -Text $reports -Patterns @(
        "Dedicated\s+logic\s+registers\s*:\s*([0-9,]+)",
        "Total\s+registers\s*:\s*([0-9,]+)"
    ))
    $fmaxMhz = Get-MaxMhz -Text $reports
    $maxFanout = Convert-ReportNumber (Get-RegexValue -Text $reports -Patterns @(
        "Maximum\s+Fan-Out\s*:\s*([0-9.]+)",
        "Max\s+fanout\s*:\s*([0-9.]+)"
    ))
    $avgFanout = Convert-ReportNumber (Get-RegexValue -Text $reports -Patterns @(
        "Average\s+Fan-Out\s*:\s*([0-9.]+)",
        "Avg\s+fanout\s*:\s*([0-9.]+)"
    ))

    $opsExact = ([double]$N * $N * $N) + ([double]$N * $N * ($N - 1))
    $opsApprox = 2.0 * [double]$N * $N * $N
    $execTimeUs = $null
    $gopsEffExact = $null
    $gopsEffApprox = $null
    $gopsPeak = $null
    $peakEfficiency = $null

    if ($null -ne $fmaxMhz -and $null -ne $execCycles -and $fmaxMhz -gt 0 -and $execCycles -gt 0) {
        $execTimeS = $execCycles / ($fmaxMhz * 1000000.0)
        $execTimeUs = $execTimeS * 1000000.0
        $gopsEffExact = $opsExact / $execTimeS / 1000000000.0
        $gopsEffApprox = $opsApprox / $execTimeS / 1000000000.0
        $gopsPeak = 2.0 * $numMacs * $fmaxMhz / 1000.0

        if ($gopsPeak -gt 0) {
            $peakEfficiency = $gopsEffApprox / $gopsPeak
        }
    }

    $rows += [pscustomobject][ordered]@{
        run_id                 = $runId
        top_entity             = $topEntity
        N                      = $N
        tile_size              = $tileSize
        num_macs               = $numMacs
        data_width             = $DataWidth
        acc_width              = $AccWidth
        mem_type               = $MemType
        flow_status            = $flowStatus
        alms                   = $alms.Used
        alms_total             = $alms.Total
        alms_pct               = $alms.Pct
        aluts                  = $aluts
        registers              = $registers
        pins                   = $pins.Used
        pins_total             = $pins.Total
        pins_pct               = $pins.Pct
        dsps                   = $dsps.Used
        dsps_total             = $dsps.Total
        dsps_pct               = $dsps.Pct
        block_memory_bits      = $memoryBits.Used
        block_memory_bits_total = $memoryBits.Total
        block_memory_bits_pct  = $memoryBits.Pct
        fmax_mhz               = $fmaxMhz
        exec_cycles            = $execCycles
        ops_exact              = $opsExact
        ops_approx_2n3         = $opsApprox
        exec_time_us           = $execTimeUs
        gops_eff_exact         = $gopsEffExact
        gops_eff_approx        = $gopsEffApprox
        gops_peak              = $gopsPeak
        peak_efficiency        = $peakEfficiency
        max_fanout             = $maxFanout
        avg_fanout             = $avgFanout
    }
}

$csvPath = Join-Path $baseOutputDir "matrix_tiled_experiments.csv"
$rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "CSV gerado em: $csvPath"
