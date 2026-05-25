param(
    [string]$Only = "",
    [int]$N = 0,
    [int]$TileSize = 0,
    [int]$NumMacs = 0,
    [int]$DataWidth = 0,
    [int]$AccWidth = 0,
    [int]$VsimRetryCount = 10,
    [int]$VsimRetrySeconds = 30,
    [switch]$Quartus,
    [switch]$QuartusFull
)

$ErrorActionPreference = "Stop"

$forwardArgs = @{}
if ($Only -ne "") { $forwardArgs.Only = $Only }
if ($N -gt 0) { $forwardArgs.N = $N }
if ($TileSize -gt 0) { $forwardArgs.TileSize = $TileSize }
if ($NumMacs -gt 0) { $forwardArgs.NumMacs = $NumMacs }
if ($DataWidth -gt 0) { $forwardArgs.DataWidth = $DataWidth }
if ($AccWidth -gt 0) { $forwardArgs.AccWidth = $AccWidth }
if ($VsimRetryCount -gt 0) { $forwardArgs.VsimRetryCount = $VsimRetryCount }
if ($VsimRetrySeconds -gt 0) { $forwardArgs.VsimRetrySeconds = $VsimRetrySeconds }
if ($Quartus) { $forwardArgs.Quartus = $true }
if ($QuartusFull) { $forwardArgs.QuartusFull = $true }

& (Join-Path $PSScriptRoot "testes\run_testbenchs.ps1") @forwardArgs
