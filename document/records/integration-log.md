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

**状态：G1 关闭**（2026-10-29 17:01，三方交付齐全，最终回归 46/46 PASS，`$finish` 1376195 ns）

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

### G1.4 回归结果（G1 判据）

| 项目 | G0 基线 | G1 集成后 |
|---|---|---|
| 测试点 | 46/46 | **46/46** |
| `$finish` | 1376195 ns | **1376195 ns** |
| `Error!!!` | 0 | **0** |
| 结束标志 | `Test end!` + `----PASS!!!` | 相同 |

完整日志：`docs/verification/ex7/g1-integrated-2026-10-29.log`

工程侧确认：`loongson.xpr` 已加入 `myCPU/csr.v`，`compile.log` 确认其参与编译，`launch_simulation` 于 13:04 重新编译、13:05 起仿真——**本次结果是包含 `csr.v` 与改后 IF/顶层的全新编译**，不是旧产物。

**G1 通过。`pipe_flush` 恒 0 时行为与 G0 逐拍一致，接口骨架未改变 ex7 功能。**

### G1.5 未完成项与遗留

| 项 | 状态 |
|---|---|
| A 的六路常量输出 | **未交付**，但本阶段不影响回归（见 G1.6） |
| C01～C03 冲刷场景 | 待 G3（需 B 的 `wb_ex`/`ertn_flush` 真正产生） |
| `tests/team/integration/` | 待建（G2 起使用） |
| `sync_ram.v` AutoDisabled、`xpr` 的 Path 噪音 | 已记录，属预期 |

### G1.6 已知隐患

A 的 `csr.v` 六路输出未驱动，接顶层后为 Z。逐条确认本阶段不影响 ex7 回归：`csr_rvalue`/`tid_value` 未被 B 的 WB 消费；`has_int` 未进入 ID 逻辑；`counter_value` 在 `cnt_op` 恒 0 时不使用；`ex_entry`/`ertn_entry` 只在 `pipe_flush` 有效时被锁存，而本阶段 `pipe_flush` 恒 0。

**A 补齐后必须重跑 G1 回归，不得直接进入 G2 验收。**

### G1.7 规范同步（main `c8a5b33`）

2026-10-29 合并 `origin/main` 的 CSR 权限勘误，merge 提交 `d8001bf`，**无冲突**（改动全在 `document/`，与集成分支的 `document/records/` 无交集）。

**结论：TEAM-ABI-1.0 的端口、位宽、字段位置不变，G1 的 RTL 与回归结论不受影响。** 勘误只涉及软件写权限，不涉及接口。

| 项 | 变更 | 负责人 | 对 C 的影响 |
|---|---|---|---|
| `BADV` | 32 位只读 → **可读写**，支持 CSRWR/CSRXCHG 掩码写；`wb_ex && wb_badv_valid` 时硬件更新优先 | A | G2 测试需覆盖 BADV 掩码写与读回（A11/A12） |
| `ECFG.LIE[12]` | 因不实现 IPI 而固定 0 → **保留读写**，软件可写掩码 `0x00001bff`；ESTAT.IS[12] 仍固定 0 | A | G5 测试需验证 LIE[12] 可读回且不触发中断（A13） |
| 新增文档 | `09-errata.md`（逐条依据与核对结论）、`csr-registers-v1.json`（机器可读权限表） | 全队 | A14 逐 CSR 权限检查的依据 |
| 新增测试 | A11～A14；A08/A09 补关闭/重配置/同拍 TICLR 边界 | A | A 执行，C 在阶段集成时核对 |

`check_documents.py` 同时升级，新增 CSR 权限回归检查。合并后运行结果：

```
PASS: documentation links/fences, ABI bit layout, fixed baseline hashes, CSR permission regression checks.
```

**需转达 A**：本次不是接口变更，但 A 的实现范围扩大两项（BADV 软件写路径、ECFG 掩码更正），且 A08/A09 的边界用例要求加严。B 的 `prep/b-g1-interface` WIP 代码不并入 main，保持原样。

