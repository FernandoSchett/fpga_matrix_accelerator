param(
    [switch]$StrictAll
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir
Set-Location $ProjectDir

$legacyPatterns = @(
    "HOST_READ_LATENCY",
    "host_wr_en",
    "host_rd_en",
    "host_rd_addr"
)

$sourceFiles = @(
    "rtl/control/command_interface.vhd",
    "rtl/top/matrix_accelerator_full_top.vhd",
    "rtl/compute/matrix_mult_sdram_tiled_core.vhd"
)

$requiredByFile = @{
    "rtl/control/command_interface.vhd" = @(
        "host_cmd_valid",
        "host_cmd_write",
        "host_cmd_ready",
        "host_rd_valid"
    )
    "rtl/top/matrix_accelerator_full_top.vhd" = @(
        "host_cmd_valid",
        "host_cmd_write",
        "host_cmd_ready",
        "host_rd_valid"
    )
    "rtl/compute/matrix_mult_sdram_tiled_core.vhd" = @(
        "host_cmd_valid",
        "host_cmd_write",
        "host_cmd_ready",
        "rd_valid"
    )
}

foreach ($source in $sourceFiles) {
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Arquivo obrigatorio nao encontrado: $source"
    }
}

$scanFiles = @()
if ($StrictAll) {
    $scanFiles = Get-ChildItem -File -Recurse -Force |
        Where-Object {
            $_.FullName -notmatch "\\(db|incremental_db|output_files|work)\\" -and
            $_.FullName -notmatch "\\parameter_optimization\\results\\"
        } |
        ForEach-Object { $_.FullName }
} else {
    $scanFiles = $sourceFiles
}

$legacyHits = @()
foreach ($file in $scanFiles) {
    $text = Get-Content -LiteralPath $file -Raw
    foreach ($pattern in $legacyPatterns) {
        if ($text -match [regex]::Escape($pattern)) {
            $legacyHits += "${file}: contem interface antiga '$pattern'"
        }
    }
}

if ($legacyHits.Count -gt 0) {
    $legacyHits | ForEach-Object { Write-Host $_ }
    throw "Interface host antiga detectada. Use host_cmd_valid/host_cmd_ready/host_rd_valid."
}

foreach ($source in $sourceFiles) {
    $text = Get-Content -LiteralPath $source -Raw
    foreach ($pattern in $requiredByFile[$source]) {
        if ($text -notmatch [regex]::Escape($pattern)) {
            throw "${source}: faltando handshake SDRAM '$pattern'"
        }
    }
}

Write-Host "PASS: handshake SDRAM fonte RTL sem interface antiga."
