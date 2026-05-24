param(
    [int]$N = 4,
    [int]$TileSize = 2,
    [int]$NumMacs = 2,
    [int]$DataWidth = 8,
    [int]$AccWidth = 32,
    [switch]$Quartus,
    [switch]$QuartusFull
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$runner = Join-Path $scriptDir "_run_testbench.ps1"

$sources = @(
    "rtl/matrix_tiled/pkg/matrix_tiled_pkg.vhd",
    "rtl/matriz_4x4/blocks/mac_unit.vhd",
    "rtl/matrix_tiled/memory/matrix_single_port_ram.vhd",
    "rtl/matrix_tiled/compute/matrix_tiled_compute_core.vhd",
    "rtl/matrix_tiled/matrix_mult_tiled_top.vhd",
    "testbench/matrix_tiled/tb_matrix_mult_tiled_top.vhd"
)

$args = @{
    TestName        = "tb_matrix_mult_tiled_top_N${N}_T${TileSize}_M${NumMacs}"
    TestbenchEntity = "tb_matrix_mult_tiled_top"
    Sources         = $sources
    ExtraGenerics   = @(
        "-gN=$N",
        "-gTILE_SIZE=$TileSize",
        "-gNUM_MACS=$NumMacs",
        "-gDATA_WIDTH=$DataWidth",
        "-gACC_WIDTH=$AccWidth"
    )
}

if ($Quartus) { $args.Quartus = $true }
if ($QuartusFull) { $args.QuartusFull = $true }

& $runner @args
