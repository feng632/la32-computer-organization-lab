# =============================================================================
# P2 定向程序测试一键复现
#
# 用法（仓库根目录 PowerShell）：
#   ./tests/team/integration/bp_p2/run_bp_p2.ps1
# 可选参数：
#   -VivadoBin "C:\Xilinx\Vivado\2023.2\bin"
#   -Python "python"
#   -OutputDir "C:\Temp\bp_p2"
#
# 流程：asm.py 自检 → 汇编 prog/*.s → 编译 RTL+TB 一次 → 逐个程序跑并比对结果
# 说明：TB 不例化预测器，顶层预测输入为 tie-off，等价于 BP_ENABLE=0，
#       因此本脚本验证的是"预测关闭时的架构行为"，是 BP=1 的对照基线。
# =============================================================================
param(
    [string]$VivadoBin = "C:\Xilinx\Vivado\2023.2\bin",
    [string]$Python    = "python",
    [string]$OutputDir = "",
    [switch]$BpOn
)

# -BpOn 用 -d BP_ON 编译，把 TB 里的 BP_EN 置 1，验证预测生效时的错误路径行为
$defs = @()
$snap = "p2_bp0"
if ($BpOn) { $defs = @("-d", "BP_ON"); $snap = "p2_bp1" }

$ErrorActionPreference = "Stop"

if ($PSScriptRoot) { $here = $PSScriptRoot }
else { $here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here)))

$src = Join-Path $repo "myCPU"
$tb  = Join-Path $here "tb_bp_p2.sv"
$asm = Join-Path $here "asm.py"
if (-not (Test-Path (Join-Path $src "mycpu_top.v"))) { throw "仓库根推算错误: $repo" }

if ([string]::IsNullOrEmpty($OutputDir)) {
    $OutputDir = Join-Path ([System.IO.Path]::GetTempPath()) "bp_p2_run"
}
# 不删已有目录（避免误删），存在时追加配置与时间戳
if (Test-Path $OutputDir) { $OutputDir = $OutputDir + "_" + $snap + "_" + (Get-Date -Format "MMdd_HHmmss") }
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
Set-Location $OutputDir

Write-Host "=== 1. 汇编器自检 ==="
& $Python $asm --selftest
if ($LASTEXITCODE -ne 0) { throw "asm.py 自检失败" }

Write-Host ""
Write-Host "=== 2. 汇编测试程序 ==="
$progs = Get-ChildItem -LiteralPath (Join-Path $here "prog") -Filter "*.s"
foreach ($p in $progs) {
    $hex = Join-Path $p.DirectoryName ($p.BaseName + ".hex")
    & $Python $asm $p.FullName -o $hex | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "汇编失败: $($p.Name)" }
    Write-Host ("  {0,-26} -> {1}" -f $p.Name, (Split-Path -Leaf $hex))
}

Write-Host ""
Write-Host "=== 3. 编译 RTL + TB ==="
$files = Get-ChildItem -LiteralPath $src -Filter "*.v" |
         Where-Object { $_.Name -ne "mycpu_head.v" } |
         ForEach-Object { $_.FullName }
& "$VivadoBin\xvlog.bat" -sv -i $src @defs $files $tb -log "xvlog_$snap.log" | Out-Null
if ($LASTEXITCODE -ne 0) { Get-Content "xvlog_$snap.log" | Select-String "ERROR"; throw "xvlog 失败" }
& "$VivadoBin\xelab.bat" tb_bp_p2 -s $snap -timescale 1ns/1ps -log "xelab_$snap.log" | Out-Null
if ($LASTEXITCODE -ne 0) { Get-Content "xelab_$snap.log" | Select-String "ERROR"; throw "xelab 失败" }
Write-Host "  xvlog / xelab 通过 (snapshot=$snap, defs=[$($defs -join ' ')])"

Write-Host ""
Write-Host "=== 4. 逐个程序运行 ==="
$allPass = $true
foreach ($p in $progs) {
    $base = $p.BaseName
    Copy-Item (Join-Path $p.DirectoryName "$base.hex") (Join-Path $OutputDir "prog.hex") -Force
    Copy-Item (Join-Path $p.DirectoryName "$base.expect") (Join-Path $OutputDir "expect.txt") -Force
    & "$VivadoBin\xsim.bat" $snap -runall -log "sim_$($base)_$snap.log" | Out-Null
    $lines = Get-Content "sim_$($base)_$snap.log"
    $sum = $lines | Where-Object { $_ -match "P2_SUMMARY" }
    $fail = $lines | Where-Object { $_ -match "\[FAIL\]|P2_FAIL" }
    if ($lines -match "P2_PASS") {
        Write-Host ("  {0,-26} {1}" -f $base, $sum)
    } else {
        $allPass = $false
        Write-Host ("  {0,-26} FAIL" -f $base)
        $fail | ForEach-Object { Write-Host "      $_" }
    }
}

Write-Host ""
Write-Host ""
Write-Host ("运行配置: snapshot={0}  BP_EN={1}" -f $snap, $(if ($BpOn) { 1 } else { 0 }))
if ($allPass) { Write-Host "RESULT: PASS" ; exit 0 }
else { Write-Host "RESULT: FAIL" ; exit 1 }
