<div align="center">

# LA32 Computer Organization Lab

**A five-stage pipeline CPU course project**

From a single-cycle CPU to stalls, forwarding, and instruction extensions.

![Verilog](https://img.shields.io/badge/HDL-Verilog-4B5563?style=flat-square)
![Architecture](https://img.shields.io/badge/ISA-LA32-2563EB?style=flat-square)
![Pipeline](https://img.shields.io/badge/Pipeline-5%20Stages-059669?style=flat-square)
![Vivado](https://img.shields.io/badge/Tool-Vivado-F59E0B?style=flat-square)

[简体中文](README.md) · **English**

[Experiments](#experiments) · [Repository layout](#repository-layout) · [Vivado simulation](#running-simulation-in-vivado) · [Study notes](#study-notes)

</div>

## About

This repository records my LA32 computer organization course project. Starting from the course-provided single-cycle CPU and SoC environment, the experiments introduce a five-stage pipeline, handle register dependencies, and extend the supported instruction subset.

```text
IF → ID → EXE → MEM → WB
     ↑     │     │     │
     └─────┴─────┴─────┘
       ex3: forwarding to ID
```

`main` contains the current ex7 CPU, matching ex7 test images and reference trace, and the packaged project files. Original branches and tags preserve each experiment's implementation.

## Experiments

| Experiment | Implementation | Original branch / tag | CPU commit | Validation record |
|---|---|---|---|---|
| ex1 | Five-stage pipeline, RAM enables, four byte write enables | `master` / `ex1-pass` | `c5a6bc3` | Historical local simulation passed |
| ex2 | Detect RAW dependencies in ID and stall until writeback | `ex2-stall` / `ex2-pass` | `f37267b` | Historical local simulation passed |
| ex3 | EXE/MEM/WB forwarding to ID; one-cycle load-use stall | `ex3-forwarding` / `ex3-pass` | `e3410f8` | Historical local simulation passed |
| ex4 | Add `slti`, `sltui`, `andi`, `ori`, `xori`, `sll.w`, `srl.w`, `sra.w`, `pcaddu12i` | `ex4-alu` / `ex4-pass` | `1b38683` | Historical commit records a simulation pass |
| ex5 | Add `blt`, `bge`, `bltu`, `bgeu` | `ex5-branch` | `e1f2723` | Historical log passes 33 test points, including all four new branches |
| ex6 | Add `ld.b`, `ld.bu`, `ld.h`, `ld.hu`, `st.b`, `st.h` | `ex6-memory` / `ex6-pass` | `abe2780` | Local simulation PASS; remote task `4735`, 100/100 |
| ex7 (Experiment 3) | Add `mul.w`, `mulh.w`, `mulh.wu`, `div.w`, `mod.w`, `div.wu`, `mod.wu`; multicycle division and dependency stalls | `ex7-muldiv` / `ex7-pass` | `06cc150` | Local simulation PASS; remote task `5890`, 100/100 |

The ex6 and ex7 remote builds target `xc7a200tfbg676-1` with a 50 MHz CPU clock; both received 100/100 online. The ex7 build has 0 DRC errors and 18 warnings, but its worst setup slack is −1.127 ns: **static timing is not fully met**. Online scores and static timing are recorded separately. See the [ex7 verification and build record (Chinese)](docs/verification/ex7/README.md). Bitstreams, DCPs, and caches are excluded.

## Repository layout

| Path | Contents |
|---|---|
| `myCPU/` | Pipeline stages, CPU top, ALU, register file, and decoders |
| `soc_verify/soc_bram/rtl/` | BRAM SoC, peripherals, and Xilinx IP configurations |
| `soc_verify/soc_bram/testbench/` | Simulation testbench |
| `soc_verify/soc_bram/run_vivado/` | Original project creation Tcl and constraints |
| `func/` | Assembly sources, bundled test images, and disassembly |
| `gettrace/golden_trace.txt` | Bundled reference register-write trace |
| `docs/` | Historical assessment notes and simulation log |

Generated projects, caches, waveforms, and bitstreams are excluded from Git.

## Running simulation in Vivado

### 1. Clone and choose a CPU version

```bash
git clone https://github.com/feng632/la32-computer-organization-lab.git
cd la32-computer-organization-lab
```

Use `main` for the current ex7 implementation and packaged environment. Students with the course environment can place the desired `myCPU/` version into their existing `mycpu_env/` and add the required divider IPs.

To inspect a historical CPU:

```bash
git switch ex3-forwarding
# Or inspect a fixed snapshot:
git switch --detach ex3-pass
git switch main
```

The original experiment branches contain stage snapshots; ex7 also includes divider configurations and verification records. The complete published layout is on `main`. To use ex3 within that layout:

```bash
git restore --source=ex3-pass -- myCPU
# Restore the main CPU afterwards:
git restore --source=HEAD -- myCPU
```

These commands overwrite local changes inside `myCPU/`; save your edits first.

### 2. Match the test program to the experiment

Bundled `func/obj/inst_ram.coe`, `inst_ram.mif`, and `test.s` now use the course-provided **ex7 precompiled image**, covering all 46 test points, including the seven multiply/divide tests n30–n36. `gettrace/golden_trace.txt` was regenerated with this same image.

The assembly sources and precompiled assets were saved separately. Rebuilding with the default Makefile is not guaranteed to reproduce this test set. The original Makefile's `EXP` numbers do not directly correspond to this repository's ex1–ex7 numbering. Course `for_test_obj/exN_obj` images can be used without cross-compilation.

For earlier CPUs, use the appropriate course test image and matching `golden_trace.txt`. ex1 also requires a program compatible with its dependency limitations. Changing the CPU alone can leave unsupported instructions in the test image.

### 3. Open or create a project

The local project used **Vivado 2023.2**. Some included IP configurations originate from 2019.2. If needed, use **Report IP Status → Upgrade Selected → Generate Output Products**.

The original project file is included at `soc_verify/soc_bram/run_vivado/project/loongson.xpr`. Open it, or use your existing course project, and check that the CPU sources point to the intended `myCPU/`. If legacy paths or IP status require rebuilding, follow the steps below.

To create a project from this repository, run the following in Vivado's **Tcl Console**, replacing the clone path:

```tcl
cd {D:/projects/la32-computer-organization-lab/soc_verify/soc_bram/run_vivado}
source create_project.tcl
```

The original script creates `project/loongson.xpr` for `xc7a200tfbg676-1`. Open that file through **File → Open Project** on subsequent runs. The script uses `-force`; rerunning it may overwrite the same-named project.

### 4. Check simulation settings

- ex7 requires both Divider Generator IPs, `div_signed` and `div_unsigned`. Their `.xci` files are under their respective `soc_verify/soc_bram/rtl/xilinx_ip/` directories and are referenced by the bundled project and creation script. For an existing course project, add both `.xci` files and **Generate Output Products**. They use 32-bit Radix2, integer remainder, Non Blocking, and ARESETN; automatic Signed/Unsigned latencies are 36/34 cycles. Do not substitute empty module stubs.
- Simulation top: **`tb_top`**, defined in `testbench/mycpu_tb.v`. Design top: `soc_lite_top`.
- If `sync_ram.v` is included, remove it or disable its simulation usage. It is an alternative RAM model and duplicates the Xilinx `inst_ram` and `data_ram` modules.
- Point the `inst_ram` IP's **COE File** to the intended `func/obj/inst_ram.coe`, then regenerate its Output Products.
- Match `gettrace/golden_trace.txt` to the test image. Default relative paths rely on the repository directory layout; do not move the generated project independently.
- The testbench uses `always #5 clk=~clk`: a 10 ns period, or **100 MHz**. This simulation clock differs from the 50 MHz CPU clock recorded for the independent hardware project.

### 5. Run behavioral simulation

Select **Flow Navigator → Simulation → Run Simulation → Run Behavioral Simulation**. A bitstream is not required.

Click **Run All**, or execute:

```tcl
run all
```

Allow the program to finish. A passing run ends with:

```text
Test end!
----PASS!!!
```

The full log is normally located at:

```text
soc_verify/soc_bram/run_vivado/project/loongson.sim/sim_1/behav/xsim/simulate.log
```

The current ex7 image should reach test point 46 and a final PASS. Earlier images count differently: ex5 skips n30–n36 and runs 33 tests; ex6 also skips those seven and runs 39. A PASS from an older image does not verify the newly added instructions.

For errors, failures, missing files, or a run that never finishes, check the CPU version, test image, reference trace, IP configuration, and paths. Historical PASS logs document their associated runs.

## Study notes

[Online study notes on Feishu (Chinese)](https://tcnlttaap31i.feishu.cn/wiki/EY6EwDhuzi6NIYkeJNIcsZaFnSh?from=from_copylink)

The repository also includes [Chinese ex1–ex3 assessment notes](docs/实验一_ex1-ex3验收说明.md). Their line numbers and simulation times refer to the historical versions specified in that document.

## Attribution and license

Based on the course-provided `cdp_ede_local-master/mycpu_env` environment. The SoC, testbench, and test programs include course and Loongson code; their original copyright and license notices are retained. The pipeline and subsequent CPU experiment changes are my course project implementation.

This repository uses the [BSD 3-Clause License](LICENSE). Existing third-party notices continue to apply. Course PDFs, slide decks, and the contents of Feishu notes are not uploaded with this repository.
