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

$args = @{}
if ($Only -ne "") { $args.Only = $Only }
if ($N -gt 0) { $args.N = $N }
if ($TileSize -gt 0) { $args.TileSize = $TileSize }
if ($NumMacs -gt 0) { $args.NumMacs = $NumMacs }
if ($DataWidth -gt 0) { $args.DataWidth = $DataWidth }
if ($AccWidth -gt 0) { $args.AccWidth = $AccWidth }
if ($Quartus) { $args.Quartus = $true }
if ($QuartusFull) { $args.QuartusFull = $true }

& (Join-Path $PSScriptRoot "testes\run_testbenchs.ps1") @args
