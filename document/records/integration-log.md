# 集成分支记录 · `integration-ex8-ex9`

负责人：C（取指 / 顶层连接 / SoC 与工程 / 联合验证）
接口版本：TEAM-ABI-1.0

## 使用说明

- 每完成一个阶段（G0～G6）追加一节，**只写真实执行过的内容**。
- 状态词只有四种：`未运行` / `进行中` / `失败` / `本地通过`。
- **功能通过、时序通过、线上通过是三件独立的事**，分栏记录，互不代替。
- 失败必须留：失败 commit、最小复现程序、第一处差异（时间 / PC / 信号 / 期望 / 实际）。
- 本文件不是验收凭证。凭证是日志、报告与提交号，本文件负责把它们串起来。

---

## G0 基线固定与环境复现

**状态：本地通过**（2026-10-29，ex7 镜像 46/46 测试点 PASS）

### 3.1 基本信息

| 项目 | 值 |
|---|---|
| 阶段 | G0 |
| 日期 | 2026-10-29 |
| 分支 | `integration-ex8-ex9`（本地新建，未推送） |
| HEAD（阶段起点） | `1516744e0330645a03809148038ab4ea4ff5eeaf` |
| **G0 阶段提交** | **`0f48184`**（8 文件 +2139/-1366） |
| G0 标签 | `baseline-ex7`（附注注明本地功能通过、时序未通过、不含线上） |
| 基线提交 | `48dc551bbc685e5351a057b7a26c8115bc7ddcf6` |
| 文档提交 | `1516744`（parent 为 `48dc551`，fast-forward 合入） |
| 接口版本 | TEAM-ABI-1.0 |
| 相对基线改动 | 仅新增 `document/`（15 文件 1260 行），**RTL 零改动** |

核对方式：`git branch --show-current`、`git rev-parse HEAD`、`git status`、`git diff --stat 48dc551 HEAD`。

### 3.2 环境

| 项目 | 值 |
|---|---|
| Vivado | 2023.2，Build 4029153（2023-10-13） |
| 器件 | `xc7a200tfbg676-1` |
| CPU 工程 | `soc_verify/soc_bram/run_vivado/project/loongson.xpr` |
| 设计顶层 | `soc_lite_top` |
| 仿真顶层 | `tb_top`（`soc_verify/soc_bram/testbench/mycpu_tb.v`） |
| 仿真时钟 | `SIMU_USE_PLL=0`，`cpu_clk = clk`（tb 中 clk 周期 10ns） |

打开工程时的日志中，`[Board 49-26] cannot add Board Part ...` 数十条属 Vivado 板卡库自身问题，本工程按 part 而非 board 综合，**与结果无关**。

另有 `[ProjectBase 1-489]` 路径长度提示（工程路径约 100 字符）。当前 IP 生成产物落在 `rtl/xilinx_ip/<ip>/` 下，未超过 260 字符限制；若后续报告 "path too long"，用 `subst` 映射盘符处理。

### 3.3 IP 配置变更（本阶段唯一有意的变更）

仓库内 5 个 IP 只有 `.xci`，无生成产物，首次打开时状态如下：

| IP | 升级前 | 升级后 | 处理 |
|---|---|---|---|
| `clk_pll` | Clocking Wizard 6.0 **Rev.4**，XML/SPIRIT 格式，2019.2 定制 | 6.0 **Rev.13**，JSON 格式 | 升级 |
| `data_ram` | Block Memory Generator 8.4 **Rev.4**，XML/SPIRIT | 8.4 **Rev.7**，JSON | 升级 |
| `inst_ram` | Block Memory Generator 8.4 **Rev.4**，XML/SPIRIT | 8.4 **Rev.7**，JSON | 升级 |
| `div_signed` | Divider Generator 5.1 Rev.20，JSON，2023.2 定制 | 不变 | 无需升级 |
| `div_unsigned` | Divider Generator 5.1 Rev.20，JSON | 不变 | 无需升级 |

升级理由：三个老 IP 在 2023.2 下为 `locked` 状态，无法生成产物；且工程版本与除法器 IP 均已是 2023.2，不升级则环境自相矛盾。

**升级前后 xci 的 SHA-256（CRLF 归一化为 LF）**：