### G1.8 A 的 csr 实现合入（`871e15d`）

2026-10-29 合并 `origin/csr` 的 `871e15d csr finished`，merge 提交见下。`csr.v` 由 45 行壳体扩为 185 行完整实现，**G1.6 所列"六路输出未驱动"隐患就此消除**。

**逐项核对结果**：

| 项 | 实现 | 判定 |
|---|---|---|
| 六路输出驱动 | `csr_rvalue` 用 `always @(*) case`；其余五路用 assign | ✓ |
| 掩码写通式 | `(~mask & old) \| (mask & value)` | ✓ |
| 异常提交 | PRMD←CRMD[2:0]、CRMD[2:0]←0、ERA←wb_pc、ESTAT[30:16]←{esubcode,ecode} | ✓ |
| BADV | 可读写，且 `if (wb_badv_valid)` 才硬件更新，SYS/BRK 不覆盖 | ✓ 勘误要求达成 |
| ESTAT 独立更新路径 | [9:2] 采 hw_int_in、[11] 定时器、[30:16] 异常、[1:0] 软件写，分散在不同分支 | ✓ 不会被 wb_ex 卡住 |
| TICLR | 无普通写（读 0），清 IS[11] 走独立条件，且到期置位优先 | ✓ |
| 定时器 | `_counter_expired = RUNNING && TVAL==0`；周期重装/单次停止并置 0xffffffff | ✓ 符合 04 |
| 稳定计数器 | 64 位每拍 +1，不受 wb_ex/ertn/pipe_flush 影响 | ✓ |

**发现的问题（已退回 A）**：

| 编号 | 问题 | 依据 |
|---|---|---|
| G1-ISS-6 | **`ECFG[12]` 未实现**：`14'h004: ECFG[11:0] <= ...` 只赋值低 12 位，`ECFG[12]` 恒为复位值 0，软件写不进去 | `c8a5b33` 勘误要求 LIE[12:11] 均可读写，掩码 `0x00001bff`。A13 测试必然失败 |
| G1-ISS-7 | `has_int` 用 `ESTAT[11:0] & ECFG[11:0]`，应为 `[12:0]` | 与 G1-ISS-6 同源；IS[12] 固定 0，故当前不影响功能，但需一并修正保持一致 |

**G1-ISS-6 已有实测证据**：C 编写最小复现 `tests/team/integration/csr_probe/tb_ecfg12.v`，直接驱动 `csr` 的 20 个端口，用 `xsim` 运行（日志 `probe_ecfg12_2026-10-29.log`）。结果：

```
[复位]     ECFG = 0x00000000
[写bit12]  ECFG = 0x00000000  (期望 0x00001000)
  FAIL: LIE[12] 写不进去，读回 bit12 = 0
[全1写入]  ECFG = 0x00000bff  (期望 0x00001bff)
  PASS: bit10 恒 0
  PASS: [31:13] 恒 0
  PASS: LIE[11] 可读写
[ESTAT]    = 0x00000000  (IS[12] 恒 0)  PASS
[has_int]  = 0  (CRMD.IE 复位 0)        PASS
结果：1 项 FAIL
```

全 1 写入得 `0x0bff`、期望 `0x1bff`，差值正是 `0x1000`（bit12），与静态分析结论一致。**本项退回 A 修复，C 不代改。**

### G1.9 A 修复验证（`13dcd86` + `43628b7`）

A 推送两个修复提交后，C 在合并前用两份测试交叉验证：

| 提交 | 内容 |
|---|---|
| `13dcd86` | `ECFG[12:0]` 改为拼接 `{[12:11], 1'b0, [9:0]}`，bit12 进入掩码写通路 |
| `43628b7` | `has_int` 改用 `ESTAT[12:0] & ECFG[12:0]` |

**验证一：C 的探针** `tb_ecfg12.v`（日志 `probe_ecfg12_after_fix_2026-10-29.log`）

