# =============================================================================
# P3 分支预测性能统计一键复现
#
# 用法（仓库根目录 PowerShell）：
#   ./tests/team/integration/bp_p3/run_bp_p3.ps1
# 可选参数：
#   -VivadoBin "C:\Xilinx\Vivado\2023.2\bin"
#   -Python "python"
#   -OutputDir "C:\Temp\bp_p3"
#
# 做什么：
#   1. asm.py 自检 → 汇编 bp_p2 与 bp_p3 全部 .s 程序
#   2. 编译两份顶层：BP_ENABLE=0（对照）与 BP_ENABLE=1（开预测）
#   3. 每个程序在每个配置下各跑一遍，先判功能（写回是否等于 expect），
#      再收集周期、分支数、准确率、命中率等统计
#   4. 输出按程序对比的汇总表与 summary.csv
#
# 判据：功能项必须全部 PASS（否则统计数字没有意义），
#       统计只做记录，不设通过阈值。
# =============================================================================
param(
    [string]$VivadoBin = "C:\Xilinx\Vivado\2023.2\bin",
    [string]$Python    = "python",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

if ($PSScriptRoot) { $here = $PSScriptRoot }
else { $here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here)))
$p2   = Join-Path (Split-Path -Parent $here) "bp_p2"

$src = Join-Path $repo "myCPU"
$tb  = Join-Path $here "tb_bp_p3.sv"
$asm = Join-Path $p2   "asm.py"
if (-not (Test-Path (Join-Path $src "mycpu_top.v"))) { throw "仓库根推算错误: $repo" }
if (-not (Test-Path $asm)) { throw "找不到汇编器: $asm" }

if ([string]::IsNullOrEmpty($OutputDir)) {
    $OutputDir = Join-Path ([System.IO.Path]::GetTempPath()) "bp_p3_run"
}
# 不删除已有目录（避免误删），存在时改用带时间戳的子目录
if (Test-Path $OutputDir) {
    $OutputDir = $OutputDir + "_" + (Get-Date -Format "MMdd_HHmmss")
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$hexDir = Join-Path $OutputDir "hex"
New-Item -ItemType Directory -Force -Path $hexDir | Out-Null
Set-Location $OutputDir

Write-Host "=== 1. 汇编器自检 ==="
& $Python $asm --selftest | Select-Object -Last 1
if ($LASTEXITCODE -ne 0) { throw "asm.py 自检失败" }

Write-Host ""
Write-Host "=== 2. 汇编测试程序 ==="
$sources = @()
$sources += Get-ChildItem -LiteralPath (Join-Path $p2 "prog")   -Filter "*.s" | Sort-Object Name
$sources += Get-ChildItem -LiteralPath (Join-Path $here "prog") -Filter "*.s" | Sort-Object Name
$progs = @()
foreach ($p in $sources) {
    $hex = Join-Path $hexDir ($p.BaseName + ".hex")
    & $Python $asm $p.FullName -o $hex | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "汇编失败: $($p.Name)" }
    $progs += [pscustomobject]@{
        Name   = $p.BaseName
        Hex    = $hex
        Expect = Join-Path $p.DirectoryName ($p.BaseName + ".expect")
    }
    Write-Host ("  {0,-14} <- {1}" -f $p.BaseName, (Split-Path -Leaf $p.FullName))
}

Write-Host ""
Write-Host "=== 3. 编译 RTL + TB (两套配置) ==="
$files = Get-ChildItem -LiteralPath $src -Filter "*.v" |
         Where-Object { $_.Name -ne "mycpu_head.v" } |
         ForEach-Object { $_.FullName }

$configs = @(
    [pscustomobject]@{ Tag = "bp0"; Defs = @();               Snapshot = "p3_bp0" },
    [pscustomobject]@{ Tag = "bp1"; Defs = @("-d", "BP_ON");  Snapshot = "p3_bp1" }
)

foreach ($c in $configs) {
    & "$VivadoBin\xvlog.bat" -sv -i $src @($c.Defs) $files $tb -log "xvlog_$($c.Tag).log" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Get-Content "xvlog_$($c.Tag).log" | Select-String "ERROR"
        throw "xvlog 失败 ($($c.Tag))"
    }
    & "$VivadoBin\xelab.bat" tb_bp_p3 -s $c.Snapshot -timescale 1ns/1ps -log "xelab_$($c.Tag).log" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Get-Content "xelab_$($c.Tag).log" | Select-String "ERROR"
        throw "xelab 失败 ($($c.Tag))"
    }
    Write-Host "  $($c.Tag): xvlog / xelab 通过"
}

Write-Host ""
Write-Host "=== 4. 逐程序 × 逐配置运行 ==="
$rows = @()
$allPass = $true