| IP | 升级前（`48dc551`） | 升级后（工作区） |
|---|---|---|
| `clk_pll` | `55CB2438B60A43A3F65D87A46515EFAB1F92FA6A4D24AEC9BE2617D9CBF56E69` | `1853FC0D226A7E2FB6302281A60D5CFD78F79EECBDBF1486B87FF68E1CA55228` |
| `data_ram` | `2FE1B0B2EFCDCF0FF82A4D45D61C4B9219F8138ABA4457C54D330BE6E39E9210` | `08B1A70D00EC4C4E48FBB67F7B4E590400FD2A8017E9E058C3BA3732F3C5770D` |
| `inst_ram` | `AFA3465D1FA54E3C868B38584E9C862CEE4635D1C6A62B80CEB137F52CDADE47` | `036FF116216B7E98894653D8D129BAD34B0A3A5CC1E7BAD28B74D5EEF2D24163` |
| `div_signed` | `305D0663BBC2890516C0734A110AA0545166DE237D58AFE828179250573B0720` | `D9D7CC2E26C2405523C6D70762D08CF205AC6FCA24855E804753895A7F0EF319` |
| `div_unsigned` | `3008EB114DE7A5BFBEB9A804EF2B2B006C1545ED29D6F25B9CF6CB46388B4403` | `DEED86CB1FBE49623C6392C8B28BD95242DDCCB9920A7CDBFE23BD0C5DBB5C50` |

**配置语义等价性核对结果**：

- `inst_ram` 的 COE 路径升级前后均为相对路径 `../../../../../func/obj/inst_ram.coe`，**未写入绝对路径**；
- `data_ram` 升级前后均为 `no_coe_file_loaded`（数据段初始为空，属原有配置，非升级导致）；
- `div_signed` / `div_unsigned` 的 xci 差异仅文件末尾 `}`（换行差异），**配置项零变化**；
- `clk_pll` / `data_ram` / `inst_ram` 的 xci 大改（1403 / 575 / 575 行）为 XML→JSON 格式转换，属升级正常结果。

**结论：功能行为是否等价，以 3.5 的 ex7 仿真结果为准。仿真未通过前，上表只证明"配置项未变"，不证明"行为未变"。**

### 3.4 输入核对

| 输入 | 值 | 判定 |
|---|---|---|
| `func/obj/inst_ram.coe` | `496A19F493B1AEBA769A35761D71BD7CCB439C3F532F7F3A24BE253C2FF1381A` | 与 `baseline.json` 一致，ex7 镜像 ✓ |
| `func/obj/data_ram.coe` | `8BC44E0D7C792DF9AADF8965F33E95A3CA0F22ABD57867712256FA2D3151CAF2` | 一致 ✓ |
| 课程 `for_test_obj/ex7_obj` 五文件 | 与 `func/obj` 逐一致（LF 归一化） | ✓ |
| `gettrace/golden_trace.txt` | 86846 行，末行 `1 1c000100 0c bfaff091` | ex7 配对轨迹 ✓ |
| `tb_top` 的 `END_PC` | `32'h1c000100` | 与轨迹末行一致 ✓ |

`mycpu_tb.v` 中 `TRACE_REF_FILE` 为相对路径 `../../../../../../../../gettrace/golden_trace.txt`，从 `loongson.sim/sim_1/behav/xsim` 上溯 8 层正好到仓库根，**工程目录结构不可挪动**。

### 3.5 仿真执行

第一次 `launch_simulation` 停在 30/46（`simulate.log` 8320 字节不再增长、`dump.vcd` 无 `$finish` 标记、进程仍存活），执行 `run all` 续跑至结束。

| 项目 | 值 |
|---|---|
| 命令 | `launch_simulation` → `run all` |
| 仿真目录 | `soc_verify/soc_bram/run_vivado/project/loongson.sim/sim_1/behav/xsim/` |
| **完整日志** | `docs/verification/ex7/ex7-local-repro-2026-10-29.log`（复制自 `project/vivado.log`） |
| 首测试点 | `[  12115 ns] Number 8'd01 Functional Test Point PASS!!!` |
| 末测试点 | `[1375745 ns] Number 8'd46 Functional Test Point PASS!!!` |
| `Error!!!` 条数 | **0** |
| 结束标志 | `Test end!` + `----PASS!!!` |
| `$finish` | **1376195 ns**（`mycpu_tb.v` Line 270） |
| 耗时 | cpu 00:02:03 / elapsed 00:04:45 |

**与 ex7 历史记录的对照**：`docs/verification/ex7/README.md` 记录的本地结果为 `$finish called at time : 1376195 ns`。本次 G0 复现的 `$finish` 时刻**同为 1376195 ns**，46 个测试点执行序列逐拍一致。

**由此得出的结论**：IP 由 2019.2 修订升级至 2023.2 修订（`clk_pll` Rev.4→13、`data_ram`/`inst_ram` Rev.4→7）**未改变任何功能行为**。3.3 中"配置项未变"的推断，至此升级为"行为等价"的实测结论。

