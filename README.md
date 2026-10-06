<div align="center">

# LA32 Computer Organization Lab

**LA32 计算机组成原理课程设计实验**

从单周期 CPU 到五级流水线，逐步实现阻塞、前递与指令扩展。

![Verilog](https://img.shields.io/badge/HDL-Verilog-4B5563?style=flat-square)
![Architecture](https://img.shields.io/badge/ISA-LA32-2563EB?style=flat-square)
![Pipeline](https://img.shields.io/badge/Pipeline-5%20Stages-059669?style=flat-square)
![Vivado](https://img.shields.io/badge/Tool-Vivado-F59E0B?style=flat-square)

**简体中文** · [English](README.en.md)

[实验进度](#实验进度) · [工程结构](#工程结构) · [Vivado 仿真](#用-vivado-运行仿真) · [复习笔记](#复习笔记)

</div>

## 项目介绍

这是我的 LA32 计算机组成原理课程设计实验记录。以课程提供的单周期 CPU 和 SoC 验证环境为基础，将 CPU 改为五级流水线，并逐步处理寄存器数据相关、扩展指令。

```text
IF 取指 → ID 译码 → EXE 执行 → MEM 访存 → WB 写回
                ↑       │          │         │
                └───────┴──────────┴─────────┘
                      ex3：结果前递到 ID
```

`main` 保存目前的 ex5 CPU 和公开整理后的工程文件。各实验原始分支和标签保留阶段性代码，便于对照学习。本项目实现的是课程要求的指令子集。

## 实验进度

| 实验 | 主要内容 | 原始分支 / 标签 | CPU 提交 | 验证记录 |
|---|---|---|---|---|
| ex1 | 单周期改为五级流水线；增加 RAM 片选和 4 位字节写使能 | `master` / `ex1-pass` | `c5a6bc3` | 历史本地仿真通过 |
| ex2 | ID 检测与 EXE、MEM、WB 的 RAW 相关，阻塞等待写回 | `ex2-stall` / `ex2-pass` | `f37267b` | 历史本地仿真通过 |
| ex3 | EXE、MEM、WB 向 ID 前递；load-use 相关阻塞一拍 | `ex3-forwarding` / `ex3-pass` | `e3410f8` | 历史本地仿真通过 |
| ex4 | 添加 `slti`、`sltui`、`andi`、`ori`、`xori`、`sll.w`、`srl.w`、`sra.w`、`pcaddu12i` | `ex4-alu` / `ex4-pass` | `1b38683` | 历史提交记录仿真通过 |
| ex5 | 添加 `blt`、`bge`、`bltu`、`bgeu` | `ex5-branch` | `e1f2723` | 历史日志中 33 项测试通过，包含四条新增分支 |

ex3 的独立远程评测工程曾成功生成 bitstream，目标器件为 `xc7a200tfbg676-1`、硬件 CPU 时钟为 50 MHz，DRC 和时序检查通过。**生成 bitstream 不等于线上评测通过，线上结果尚未确认。**

## 工程结构

```text
myCPU/                         CPU 源码
├── mycpu_top.v                五级流水线顶层
├── mycpu_head.v               总线宽度定义
├── IF_stage.v                 取指、PC 和分支处理
├── ID_stage.v                 译码、相关检测、前递、分支判断
├── EXE_stage.v                ALU 运算与 RAM 请求
├── MEM_stage.v                选择访存数据或 ALU 结果
├── WB_stage.v                 寄存器写回与调试输出
├── alu.v                      算术逻辑单元
├── regfile.v                  寄存器堆
└── tools.v                    译码器
soc_verify/soc_bram/           BRAM SoC 验证环境
├── rtl/                       SoC、外设及 Xilinx IP 配置
├── testbench/                 仿真测试平台
└── run_vivado/                建工程 Tcl 和约束
func/                         汇编测试源码、预编译镜像和反汇编
gettrace/golden_trace.txt      随工程保存的参考写回记录
docs/                         阶段验收说明和历史日志
```

仿真生成的 `project/`、缓存、波形和 bitstream 不提交到仓库。

## 用 Vivado 运行仿真

### 1. 获取代码并选择实验

```bash
git clone https://github.com/feng632/la32-computer-organization-lab.git
cd la32-computer-organization-lab
```

直接使用 `main` 可以取得当前 ex5 实现和随仓库提供的验证环境。

已有课程环境的同学，可以将本仓库对应版本的 `myCPU/` 放进自己的 `mycpu_env/`，继续使用课程提供的 SoC 和测试程序。

查看某个阶段的 CPU：

```bash
git switch ex3-forwarding
# 或查看固定的历史版本：
git switch --detach ex3-pass
# 回到公开整理的完整目录：
git switch main
```

**原始实验分支主要保存 CPU 源码，完整公开目录位于 `main`。** 如果需要在 `main` 的验证环境中使用 ex3 CPU，可执行：

```bash
git restore --source=ex3-pass -- myCPU
```

这会替换当前 CPU 文件并产生工作区修改。完成对照后，恢复 `main` 的 CPU：

```bash
git restore --source=HEAD -- myCPU
```

以上恢复命令会覆盖 `myCPU/` 的本地修改，执行前请保存自己的修改。

### 2. 准备匹配的测试程序

仓库随附的 `func/obj/inst_ram.coe`、`inst_ram.mif` 和 `test.s` 是已有的预编译测试文件。反汇编入口依次调用基础 20 项、ex4 的 9 项和 ex5 的 4 项测试，共 33 项。

测试镜像与当前汇编源码是分别保存的；直接用默认 `make` 重编译，不保证生成同一套 33 项测试。`func/Makefile` 中的 `EXP` 是原始课程测试配置编号，不应直接当作这里的 ex1～ex5 编号。

运行早期 CPU 时，请使用课程提供的对应实验镜像和匹配的 `golden_trace.txt`。ex1 还需要符合其数据相关限制的测试程序。**只切 CPU 版本而不换测试程序，可能执行尚未实现的指令，导致失败。**

### 3. 打开或创建 Vivado 工程

本地原工程使用 Vivado **2023.2**；仓库中的部分 IP 配置来自 2019.2。不同版本可能需要通过 **Report IP Status → Upgrade Selected → Generate Output Products** 升级或重新生成 IP。

仓库保留了原工程文件，可直接打开 `soc_verify/soc_bram/run_vivado/project/loongson.xpr`。如果已有课程工程，也可以打开自己的 `loongson.xpr`。确认 Sources 中的 CPU 指向你要测试的 `myCPU/`；若旧工程的路径或 IP 状态不适用，可按下面步骤重新创建。

如果从本仓库创建工程，在 Vivado 的 **Tcl Console** 中执行（替换成自己的克隆路径，使用正斜杠）：

```tcl
cd {D:/projects/la32-computer-organization-lab/soc_verify/soc_bram/run_vivado}
source create_project.tcl
```

原始脚本会在该目录下创建 `project/loongson.xpr`，目标器件为 `xc7a200tfbg676-1`。重新使用时可从 **File → Open Project** 打开它。

脚本包含 `-force`，重复运行可能覆盖同名项目；后续优先打开已有 `.xpr`。

### 4. 检查仿真设置

- Simulation Sources 的顶层为 **`tb_top`**，来自 `testbench/mycpu_tb.v`；Design Sources 的顶层为 `soc_lite_top`。
- 如果脚本把 `sync_ram.v` 也加入了 Vivado 仿真源，请移除它或禁用其仿真用途。它是另一种 RAM 模型，会与 Xilinx 的 `inst_ram`、`data_ram` IP 重复定义模块。
- 确认 `inst_ram` IP 的 **COE File** 指向当前测试的 `func/obj/inst_ram.coe`，并重新生成 Output Products。
- 确认测试平台读取的 `gettrace/golden_trace.txt` 与测试镜像匹配。默认相对路径依赖仓库的目录层级，避免单独移动生成的项目文件夹。
- `mycpu_tb.v` 的时钟为 `always #5 clk=~clk`，周期 10 ns，仿真频率为 **100 MHz**。这是仿真配置，与远程工程的 50 MHz 硬件 CPU 时钟分别记录。

### 5. 运行并查看结果

点击 **Flow Navigator → Simulation → Run Simulation → Run Behavioral Simulation**。行为仿真不需要先生成 bitstream。

进入仿真界面后点击 **Run All**，或在 Tcl Console 执行：

```tcl
run all
```

不要只观察默认运行的短时间窗口；程序需要执行完才有最终结果。正常通过时，控制台末尾包含：

```text
Test end!
----PASS!!!
```

完整日志通常位于：

```text
soc_verify/soc_bram/run_vivado/project/loongson.sim/sim_1/behav/xsim/simulate.log
```

测试点编号是实际执行顺序。当前 33 项镜像中的第 30～33 项依次对应 `blt`、`bge`、`bltu`、`bgeu`，不是汇编文件名中的 n37～n40。

出现 `Error`、`Fail`、找不到文件或一直没有 `Test end!` 时，先核对 CPU 版本、测试镜像、参考 trace、IP 和文件路径。历史 PASS 日志仅代表其对应运行记录。

## 复习笔记

[飞书在线复习笔记](https://tcnlttaap31i.feishu.cn/wiki/EY6EwDhuzi6NIYkeJNIcsZaFnSh?from=from_copylink)

仓库同时保存 [ex1～ex3 验收说明](docs/实验一_ex1-ex3验收说明.md)，其中的代码行号和仿真时间对应文中注明的历史版本。

## 来源与许可

本项目基于课程提供的 `cdp_ede_local-master/mycpu_env` 实验环境。SoC、测试平台和测试程序包含原始课程与龙芯代码，保留其版权和许可声明；CPU 流水线及后续实验修改为个人课程设计实现。

本仓库采用 [BSD 3-Clause License](LICENSE)。第三方文件已有的版权与许可声明继续适用。课程 PDF、PPT 和飞书笔记正文不随代码仓库上传。
