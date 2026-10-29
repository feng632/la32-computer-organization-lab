# Real divider cancellation/recovery result

Date: 2026-10-29 (Asia/Shanghai). Vivado/xsim 2023.2.
CPU base: `470bd1009e4a9ced0364695fd68f3a849d4fc794`; no CPU edits during this test.
Result: **local module test PASS**, not complete course ex8 acceptance.
Both the initial manual command sequence and a second fresh run through the
checked-in `run_div_cancel.ps1` reproduced this result. Saved logs are from the
second run, which ended at 22:00:07 local time.

```
REAL_DIV_CANCEL_PASS checks=26 signed_requests=6 unsigned_requests=5
$finish called at time : 7410 ns
```

## Real components

- Actual `EXE_stage.v` and `alu.v` from the B feature branch.
- Actual AMD Divider Generator 5.1 revision 20 simulation models generated with
  Vivado 2023.2 from copies of the repository's two `.xci` files.
- Existing Radix2, 32-bit, NonBlocking, ARESETN-enabled configurations retained;
  automatic signed/unsigned latency is 36/34 cycles.
- Generated VHDL wrappers compiled with xvhdl, linked against Vivado's actual
  `div_gen_v5_1_20` library. No behavioral replacement divider is used.
- Module-level stimuli drive the ID input packet, MEM allowin, older-exception
  signal and flush directly. This deliberately constructs exceptional overlaps;
  it does not claim that normal serialized syscall execution naturally creates them.

## Executed scenarios

1. Signed quotient -100/7=-14 and remainder -2.
2. Unsigned quotient 0xfffffff0/16=0x0fffffff and remainder 0xfffffff3%16=3.
3. B07: real signed task accepted, flush before completion, queue unsigned task;
   new result 1000/7=142, no duplicate request or stale result over 45 quiet cycles.
4. Reverse direction: cancel accepted unsigned task, then signed remainder
   -101%9=-2; observe beyond the old maximum latency.
5. B08: repeated flush in RESET_HOLD and another flush in RECOVER, then fresh
   unsigned remainder 1001%9=2.
6. Ordinary ALU operation 20+22=42 progresses during divider recovery.
7. B06 subset: completed quotient held for three cycles with MEM blocked; flush
   still clears EXE valid/sent/done and suppresses outgoing transfer.
   The other cases also flush while real division is still waiting.
8. Already-exception-marked division does not request IP, does not wait for a
   result, and transports its exception metadata.
9. B05 module stimulus: older MEM exception blocks a younger store before WB flush.

Continuous assertions check low reset spans at least two sampled rising edges,
one complete recovery cycle before a new request, no request outside RUN,
immediate flush suppression, and no memory side effects under exception/flush.
Simulation timeout: 50us. `checks=26` counts task checkpoints, not 26 independent
course test cases or completion of the whole B01-B09 matrix.

## Reproduce

From the repository root in PowerShell:

```powershell
& ./tests/team/pipeline/run_div_cancel.ps1 -VivadoBin 'D:/vivado/Vivado/2023.2/bin'
```

Each run copies XCI inputs and generates/compiles in a fresh temporary folder;
it does not change CPU sources, the checked-in XCI, or the shared Vivado project.
The script checks both tool exit codes and the final PASS marker.

Evidence: `real-div-cancel-2026-10-29.log` and
`real-div-elaborate-2026-10-29.log`. Elaboration reported two VRFC 10-9145
library/entity-name warnings in AMD-generated wrappers (one per divider),
and zero errors. IP generation reported moved-copy output-location warnings,
as expected for copying XCI files to a temporary directory.

Still outside this result: full ID/MEM/WB stress coverage, all 164-bit transport
patterns (B09), complete course ex8 image, online evaluation, synthesis/timing.