foreach ($prog in $progs) {
    Copy-Item $prog.Hex    (Join-Path $OutputDir "prog.hex")   -Force
    Copy-Item $prog.Expect (Join-Path $OutputDir "expect.txt") -Force
    Set-Content -Path (Join-Path $OutputDir "name.txt") -Value $prog.Name -Encoding ascii -NoNewline

    foreach ($c in $configs) {
        $log = "sim_$($prog.Name)_$($c.Tag).log"
        & "$VivadoBin\xsim.bat" $c.Snapshot -runall -log $log | Out-Null
        $lines = Get-Content $log
        $pass  = ($lines -match "P3_PASS").Count -gt 0
        $stat  = @($lines | Where-Object { $_ -match "^BP_CSV," })
        if ($stat.Count -gt 0) {
            $f = [string]$stat[0]
            $f = $f.Split(",")
            $rows += [pscustomobject]@{
                Program  = $prog.Name
                BP       = $c.Tag
                # 字段顺序: BP_CSV,program,bp,cycles,inst,ipc,branch,cond,uncond,
                #           taken,btb_hit,ok,accuracy,redirect,fail_cold,fail_dir,
                #           fail_tgt,fail_miss,fs_drop
                Cycles   = [int]$f[3]
                Inst     = [int]$f[4]
                IPC      = [double]$f[5]
                Branch   = [int]$f[6]
                Cond     = [int]$f[7]
                Uncond   = [int]$f[8]
                Taken    = [int]$f[9]
                BtbHit   = [int]$f[10]
                Ok       = [int]$f[11]
                Accuracy = [double]$f[12]
                Redirect = [int]$f[13]
                FailCold = [int]$f[14]
                FailDir  = [int]$f[15]
                FailTgt  = [int]$f[16]
                FailMiss = [int]$f[17]
                FsDrop   = [int]$f[18]
                Committed= [int]$f[19]
                CPI      = [double]$f[20]
                NbRedir  = [int]$f[21]
                Pass     = $pass
            }
        } else {
            $rows += [pscustomobject]@{
                Program = $prog.Name; BP = $c.Tag; Cycles = -1; Inst = -1; IPC = 0
                Branch = 0; Cond = 0; Uncond = 0; Taken = 0; BtbHit = 0; Ok = 0
                Accuracy = 0; Redirect = 0; FailCold = 0; FailDir = 0; FailTgt = 0
                FailMiss = 0; FsDrop = 0; Committed = 0; CPI = 0; NbRedir = 0; Pass = $false
            }
        }
        if (-not $pass) {
            $allPass = $false
            Write-Host ("  {0,-14} {1}  FUNCTION FAIL" -f $prog.Name, $c.Tag)
            $lines | Where-Object { $_ -match "\[FAIL\]|P3_FAIL" } | ForEach-Object { Write-Host "      $_" }
        }
    }
    # 功能项先过，再看数字
    $r0 = @($rows | Where-Object { $_.Program -eq $prog.Name -and $_.BP -eq "bp0" }) | Select-Object -First 1
    $r1 = @($rows | Where-Object { $_.Program -eq $prog.Name -and $_.BP -eq "bp1" }) | Select-Object -First 1
    if ($r0 -and $r1 -and $r0.Pass -and $r1.Pass) {
        $delta = $r0.Cycles - $r1.Cycles
        $pct   = if ($r0.Cycles -gt 0) { 100.0 * $delta / $r0.Cycles } else { 0 }
        Write-Host ("  {0,-14} pass  cycles {1,6} -> {2,6}  ({3,5:N1}% faster)  acc {4,6:P1}" -f `
                    $prog.Name, $r0.Cycles, $r1.Cycles, $pct, $r1.Accuracy)
    }
}

Write-Host ""
Write-Host "=== 5. 汇总表 ==="
$rows | Sort-Object Program, BP | Format-Table -AutoSize `
    @{ L = "program";  E = { $_.Program };  W = 12 },
    @{ L = "bp";       E = { $_.BP };       W = 4  },
    @{ L = "cycles";   E = { $_.Cycles };   W = 7  },
    @{ L = "inst";     E = { $_.Inst };     W = 6  },
    @{ L = "ipc";      E = { "{0:N3}" -f $_.IPC }; W = 6 },
    @{ L = "branch";   E = { $_.Branch };   W = 7  },
    @{ L = "btb_hit";  E = { $_.BtbHit };   W = 8  },
    @{ L = "ok";       E = { $_.Ok };       W = 4  },
    @{ L = "acc";      E = { "{0:P1}" -f $_.Accuracy }; W = 7 },
    @{ L = "redir";    E = { $_.Redirect }; W = 6  },
    @{ L = "cold";     E = { $_.FailCold }; W = 5  },
    @{ L = "dir";      E = { $_.FailDir };  W = 4  },
    @{ L = "tgt";      E = { $_.FailTgt };  W = 4  },
    @{ L = "miss";     E = { $_.FailMiss }; W = 5  },
    @{ L = "nb_redir"; E = { $_.NbRedir };  W = 8  },
    @{ L = "cpi";      E = { "{0:N3}" -f $_.CPI }; W = 6 } |
    Out-String -Width 220 | Write-Host

$csv = Join-Path $OutputDir "summary.csv"
$rows | Select-Object Program, BP, Cycles, Inst, IPC, Branch, Cond, Uncond, Taken, BtbHit, Ok,
                        Accuracy, Redirect, FailCold, FailDir, FailTgt, FailMiss, FsDrop,
                        Committed, CPI, NbRedir, Pass |
        Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
Write-Host "汇总已写入 $csv"

Write-Host ""
if ($allPass) { Write-Host "RESULT: PASS" ; exit 0 }
else          { Write-Host "RESULT: FAIL" ; exit 1 }