```
[写bit12]  ECFG = 0x00001000  (期望 0x00001000)  PASS: LIE[12] 可读写
[全1写入]  ECFG = 0x00001bff  (期望 0x00001bff)  PASS: bit10 恒0 / [31:13] 恒0 / LIE[11] 可写
[ESTAT]    = 0x00000000  PASS: IS[12] 恒 0
结果：全部 PASS
```

**验证二：A 自己的测试平台** `tests/team/csr/tb_csr.sv`（日志 `a_suite_after_fix_2026-10-29.log`）

```
PASS A01 ... PASS A10
CSR_SUMMARY groups_passed=10 groups_total=10 checks=414 failures=0
CSR_TEST_PASS
```

对照 A 在 `871e15d` 上的记录（`tests/team/csr/result-2026-10-29.md`：9/10 组、`FAIL A03 ... actual=0x0bff expected=0x1bff`），缺口已闭合。

**G1-ISS-6、G1-ISS-7 关闭。**

注：A 的 `run.ps1` 在 PowerShell 5.1 上会因 `Start-Process` 的字典键冲突（`Key 'Path' being added: 'path'`）在调用工具阶段失败，与测试逻辑无关；本次由 C 按脚本原命令序列手工执行 xvlog/xelab/xsim 完成验证。该问题已告知 A，不影响其测试结论。

### G1.10 最终回归（G1 关闭判据）

在 A 的修复合入后（`csr.v` blob `5be9d27`），执行第三次 ex7 回归。本次为**重新编译**：`launch_simulation` 于 16:43 重新编译、16:48 仿真结束，非续跑、非旧产物。

| 项目 | G0 基线 | G1 初版 | G1 + A实现 | **G1 最终** |
|---|---|---|---|---|
| 测试点 | 46/46 | 46/46 | — | **46/46** |
| `$finish` | 1376195 ns | 1376195 ns | — | **1376195 ns** |
| `Error!!!` | 0 | 0 | — | **0** |
| `csr.v` 版本 | 不存在 | 45 行壳体 | 185 行（含 ECFG bug） | **185 行（修复后）** |

完整日志：`docs/verification/ex7/g1-final-2026-10-29.log`

**G1 三方交付确认**：

| 方 | 交付物 | 状态 |
|---|---|---|
| A | `csr.v` 完整实现 + `tests/team/csr/` 模块测试（10/10 组，414 检查） | ✓ |
| B | ID/EXE/MEM/WB 新端口与 meta 直通，功能关闭 | ✓ |
| C | IF 重定向缓存、顶层连线、SoC 端口、csr 例化；三次回归证据 | ✓ |

**G1 关闭。** `pipe_flush` 恒 0 时行为与 G0 逐拍一致，接口骨架未改变 ex7 功能；A 的 CSR 实现进入流水线后同样未影响 ex7 结果。

`tests/team/csr/result-2026-10-29.md` 记录的是 `871e15d` 时的结果（9/10 组，A03 失败），修复后的验证结果见 G1.9。

**静态检查**：Vivado `xvlog` 对 14 个文件重新分析，**0 ERROR / 0 WARNING**。

**待做**：ex7 回归。判据仍是 46/46 PASS 且 `$finish` 为 **1376195 ns**。理论上 `csr` 的全部输出在 ex7 场景下不进入任何有效逻辑路径（`csr_num` 恒 0 → `csr_rvalue`=CRMD=0x8 但不被 WB 消费；`has_int`=0；`cnt_op` 恒 NONE 故 `counter_value` 不被 EXE 使用），预期回归通过，但**必须实跑确认，不得以推理代替**。

---

## G2 ～ G6

**状态：G4 本地功能通过**（ex8 课程镜像 47/47 PASS），G5/G6 未开始；C01～C04 定向场景已补做（模块级激励，44/44 通过，见本文件末尾章节），C 侧短程序仍待做

