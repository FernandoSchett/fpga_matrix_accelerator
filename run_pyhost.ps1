param(
    [switch]$SkipGenerate,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$ProjectDir = $PSScriptRoot
Set-Location $ProjectDir

function Invoke-Step {
    param([string[]]$Command)

    Write-Host ""
    Write-Host ("$ " + ($Command -join " "))

    $exe = $Command[0]
    $args = @()
    if ($Command.Count -gt 1) {
        $args = $Command[1..($Command.Count - 1)]
    }

    & $exe @args

    if ($LASTEXITCODE -ne 0) {
        throw "Comando falhou com exit code ${LASTEXITCODE}: $($Command -join ' ')"
    }
}

if (-not $SkipGenerate) {
    Invoke-Step -Command @("python", ".\py_matrix_host\main.py", "generate")
}

$uartCommand = @("python", ".\py_matrix_host\main.py", "uart")
if ($DryRun) {
    $uartCommand += "--dry-run"
}

Invoke-Step -Command $uartCommand
