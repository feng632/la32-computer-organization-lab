param(
    [string]$VivadoBin = 'D:\vivado\Vivado\2023.2\bin',
    [string]$OutputDir = ''
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
if (-not $OutputDir) {
    $OutputDir = Join-Path $env:TEMP ('la32-ex9-' + [guid]::NewGuid().ToString('N'))
}
if (Test-Path -LiteralPath $OutputDir) { throw 'Use a new output directory to prevent stale results.' }
New-Item -ItemType Directory -Path $OutputDir | Out-Null
$OutputDir = (Resolve-Path -LiteralPath $OutputDir).Path
$src = Join-Path $repo 'myCPU'
$files = Get-ChildItem -LiteralPath $src -Filter '*.v' |
    Where-Object { $_.Name -ne 'mycpu_head.v' } | ForEach-Object { $_.FullName }
Push-Location -LiteralPath $OutputDir
try {
    # tb_ex8_smoke supplies rejecting divider guards. Only the selected ex9 tops
    # are elaborated; tb_ex8_smoke itself is not executed.
    & "$VivadoBin/xvlog.bat" --sv --include $src $files `
        "$PSScriptRoot/tb_ex8_smoke.sv" "$PSScriptRoot/tb_ex9_program.sv" `
        "$PSScriptRoot/tb_ex9_controls.sv"
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }
    & "$VivadoBin/xelab.bat" tb_ex9_program -s ex9_program --timescale 1ns/1ps
    if ($LASTEXITCODE -ne 0) { throw 'Program elaboration failed' }
    for ($caseId=0; $caseId -le 11; $caseId++) {
        Set-Content -LiteralPath case.txt -Value $caseId -Encoding ascii
        $logFile = "case$caseId.log"
        & "$VivadoBin/xsim.bat" ex9_program --runall --log $logFile
        if ($LASTEXITCODE -ne 0) { throw "xsim failed case $caseId" }
        if (-not (Select-String -LiteralPath $logFile -Pattern "^EX9_PROGRAM_PASS CASE=$caseId ")) {
            throw "Missing PASS for case $caseId; inspect $logFile"
        }
    }
    & "$VivadoBin/xelab.bat" tb_ex9_controls -s ex9_controls --timescale 1ns/1ps
    if ($LASTEXITCODE -ne 0) { throw 'Controls elaboration failed' }
    & "$VivadoBin/xsim.bat" ex9_controls --runall --log controls.log
    if ($LASTEXITCODE -ne 0) { throw 'Controls simulation failed' }
    if (-not (Select-String -LiteralPath controls.log -Pattern '^EX9_CONTROLS_PASS ')) {
        throw 'Missing controls PASS marker'
    }
    Write-Output "EX9_SUITE_PASS program_cases=12 control_checkpoints=9 output=$OutputDir"
} finally {
    Pop-Location
}