### G2.1 B 的 ex8 流水线与提交逻辑合入（`470bd10` + `33e6b74`）

2026-10-30 合并 `origin/feat/exception-pipeline`，**fast-forward**（B 直接基于 G1 最终提交 `a865f81`，未产生 merge 节点）。

改动范围：`ID_stage.v` +103、`EXE_stage.v` +116、`WB_stage.v` +65、`MEM_stage.v` +5，另加 `tests/team/pipeline/` 六个测试文件。

**C 侧代码核对（合入前完成）**：

| 模块 | 关键点 | 判定 |
|---|---|---|
| WB | `wb_ex`/`ertn_flush`/`csr_we` 的产生条件与互斥；位段 `[83]/[82:77]/[76:68]/[67]/[66:35]` 与 49 位 EXC 布局逐位对齐；`badv_valid=0` 时 `wb_badv` 输出 0；`ws_allowin` 含 `!wb_ex && !ertn_flush`；`rf_we` 含 `dest≠0` | ✓ |
| ID | 五条指令译码；`serial_inflight`/`older_valid`/`ds_serial_wait`；meta 打包（`csr_num=inst[23:10]`、`wmask` WR 全 1 / XCHG 取 rj、`wvalue=rkd_value`）；`br_taken` 含 `!ds_exc[48]` | ✓ |
| EXE | `es_mem_req_ok` 五项条件与 03 第 5 节逐项一致；`data_sram_en/we` 组合屏蔽；`es_ready_go = es_exc_valid ? 1`；除法 `RESET_HOLD(2拍)→RECOVER(1拍)→RUN` | ✓ |
| 编码 | `0400180C`=csrrd $r12,0x6；`0401102D`=csrwr $r13,0x44；`0400158D`=csrxchg $r13,$r12,0x5；`002B0000`=syscall 0x0；`06483800`=ertn | ✓ 全部取自 `func/obj/test.s` 与 `ex8_obj/test.s` 真实反汇编 |

**静态检查**：11 个 Verilog 文件 `xvlog` 通过，0 ERROR / 0 WARNING。

### G2.2 合并后回归

| 测试 | 结果 | 说明 |
|---|---|---|
| **ex7 课程镜像** | 46/46 PASS，`$finish` **1376195 ns**，0 Error | 08:18 重新编译。B 将 `pipe_flush` 由常数 0 改为真实事件并加入序列化排空后，**逐拍行为仍与 G0 完全一致**，说明冲刷通路未误触发、序列化未阻塞正常指令流 |
| **B 的 ex8 smoke（C 重跑）** | `EX8_SMOKE_PASS write_checks=22 exceptions=1 returns=1 stores=1`，1240 ns | 在**合并后**代码（含 A 的 `csr.v` ECFG 修复）上重跑，与 B 的记录一致 |

B 的 smoke 为模块级集成测试：真实 IF/ID/EXE/MEM/WB + 寄存器堆 + ALU + 顶层连线 + A 的 `csr`，但**指令存储器为自建同步 ROM、除法器为占位模块**，其 README 明确声明不验证除法、不验证 B01～B09 全部、不验证课程 ex8 镜像。

### G2.3 G2 剩余工作与阻塞

| 项 | 状态 | 阻塞原因 |
|---|---|---|
| A 的 A01～A03 | ✓ | — |
| B 的 B01～B03、B09 | 部分通过（smoke 覆盖 CSR 读写旧值、部分掩码交换、rd=0、未知 CSR、ADD 立即依赖、EENTRY、SYS 编码与 ERA、ERA+4、返回、无重复事件） | 未覆盖 B09 全字段图样、B05 访存屏蔽的强制构造 |
| **C 的真实 SoC 短程序** | ✗ **未开始** | **本机无 `loongarch32r-linux-gnusf-*` 交叉工具链**，无法从 `.S` 生成 `inst_ram.coe`。课程资料包内亦无工具链 |
| 课程 ex8 完整仿真（G4） | ✗ | 缺 ex8 配对的 `golden_trace.txt`；`ex8_obj` 仅含四个镜像 + `rom.vlog` + `test.s` |

