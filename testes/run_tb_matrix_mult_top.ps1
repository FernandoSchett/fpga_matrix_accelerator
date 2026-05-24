param(
    [string]$EnvFile = "",
    [switch]$SkipGenerate,
    [switch]$Quartus,
    [switch]$QuartusFull
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$runner = Join-Path $scriptDir "_run_testbench.ps1"

if ($EnvFile -eq "") {
    $EnvFile = Join-Path (Split-Path -Parent $scriptDir) ".env"
}

$sources = @(
    "rtl/matriz_4x4/blocks/mac_unit.vhd",
    "rtl/matriz_4x4/core/matrix_mult_core.vhd",
    "rtl/matrix_accelerator_top/matrix_mult_top.vhd",
    "testbench/matrix_accelerator_top/tb_matrix_mult_top.vhd"
)

$args = @{
    TestName        = "tb_matrix_mult_top"
    TestbenchEntity = "tb_matrix_mult_top"
    Sources         = $sources
    EnvFile         = $EnvFile
    GenerateVectors = $true
    UseEnvGenerics  = $true
    Require2x2Env   = $true
}

if ($SkipGenerate) { $args.SkipGenerate = $true }
if ($Quartus) { $args.Quartus = $true }
if ($QuartusFull) { $args.QuartusFull = $true }

& $runner @args
