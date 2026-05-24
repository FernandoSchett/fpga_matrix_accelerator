param(
    [string]$Only = "",
    [switch]$Quartus,
    [switch]$QuartusFull
)

$ErrorActionPreference = "Stop"

$args = @{}
if ($Only -ne "") { $args.Only = $Only }
if ($Quartus) { $args.Quartus = $true }
if ($QuartusFull) { $args.QuartusFull = $true }

& (Join-Path $PSScriptRoot "testes\run_testbenchs.ps1") @args