C 侧短程序的设计要点已确认（以 `confreg.v` 实测为依据）：`open_trace` 复位值为 **1**，短程序必须首先向 `0xbfafff30` 写 0 关闭 trace 比对，否则 `mycpu_tb.v` 会用 ex7 轨迹逐条比对并立即报错；程序收尾需跳到 `0x1c000100`（`END_PC`）或经 uart 输出 `0xff` 触发 `test_end`。

### G4 ex8 课程镜像完整验证（本地功能通过）

2026-10-30，课程 ex8 镜像 + 配对轨迹，47/47 测试点全部 PASS。

**输入核对**：

| 输入 | 值 | 判定 |
|---|---|---|
| `func/obj/inst_ram.coe` | `E6A1F8AA036755FB...` | 与 `baseline.json` 记录的 ex8 哈希一致 ✓ |
| `func/obj/inst_ram.mif` | 4,332,075 B | 与 ex8 一致 ✓ |
| `func/obj/test.s` | `7F9D6FD4...` | ex8 反汇编 ✓ |
| `func/obj/data_ram.coe/mif` | `8BC44E0D` / `54E1F555` | 与 ex7 相同，无需更换 ✓ |
| `gettrace/golden_trace.txt` | 87,100 行，末行 `1 1c000100 0c bfaff091` | 已替换为 ex8 配对轨迹 ✓ |
| IP 产物 | `inst_ram/inst_ram.mif` 08:38 重新生成，4,332,075 B | 与新 coe 同步 ✓ |

**执行结果**：

| 项目 | 值 |
|---|---|
| 测试点 | **47 / 47** |
| 第 47 点 | `[1384795 ns] Number 8'd47 Functional Test Point PASS!!!`，PC `0x1c00800c`（`syscall_ex` 入口） |
| 结束标志 | `Test end!` + `----PASS!!!` |
| `$finish` | **1385245 ns** |
| `Error!!!` / `Unknown` | **0** |
| 耗时 | cpu 00:01:08 / elapsed 00:03:20 |
| 完整日志 | `docs/verification/ex8/ex8-full-2026-10-30.log` |

**与 ex7 的对照**：

| 项 | ex7 | ex8 | 说明 |
|---|---|---|---|
| 测试点 | 46 | **47** | 多出 `n47_syscall_ex_test` |
| `$finish` | 1376195 ns | **1385245 ns** | +109050 ns，源于新增的 syscall 测试段 |

**这次通过意味着什么**：这是三方交付**第一次在真实课程镜像下同时被验证**——A 的 `csr` 模块（CRMD/PRMD/ESTAT/ERA/EENTRY 读写、异常提交、ERTN 恢复）、B 的流水线（CSR 译码、meta 传递、序列化排空、冲刷、访存屏蔽）、C 的顶层连线（`pipe_flush`/`redirect_pc`、IF 重定向、`csr` 例化）共同跑通了含 syscall 的完整测试序列，且逐条写回与参考轨迹一致。

**本次未覆盖（不得据 G4 结论声称通过）**：

| 项 | 状态 |
|---|---|
| C01～C04 定向冲刷场景（`ds_allowin=0` 时冲刷、连续 redirect、旧响应丢弃、EENTRY→syscall→ERA→ERTN 闭环的变量组合） | 当时未做。课程程序只走到 n47 的 syscall 路径，不主动构造这些交叉条件。**已于后续补做，见本文件"C01～C04 定向冲刷与重定向场景"章节** |
| C05～C07（ex9：ADEF、硬中断端口、全模块连接检查） | 未做，属 G5 |
| 综合 / 实现 / 静态时序 | 未做，沿用 ex7 历史 WNS −1.127 ns 结论，不得声称时序通过 |
| bit 构建与线上评测 | 未做 |