**功能结论：`本地通过`**——ex7 课程镜像 + 配对 golden_trace，46/46 测试点全部 PASS。

**日志取证的经验（必须保留）**：`xsim/simulate.log` **不可作为证据**。续跑时 xsim 不再向该文件写 stdout，它会永久停在 30 个测试点（8320 字节），与实际运行进度脱节。完整输出只在 `project/vivado.log`（GUI Tcl Console 的记录）。下次判断"是否跑完"，只认 `$finish` 行和 `Test end!`，不认 `simulate.log` 的长度。

### 3.6 工程检查（对应清单 G0-2 / C07 雏形）

| 检查项 | 结果 |
|---|---|
| Design Sources 编译顺序 | `mycpu_head.v` 第 6 位，`IF_stage.v` 第 9 位，head 在前 ✓ |
| 仿真顶层 | `tb_top` ✓ |
| `mycpu_tb.v` 是否入工程 | 在 sim_1 源文件列表中 ✓ |
| `sync_ram.v` | 被 Vivado 标记 `AutoDisabled="1"` ✓ |
| 5 个 IP 产物 | `hdl/`、`sim/`、`synth/`、`*.vho`、`*_ooc.xdc` 均已生成，状态全 `Up-to-date` ✓ |

`sync_ram.v` 内含 `sync_ram`、`inst_ram`、`data_ram` 三个模块，其中后两个与 RAM IP 生成的模块**同名**。`tb_top` 未引用 `sync_ram`，`soc_lite_top` 需要的是 IP 版本，因此 `AutoDisabled` 是**避免重名的正确保护**，不是误伤。对应 06 文档"旧 `sync_ram.v` 不能和 RAM IP 重复作为仿真模型"。

### 3.7 历史时序风险（继承自 ex7，非本次引入）

来源：`docs/verification/ex7/README.md`。

| 指标 | 值 |
|---|---|
| WNS | **-1.127 ns** |
| TNS | **-208.302 ns** |
| 建立时间失败端点 | 566 个 |
| WHS | +0.019 ns |
| 保持时间失败端点 | 0 |
| DRC | 0 错误 / 18 警告（16 条 DSP 流水寄存器建议 + 2 条时钟缓冲连接建议） |

**这是 ex7 就存在的时序债，ex8/ex9 不得据此声称自己"时序退化"，也不得用功能通过掩盖它。** G6 做时序检查时以此表为对照基线。

**处理决定（2026-10-29，团队 C 确认）**：

本次**不修时序，只如实记录**。理由：课程验收以 ex8/ex9 功能正确性为主；修时序需要改动流水线切分或给组合路径加寄存器，会改变时序语义与既有验证结论，风险大于收益。

由此产生三条约束：

1. G6 的综合实现必须以 **WNS −1.127 ns / TNS −208.302 ns / 566 端点** 为对照基线，不得另立标准；
2. 若 G6 结果差于上述值，**差值部分属于 ex8/ex9 新引入**，不得归入"继承"；
3. 报告、标签、交付说明中，**功能与时序分栏声明**，功能 PASS 不得用于暗示时序通过。

**后续若要优化（不在本次范围）**：优先检查 164 位 meta 总线的组合穿透深度、CSR 组合读路径（`csr_rvalue` 直接组合进 WB 写回）、以及 `has_int` 从 CSR 组合进 ID 的路径——这三条是本次新增的深组合链。

### 3.8 未关闭问题

| 编号 | 问题 | 负责人 | 状态 |
|---|---|---|---|
| G0-ISS-1 | ex7 仿真停在 30/46 未跑完 | C | **已关闭**：`run all` 续跑至 1376195 ns，46/46 PASS |
| G0-ISS-2 | IP 升级后行为等价性未证明 | C | **已关闭**：`$finish` 时刻与历史记录同为 1376195 ns |
| G0-ISS-3 | 参考工程 `gettrace.xpr` 不存在于仓库与课程包，ex8/ex9 配对轨迹无法自行生成 | 课程方 | 待确认 |
| G0-ISS-4 | `$dumpvars;` 全层次 dump，单次约 447MB 并显著拖慢仿真；磁盘 C 剩 6.4G / D 剩 6.0G | C | 观察，暂不改动 |
| G0-ISS-5 | `loongson.xpr` 的 `Path` 属性被 Vivado 改写为本机绝对路径 `D:/Users/20656/...` | C | 提交时注明，属各人本地必然噪音 |

### 3.9 下一步

