# ex8 short-program smoke test

2026-10-29: executed with Vivado 2023.2 on the uncommitted B feature working tree.
Result: `EX8_SMOKE_PASS write_checks=22 exceptions=1 returns=1 stores=1`.
Complete simulator log: `ex8-smoke-2026-10-29.log`.

Uses the real IF/ID/EXE/MEM/WB, register file, ALU, top-level wiring and A's CSR.
Instruction memory is a synchronous test ROM. The data interface is monitored:
the only permitted store must happen after ERTN, at address 0, with data 0x55.
The program checks CSR read/write old values, a partial-mask exchange, writes
and reads with rd=0, unknown CSR accesses, immediate ADD dependency, EENTRY setup,
SYS exception code and ERA, software ERA+4, return, and absence of repeated events.
The simulation has a 50us timeout and checks every enabled debug write by PC,
destination, value and uniqueness. Completion occurs at 1240ns.

IMPORTANT: divider placeholders are embedded in the testbench. They return no
results and fail immediately if requested. This test does NOT verify division,
divider cancellation/recovery, all B01-B09 cases, timing, or the course ex8 image.
It is a short real-CSR integration check, not full ex8 acceptance.

## Separate real-divider validation

The actual AMD divider IP cancellation/recovery test has now also been run.
See [result and scope](real-div-result-2026-10-29.md).
Its testbench is `tb_div_cancel.sv`; reproduce with `run_div_cancel.ps1`.
Do not compile this bench together with the smoke bench's placeholder modules.

## ex9 targeted verification

See [2026-10-30 result and scope](ex9-result-2026-10-30.md).
Run `run_ex9.ps1` for the 12 real-CPU/CSR program cases and the separate
ID/EXE/MEM control bench. These do not constitute full course ex9 acceptance.

## Branch-prediction ID verification

See [2026-10-31 result and scope](bp-id-result-2026-10-31.md).
Run `./tests/team/pipeline/run_bp_id.ps1` from the repository root in PowerShell.
Uses the real ID, register file and decoders with port stimuli only; no force or
CPU-source edits. Final result: 89 scenarios, 693 checks, 79 update edges,
53 correction edges, ending at 3170 ns. The runner validates an exact PASS marker
and input hashes. This is B's module test, not real predictor/IF integration,
course regression, performance measurement, bit generation or timing closure.

## Reproduce in PowerShell

Run from the repository root. Generated files go to a new temporary directory.
Do not compile these divider placeholders together with real divider IP models.

```powershell
$repo = (Get-Location).Path
$bin = 'D:\vivado\Vivado\2023.2\bin'
$src = Join-Path $repo 'myCPU'
$tb = Join-Path $repo 'tests/team/pipeline/tb_ex8_smoke.sv'
$files = Get-ChildItem -LiteralPath $src -Filter '*.v' |
    Where-Object { $_.Name -ne 'mycpu_head.v' } |
    ForEach-Object { $_.FullName }
$runDir = Join-Path $env:TEMP ('la32-ex8-smoke-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runDir | Out-Null
Push-Location -LiteralPath $runDir
try {
    & "$bin/xvlog.bat" --sv --include $src $files $tb
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }
    & "$bin/xelab.bat" tb_ex8_smoke -s ex8_smoke --timescale 1ns/1ps
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed' }
    & "$bin/xsim.bat" ex8_smoke -runall
    if ($LASTEXITCODE -ne 0) { throw 'xsim failed' }
    if (-not (Select-String -LiteralPath 'xsim.log' -Pattern '^EX8_SMOKE_PASS')) {
        throw 'Simulation did not report PASS; inspect xsim.log'
    }
} finally {
    Pop-Location
}
```
