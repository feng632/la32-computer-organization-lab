param(
    [string]$VivadoBin = 'D:\vivado\Vivado\2023.2\bin',
    [string]$OutputDir = ''
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
if (-not $OutputDir) {
    $OutputDir = Join-Path $env:TEMP ('la32-bp-id-' + [guid]::NewGuid().ToString('N'))
}
if (Test-Path -LiteralPath $OutputDir) { throw 'Use a new output directory to prevent stale results.' }
New-Item -ItemType Directory -Path $OutputDir | Out-Null
$OutputDir = (Resolve-Path -LiteralPath $OutputDir).Path
$src = Join-Path $repo 'myCPU'
$inputs = @('myCPU/ID_stage.v','myCPU/mycpu_head.v','myCPU/regfile.v','myCPU/tools.v',
    'tests/team/pipeline/tb_bp_id.sv','tests/team/pipeline/run_bp_id.ps1')
$hashes = foreach ($path in $inputs) {
    [pscustomobject]@{path=$path; sha256=(Get-FileHash -LiteralPath (Join-Path $repo $path) -Algorithm SHA256).Hash}
}
$hashes | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDir 'source-hashes.json') -Encoding utf8
Push-Location -LiteralPath $OutputDir
try {
    & "$VivadoBin/xvlog.bat" --sv --include $src "$src/ID_stage.v" "$src/regfile.v" `
        "$src/tools.v" "$PSScriptRoot/tb_bp_id.sv" --log compile.log
    if ($LASTEXITCODE -ne 0) { throw 'ID compile failed' }
    & "$VivadoBin/xelab.bat" tb_bp_id -s bp_id --timescale 1ns/1ps --log elaborate.log
    if ($LASTEXITCODE -ne 0) { throw 'ID elaboration failed' }
    & "$VivadoBin/xsim.bat" bp_id --runall --log simulation.log
    if ($LASTEXITCODE -ne 0) { throw 'ID simulation failed' }
    if (-not (Select-String -LiteralPath simulation.log -Pattern '^BP_ID_PASS cases=89 ')) {
        throw 'Missing exact BP_ID_PASS marker; inspect simulation.log'
    }
    foreach ($entry in $hashes) {
        if ((Get-FileHash -LiteralPath (Join-Path $repo $entry.path) -Algorithm SHA256).Hash -ne $entry.sha256) {
            throw "Source changed during run: $($entry.path)"
        }
    }
    Write-Output "BP_ID_SUITE_PASS output=$OutputDir"
} finally { Pop-Location }
