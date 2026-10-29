param(
    [string]$VivadoBin = 'D:\vivado\Vivado\2023.2\bin',
    [string]$OutputDir = ''
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
if (-not $OutputDir) {
    $OutputDir = Join-Path $env:TEMP ('la32-realdiv-' + [guid]::NewGuid().ToString('N'))
}
if (Test-Path -LiteralPath $OutputDir) { throw 'Use a new output directory to avoid stale artifacts.' }
New-Item -ItemType Directory -Path $OutputDir | Out-Null
$OutputDir = (Resolve-Path -LiteralPath $OutputDir).Path
foreach ($ipName in @('div_signed','div_unsigned')) {
    $ipDir = Join-Path $OutputDir $ipName
    New-Item -ItemType Directory -Path $ipDir | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo "soc_verify/soc_bram/rtl/xilinx_ip/$ipName/$ipName.xci") -Destination $ipDir
}
$generation = @'
create_project -in_memory -part xc7a200tfbg676-1
set_property target_language Verilog [current_project]
read_ip div_signed/div_signed.xci
read_ip div_unsigned/div_unsigned.xci
generate_target simulation [get_ips]
exit
'@
Set-Content -LiteralPath (Join-Path $OutputDir 'generate.tcl') -Value $generation -Encoding ascii
Push-Location -LiteralPath $OutputDir
try {
    & "$VivadoBin/vivado.bat" -mode batch -notrace -source generate.tcl -log generate.log -journal generate.jou
    if ($LASTEXITCODE -ne 0) { throw 'IP generation failed' }
    & "$VivadoBin/xvhdl.bat" --work work "$OutputDir/div_signed/sim/div_signed.vhd" "$OutputDir/div_unsigned/sim/div_unsigned.vhd"
    if ($LASTEXITCODE -ne 0) { throw 'VHDL compilation failed' }
    $src = Join-Path $repo 'myCPU'
    & "$VivadoBin/xvlog.bat" --sv --include $src "$src/EXE_stage.v" "$src/alu.v" "$PSScriptRoot/tb_div_cancel.sv"
    if ($LASTEXITCODE -ne 0) { throw 'Verilog compilation failed' }
    & "$VivadoBin/xelab.bat" work.tb_div_cancel -L div_gen_v5_1_20 -s real_div_cancel --timescale 1ns/1ps
    if ($LASTEXITCODE -ne 0) { throw 'Elaboration failed' }
    & "$VivadoBin/xsim.bat" real_div_cancel -runall
    if ($LASTEXITCODE -ne 0) { throw 'Simulation failed' }
    if (-not (Select-String -LiteralPath 'xsim.log' -Pattern '^REAL_DIV_CANCEL_PASS')) {
        throw 'No PASS marker; inspect xsim.log (xsim may return zero after a fatal assertion).'
    }
    Write-Output "PASS: evidence saved in $OutputDir"
} finally {
    Pop-Location
}
