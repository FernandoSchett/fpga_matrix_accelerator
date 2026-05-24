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

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TestsDir = Split-Path -Parent $ScriptDir
$Runner = Join-Path $TestsDir "run_testbenchs.ps1"

$args = @{
    Only      = "tb_matrix_mult_tiled_top"
    N         = $N
    TileSize  = $TileSize
    NumMacs   = $NumMacs
    DataWidth = $DataWidth
    AccWidth  = $AccWidth
}

if ($Quartus) { $args.Quartus = $true }
if ($QuartusFull) { $args.QuartusFull = $true }

& $Runner @args
