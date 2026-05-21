param(
    [switch]$Quartus,
    [switch]$QuartusFull
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$runner = Join-Path $scriptDir "_run_testbench.ps1"

$sources = @(
    "mac_unity.vhd",
    "matrix_mult_core.vhd",
    "matrix_mult_4x4_top.vhd",
    "tb_matrix_mult_4x4_top.vhd"
)

$args = @{
    TestName        = "tb_matrix_mult_4x4_top"
    TestbenchEntity = "tb_matrix_mult_4x4_top"
    Sources         = $sources
}

if ($Quartus) { $args.Quartus = $true }
if ($QuartusFull) { $args.QuartusFull = $true }

& $runner @args
