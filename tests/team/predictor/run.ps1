param(
    [string]$VivadoBin = 'E:\Vivado\Vivado\2023.2\bin',
    [string]$OutputDir = "$env:TEMP\la32-predictor-test"
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot\..\..\..").Path
New-Item -ItemType Directory -Force $OutputDir | Out-Null
Push-Location $OutputDir
try {
    & "$VivadoBin\xvlog.bat" --sv "$repo\myCPU\branch_predictor.v" "$PSScriptRoot\tb_predictor.sv"
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }
    & "$VivadoBin\xelab.bat" tb_predictor -s predictor_test --timescale 1ns/1ps
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed' }
    & "$VivadoBin\xsim.bat" predictor_test -runall -log simulation.log
    if ($LASTEXITCODE -ne 0) { throw 'xsim failed' }
    if (!(Select-String -Path simulation.log -Pattern 'PREDICTOR_PASS')) { throw 'PASS marker missing' }
} finally { Pop-Location }
