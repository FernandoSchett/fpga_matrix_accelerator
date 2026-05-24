param(
    [switch]$Quartus,
    [switch]$QuartusFull,
    [switch]$SkipGenerate
)

$ErrorActionPreference = "Stop"

$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TestsDir = Join-Path $ProjectDir "testes"

Set-Location $ProjectDir

$tb2x2Args = @{}
$tb4x4Args = @{}
$tbTiledArgs = @{}

if ($Quartus) {
    $tb2x2Args.Quartus = $true
    $tb4x4Args.Quartus = $true
    $tbTiledArgs.Quartus = $true
}

if ($QuartusFull) {
    $tb2x2Args.QuartusFull = $true
    $tb4x4Args.QuartusFull = $true
    $tbTiledArgs.QuartusFull = $true
}

if ($SkipGenerate) {
    $tb2x2Args.SkipGenerate = $true
}

& (Join-Path $TestsDir "run_tb_matrix_mult_top.ps1") @tb2x2Args
& (Join-Path $TestsDir "run_tb_matrix_mult_4x4_top.ps1") @tb4x4Args
& (Join-Path $TestsDir "run_tb_matrix_mult_tiled_top.ps1") @tbTiledArgs

Write-Host ""
Write-Host "PASS: todos os testbenchs passaram."
