# C06 module-level hardware interrupt input test
# Reproduce: run from anywhere, the script derives the repo root from its own path.
#   powershell -ExecutionPolicy Bypass -File tests\team\integration\int_hw\run_int_hw.ps1
#
# Requires Vivado's xvlog/xelab/xsim. Pass -VivadoBin if Vivado is not in the default path.

param(
    [string]$VivadoBin = 'C:\Xilinx\Vivado\2023.2\bin'
)

$ErrorActionPreference = 'Stop'

$benchDir = $PSScriptRoot
$repo     = (Resolve-Path (Join-Path $benchDir '../../../..')).Path
$src      = Join-Path $repo 'myCPU'
$tb       = Join-Path $benchDir 'tb_int_hw.sv'

if (-not (Test-Path -LiteralPath (Join-Path $VivadoBin 'xvlog.bat'))) {
    throw "xvlog.bat not found in '$VivadoBin'. Pass -VivadoBin explicitly."
}
if (-not (Test-Path -LiteralPath $tb)) {
    throw "testbench not found: $tb"
}

$files = Get-ChildItem -LiteralPath $src -Filter '*.v' |
         Where-Object { $_.Name -ne 'mycpu_head.v' } |
         ForEach-Object { $_.FullName }

$runDir = Join-Path $env:TEMP ('la32-int-hw-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runDir | Out-Null

$logPath = Join-Path $benchDir 'int-hw-latest.log'

Push-Location -LiteralPath $runDir
try {
    Write-Output "compile: $($files.Count) RTL files + tb_int_hw.sv"
    & "$VivadoBin\xvlog.bat" --sv -i $src @files $tb
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }

    & "$VivadoBin\xelab.bat" tb_int_hw -s int_hw -timescale 1ns/1ps
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed' }

    & "$VivadoBin\xsim.bat" int_hw -runall | Tee-Object -FilePath $logPath
    if ($LASTEXITCODE -ne 0) { throw 'xsim failed' }

    $log = Get-Content -LiteralPath $logPath -Raw
    if ($log -notmatch 'INT_HW_PASS') {
        throw "bench did not report INT_HW_PASS; inspect $logPath"
    }
    Write-Output ''
    Write-Output "INT_HW_OK  (log: $logPath)"
}
finally {
    Pop-Location
    Remove-Item -LiteralPath $runDir -Recurse -Force -ErrorAction SilentlyContinue
}