1. 提交 G0 产物：5 个 xci、`loongson.xpr`、`document/records/`、`docs/verification/ex7/ex7-local-repro-2026-10-29.log`；提交说明写明"IP 由 2019.2 修订升级至 2023.2 修订，ex7 46/46 PASS，`$finish` 与历史记录一致"；
2. 建立 `baseline-ex7` 标签（附注注明"本地功能通过，时序未通过（继承）"），**不推送**；
3. 阻塞项：A 的 `csr.v` 仍缺六路常量输出（截至 `8068839`，`assign`/`always` 计数为 0），需 A 补齐后方可交付 G1；
4. 进入 G1。

---

## G1 接口骨架

**状态：进行中**（RTL 已改完并通过静态检查，待 Vivado elaborate 与 ex7 回归）

### G1.1 合并 A / B 骨架

| 提交 | 内容 |
|---|---|
| `c0ae694` | 合并 `origin/prep/b-g1-interface`（`80b2ca8`）：ID/EXE/MEM/WB/mycpu_head 新增端口与 meta 直通，5 文件 +146/-7 |
| `8377221` | 合并 `origin/csr`（`8068839`）：新增 `myCPU/csr.v`，45 行（仅端口与寄存器声明） |

两次合并均无冲突。

### G1.2 本轮改动（C 负责的三处）

| 文件 | 改动 |
|---|---|
| `myCPU/IF_stage.v` | 新增 `pipe_flush`、`redirect_pc[31:0]`、`fs_to_ds_ex[48:0]` 端口；新增重定向缓存 `redirect_pending`/`redirect_pc_r`；`fetch_req = to_fs_valid && fs_allowin && !pipe_flush` 控制请求发出；`fs_valid` 改为仅在 `fetch_req` 的下一拍置 1；`fs_to_ds_valid` 增加 `!pipe_flush` |
| `myCPU/mycpu_top.v` | 新增顶层端口 `hw_int_in[7:0]`；例化 `csr`（20 端口）；组合产生 `pipe_flush = wb_ex \|\| ertn_flush`、`redirect_pc = wb_ex ? ex_entry : ertn_entry`；`pipe_flush` 送 IF/ID/EXE/MEM（不送 WB）；接齐 49/164 位元数据链路与 7 个 ctrl 信号 |
| `soc_verify/soc_bram/rtl/soc_lite_top.v` | `mycpu_top` 例化处补 `.hw_int_in(8'b0)`，显式接 0 不悬空 |

设计依据与逐拍推演见 C 本地笔记（不进版本库）。

### G1.3 静态检查结果

**端口完整性核对**（脚本比对模块定义与例化连接）：

| 模块 | 声明端口 | 实际连接 | 缺失 | 多余 |
|---|---:|---:|---|---|
| `IF_stage` | 14 | 14 | 无 | 无 |
| `ID_stage` | 23 | 23 | 无 | 无 |
| `EXE_stage` | 20 | 20 | 无 | 无 |
| `MEM_stage` | 16 | 16 | 无 | 无 |
| `WB_stage` | 27 | 27 | 无 | 无 |
| `csr` | 20 | 20 | 无 | 无 |

**Vivado `xvlog` 语法分析**：14 个 Verilog 文件全部通过，**0 ERROR、0 WARNING**。

**`xelab mycpu_top`**：仅报两个 `div_signed` / `div_unsigned` 模块未找到——两个除法器 IP 为 VHDL 模型，命令行环境未编译，在 Vivado 工程内由 IP 提供。**除此外无任何错误或位宽警告。**

**结论：Verilog 侧连接与位宽合法；完整的模块解析需在 Vivado 工程内 elaborate 确认。**

### G1.4 未完成项

| 项 | 状态 |
|---|---|
| `csr.v` 加入 `loongson.xpr` Design Sources | 待做（Vivado GUI） |
| Vivado Reload 后 elaborate | 待做 |
| ex7 回归，`$finish` 应仍为 1376195 ns | 待做 |
| A 的六路常量输出 | 未交付 |

### G1.5 已知隐患

A 的 `csr.v` 六路输出未驱动，接顶层后为 Z。逐条确认本阶段不影响 ex7 回归：`csr_rvalue`/`tid_value` 未被 B 的 WB 消费；`has_int` 未进入 ID 逻辑；`counter_value` 在 `cnt_op` 恒 0 时不使用；`ex_entry`/`ertn_entry` 只在 `pipe_flush` 有效时被锁存，而本阶段 `pipe_flush` 恒 0。**A 补齐后必须重跑 G1 回归。**

判据：`pipe_flush` 恒 0 时 ex7 结果与 G0 逐拍一致。

---

## G2 ～ G6

**状态：未开始**

按 `document/05-validation.md` 的里程碑推进，每阶段完成时在本文件追加一节。