**日志取证注意**：`ex8-full-2026-10-30.log` 内含两轮仿真记录——第 548/550 行为 ex7 回归（`$finish` 1376195 ns），第 1022/1024 行为本次 ex8（`$finish` 1385245 ns）。引用时须指明轮次，避免取错时刻。

### C01～C04 定向冲刷与重定向场景（模块级激励，通过）

2026-10-30，`mycpu_top` 模块级测试，**44 项检查全部通过**（`checks=44 fails=0`，`IF_FLUSH_PASS`，`$finish` 870 ns）。

**测试手段与其边界（必须明确）**：

| 项 | 说明 |
|---|---|
| 级别 | `mycpu_top` 模块级。指令 RAM 为同步读模型（1 拍延迟），内容恒为 `addi.w $r0,$r0,0` |
| 激励 | `force` 顶层 `ds_allowin` / `wb_ex` / `ex_entry` / `br_bus` |
| 依据 | `05-validation.md` 允许"用模块测试直接注入合法状态" |
| **不得声称** | **本测试不代表课程程序会自然触发这些交叉条件**，仅为定向时序验证 |

**C01：IF 被 ID 阻塞（`ds_allowin=0`）时发生 `pipe_flush`**

| 检查点 | 结果 |
|---|---|
| 阻塞期间不发新请求、`fs_valid` 保持 | ✓ |
| 冲刷当拍 `pipe_flush` 有效、旧指令不送 ID、不发请求 | ✓ |
| 冲刷当拍 `redirect_pc` = `ex_entry` | ✓ |
| 下一拍 `fs_valid` 清 0、目标已锁存、`redirect_pc_r` = 目标 | ✓ |
| **保持 `ds_allowin=0` 时仍发出取指请求，地址即重定向目标** | ✓ **核心：跳转不因阻塞丢失** |
| 再下一拍 `fs_pc` = 目标、新指令有效且可送 ID、目标已消费 | ✓ |

**C02：分支与 WB 事件同拍；连续 redirect**

| 检查点 | 结果 |
|---|---|
| 同拍 `pipe_flush` 有效，分支被取消（`fs_to_ds_valid=0`） | ✓ |
| 组合 `redirect_pc` 取 `ex_entry` 而非 `br_target` | ✓ |
| 锁存值为 WB 事件目标（`0x1c002000`），非分支目标（`0x1c001000`） | ✓ **WB 事件优先** |
| 连续两次 redirect：第一个目标 `0x1c003000`，第二个覆盖为 `0x1c004000` | ✓ |
| 最终取指地址为第二个目标，第一个目标从未被取 | ✓ |

**C03：BRAM 旧响应在冲刷后到达**

| 检查点 | 结果 |
|---|---|
| 冲刷当拍旧响应出现在 `inst_rdata`（`0x02800000`），但 `fs_to_ds_valid=0` | ✓ |
| 下一拍 `fs_valid` 被清 0，旧响应丢弃 | ✓ |
| 重定向目标锁存；释放后向新目标发请求且 `fs_pc` 更新 | ✓ |

**C04：ERTN 冲刷通路**

主闭环（EENTRY→syscall→handler→ERTN）已由 G4 的 ex8 `n47_syscall_ex_test` 覆盖（47/47 PASS，逐条写回匹配参考轨迹）。此处补的是流水线侧那个未被课程程序单独证明的事实：**ERTN 冲刷必须重定向到 `ertn_entry`，绝不能落到 `ex_entry`**。`ertn_entry` 即 CSR 的 ERA 输出，因此喂一个非原始返回地址，等价于"在 handler 内改 ERA 后 ERTN"。

| 检查点 | 结果 |
|---|---|
| 仅 `ertn_flush` 有效时 `pipe_flush` 成立 | ✓ |
| `redirect_pc` 取 `ertn_entry`（`0x1c006000`） | ✓ |
| **同时投放的 `ex_entry`（`0x1c002222`）不生效** | ✓ **不会串到异常入口** |
| `fs_valid` 被清 0、ERTN 目标锁存 | ✓ |
| 释放后向 ERTN 目标发请求，`fs_pc` 更新、新指令有效 | ✓ |

