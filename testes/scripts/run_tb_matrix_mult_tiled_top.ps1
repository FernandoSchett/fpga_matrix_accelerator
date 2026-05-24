param(
    [switch]$Quartus,
    [switch]$QuartusFull
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TestsDir = Split-Path -Parent $ScriptDir
$Runner = Join-Path $TestsDir "run_testbenchs.ps1"

$args = @{
    Only = "tb_matrix_mult_tiled_top"
}

if ($Quartus) {
    $args.Quartus = $true
}

if ($QuartusFull) {
    $args.QuartusFull = $true
}

& $Runner @args