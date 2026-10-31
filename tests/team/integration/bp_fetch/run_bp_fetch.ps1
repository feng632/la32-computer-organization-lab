# =============================================================================
# C 的 P1 测试复现脚本：IF 预测查询 / 锁存 / 纠正（TEAM-BP-1.0）
#
# 用法（在任意目录执行）：
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\team\integration\bp_fetch\run_bp_fetch.ps1
# 可选参数：
#   -VivadoBin "C:\Xilinx\Vivado\2023.2\bin"   指定工具目录
#   -OutputDir "C:\Temp\bp_fetch"              指定临时工作目录
#
# 说明：本脚本只编译 myCPU/*.v 与 tb_bp_fetch.sv，不涉及 VHDL 的 div IP
#       （TB 内自带占位模块），因此不需要完整工程即可运行。
# =============================================================================
param(
    [string]$VivadoBin = "C:\Xilinx\Vivado\2023.2\bin",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

# 由脚本位置推算仓库根：tests/team/integration/bp_fetch -> 上溯 4 层
if ($PSScriptRoot) { $here = $PSScriptRoot }
else { $here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here)))

$tb = Join-Path $here "tb_bp_fetch.sv"
if (-not (Test-Path $tb)) { throw "找不到测试平台: $tb" }
if (-not (Test-Path (Join-Path $repo "myCPU\IF_stage.v"))) { throw "仓库根推算错误: $repo" }

if ([string]::IsNullOrEmpty($OutputDir)) {
    $OutputDir = Join-Path ([System.IO.Path]::GetTempPath()) "bp_fetch_run"
}
if (Test-Path $OutputDir) { Remove-Item -Recurse -Force $OutputDir }
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
Set-Location $OutputDir

$src = Join-Path $repo "myCPU"
# mycpu_head.v 是宏头文件，通过 -i 包含，不单独编译
$files = Get-ChildItem -LiteralPath $src -Filter "*.v" |
         Where-Object { $_.Name -ne "mycpu_head.v" } |
         ForEach-Object { $_.FullName }

Write-Host "repo      : $repo"
Write-Host "rtl files : $($files.Count)"
Write-Host "tb        : $tb"
Write-Host "workdir   : $OutputDir"

& "$VivadoBin\xvlog.bat" -sv -i $src $files $tb -log xvlog.log | Out-Null
if ($LASTEXITCODE -ne 0) { Get-Content xvlog.log | Select-String "ERROR"; throw "xvlog 失败" }
Write-Host "xvlog OK"

& "$VivadoBin\xelab.bat" tb_bp_fetch -s bp_fetch -timescale 1ns/1ps -log xelab.log | Out-Null
if ($LASTEXITCODE -ne 0) { Get-Content xelab.log | Select-String "ERROR"; throw "xelab 失败" }
Write-Host "xelab OK"

& "$VivadoBin\xsim.bat" bp_fetch -runall -log simulate.log | Out-Null

$logText = Get-Content simulate.log
$logText | Where-Object { $_ -match "\[PASS\]|\[FAIL\]|BP_FETCH_SUMMARY|BP_FETCH_" }
$summary = $logText | Where-Object { $_ -match "BP_FETCH_SUMMARY" }
Write-Host ""
Write-Host $summary
if ($logText -match "BP_FETCH_PASS") {
    Write-Host "RESULT: PASS"
    exit 0
} else {
    Write-Host "RESULT: FAIL"
    exit 1
}