**复现**：

```
tests/team/integration/if_flush/run_if_flush.ps1
```

脚本自行推算仓库根，编译 `myCPU/*.v`（排除 `mycpu_head.v`，经 `-i` 包含）+ `tb_if_flush.sv`，elaborate 后运行并校验 `IF_FLUSH_PASS`。除法器使用占位模块（与 `tests/team/pipeline/tb_ex8_smoke.sv` 一致），一旦被请求立即 `$fatal`，兼作护栏。

**日志**：`tests/team/integration/if_flush/if-flush-2026-10-30.log`（81 行，44 条 PASS）。

**本阶段仍缺**：C05～C07 属 G5（ADEF 需先在 IF 实现；硬中断需 A/B 的 ex9 功能）。

### 远程 bit 构建（ex8 代码，生成成功，时序未通过）

2026-10-30 10:53，`looongson_remote_top` 远程 bit 构建完成。详细记录见
`docs/verification/ex8/remote-bit-2026-10-30/build-summary.md`。

| 项 | 值 |
|---|---|
| bit | `looongson_remote_top.bit`，4,773,807 B |
| **SHA-256** | `FEC816DCB98DAC8666510385DB405D28DC8EAE308BED98ED2A5FBD42F618C5A8` |
| 实现 ERROR | **0** |
| 布线 | 14386 个可路由网全部布通，**0 routing error** |
| DRC | **16 条，全部 Warning（DPOP-1/2 DSP 流水建议），无 Critical**（ex7 为 18 条） |
| 资源 | LUT 3.95% / FF 3.14% / BRAM **87.67%** / DSP 1.08% / IOB 35.00% |

**时序（关键，未通过且比 ex7 差）**：

| 项 | ex7 | 本次 | 变化 |
|---|---|---|---|
| WNS | −1.127 ns | **−1.564 ns** | 恶化 0.437 ns |
| TNS | −208.302 ns | **−462.940 ns** | 恶化 2.22 倍 |
| 失败端点 | 566 | **1029** | +81.8% |
| WHS | +0.019 ns | +0.031 ns | 略好 |
| 约束 | not met | **not met** | 均未通过 |

**结论必须分开写**：

| 维度 | 结论 |
|---|---|
| 功能 | 本地 RTL 仿真 ex8 镜像 **47/47 PASS**；线上评测 **100 分（任务 6702）**。bit 本身未做逐条写回比对 |
| 时序 | **未通过**（WNS −1.564 / TNS −462.940 / 1029 失败端点），相对 ex7 恶化，**不得声称继承 ex7 的 −1.127 ns** |
| 线上 | **PASSED**，任务 ID **6702**，状态 Finished，得分 **100**，提交 2026-10-30 10:59:25，页面 `exp_8`，证据为用户提供的平台截图 |

**线上 100 分不等于时序通过。** 评测平台判功能（bit 跑得对），不判静态时序是否收敛。ex7 的 −1.127 ns 同样在线上得了 100，本次 −1.564 ns 更差——功能正确与工艺余量是两件独立的事，06 文档要求分栏记录即是为此。

**恶化原因（按影响排序）**：① 本次走 GUI 默认实现流程，**未执行 ex7 `build.tcl` 中的 `phys_opt_design -directive AggressiveExplore` + `route_design -directive Explore` 二次优化**；② ex8 新逻辑使时序端点 21,557→23,385（+8.5%）；③ 16 条 DPOP 警告指向乘法器 DSP 输出未加流水寄存器。

**未执行的可选改进**：对 `impl_1` 设置 `PHYS_OPT_DESIGN.ARGS.DIRECTIVE=AggressiveExplore`、`ROUTE_DESIGN.ARGS.DIRECTIVE=Explore` 后重跑（约 25 分钟），或改用 ex7 的独立 `build.tcl` 流程。

