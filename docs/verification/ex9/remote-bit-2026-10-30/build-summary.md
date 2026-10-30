# 远程 bit 构建记录（ex9 代码，2026-10-30）

本目录是 ex9 代码的远程 bit 构建与线上评测证据。功能验证见
`docs/verification/ex9/ex9-full-2026-10-30.log`（ex9 镜像 58/58 PASS）。

## 1. 构建配置

| 项 | 值 |
|---|---|
| 源码 | 提交 `df191a9`（含 A 的 csr、B 的 ex9 异常与中断、C 的 ADEF） |
| 设计顶层 | `looongson_remote_top` |
| 器件 | `xc7a200tfbg676-1` |
| Vivado | v2023.2 (win64) Build 4029153 |
| 时钟 | `clk_50M` 20 ns；`cpu_clk_clk_pll` 20 ns；`timer_clk_clk_pll` 10 ns |
| 约束 | 仅 `remote/loongson_remote.xdc`（本地板 xdc 已禁用） |
| 镜像 | ex9（`inst_ram.coe` = `BEA7A2C0...`，IP 已重新生成） |
| **实现 directive** | **默认（未使用 `-directive`）** |

**注意**：本次未带优化。原计划设置 `PHYS_OPT_DESIGN.ARGS.DIRECTIVE=AggressiveExplore`
与 `ROUTE_DESIGN.ARGS.DIRECTIVE=Explore`，但命令顺序有误（`reset_run` 放在
`set_property` 之前，属性被重置清掉），实际按默认策略执行。`runme.log` 中
`phys_opt_design` / `route_design` 均无 `-directive` 参数可证。

## 2. 构建结果

| 项 | 值 |
|---|---|
| bit 文件 | `looongson_remote_top.bit` |
| 大小 | **4,961,995 字节**（ex8 为 4,773,807） |
| **SHA-256** | **`D6DD7FD1215C4E3C6CB03552C5520D96C2B202DCE910E0C7B914BBB5DADFDA03`** |
| 完成时刻 | 2026-10-30 23:53:23 |
| 实现 ERROR | **0** |
| 布线 | **0 routing error** |
| DRC | **16 条，全部 Warning（DPOP-1/2）**，无 Critical |

**资源占用**：

| 资源 | ex9 | ex8 | 变化 |
|---|---|---|---|
| Slice LUTs | 5,342 (3.99%) | 5,291 (3.95%) | +51 |
| Slice Registers | 8,721 (3.24%) | 8,440 (3.14%) | +281 |
| Block RAM Tile | 320 (87.67%) | 320 (87.67%) | 0 |
| DSPs | 8 (1.08%) | 8 (1.08%) | 0 |
| Bonded IOB | 140 (35.00%) | 140 (35.00%) | 0 |

## 3. 时序结果（**未通过，三代最差**）

| 项 | ex7 | ex8 | **ex9** |
|---|---|---|---|
| **WNS** | −1.127 ns | −1.564 ns | **−2.931 ns** |
| **TNS** | −208.302 ns | −462.940 ns | **−1472.562 ns** |
| **失败端点** | 566 | 1029 | **2080** |
| 时序总端点 | 21,557 | 23,385 | 24,043 |
| WHS | +0.019 ns | +0.031 ns | +0.019 ns |
| 约束 | not met | not met | **not met** |

**按时钟域**：

| 时钟域 | 周期 | WNS | 失败/总数 |
|---|---|---|---|
| `cpu_clk_clk_pll` | 20.000 ns（50 MHz） | **−2.931** | **2080 / 23879** |
| `timer_clk_clk_pll` | 10.000 ns（100 MHz） | +5.031 | 0 / 66 |

失败全部集中在 CPU 时钟域。`timer_clk` 虽为 100 MHz（周期 10 ns）反而余量充足，说明
瓶颈不是时钟更快的那条路径，而是 CPU 域内的长组合路径。

## 4. 恶化原因（数据支持的三条）

**① 端点只增 2.8%，WNS 却恶化 87%**

23,385 → 24,043（+658）对应 WNS −1.564 → −2.931（差 1.367 ns）。这不是"逻辑变多导致整体变慢"，
而是**出现了新的长关键路径**。最可能的候选：

- `ID_stage` 的五级异常优先级链 `has_int > fs_to_ds_ex_r[48] > inst_ine > inst_syscall > inst_break`，
  每级都是一个 49 位 mux，串起来后组合深度明显增加
- `csr` 的中断通路：`ESTAT[9:2]` 采样 + `ECST & ECFG` 的 13 位与或 + `CRMD[2]` 与门，其输出
  `has_int` 直接进 ID 的优先级链顶端，形成跨模块长路径
- `EXE` 的 `es_ale` → `es_exc` → `es_mem_req_ok` 的组合串联（用于屏蔽访存请求）

**② 未使用实现优化 directive**

ex7 的 `build.tcl` 在首次布线后执行了 `phys_opt_design -directive AggressiveExplore` +
`route_design -directive Explore`，本次按默认策略。ex7 能达到 −1.127 有这部分功劳。

**③ 16 条 DPOP 警告未处理**

全部指向乘法器 DSP48 输出未加流水寄存器（`es_mul_result`），说明该路径本身偏长。

## 5. 线上评测

| 项 | 值 |
|---|---|
| 结果 | **PASSED**，两次提交均为 100 分 |
| 任务 ID | **6785**（与 6784 使用同一 bitstream） |
| 状态 / 得分 | Finished / **100** |
| 评测页面 | `exp_9` |
| 证据来源 | 用户提供的平台截图 |

**平台时间戳说明**：该平台记录的时间比本地时间慢约 3 分钟（任务 6785 记录 23:58:40，
用户实际点击为 00:01 左右）。因此**不能用平台时间戳反推本地构建时序**——本次记录最初
据此误判"上传了旧 bit"，实际两次提交都在 bit 生成（23:53:23）之后，用的是同一个
`d6dd7fd1` 版本。后续引用平台时间时须注明此偏差。

## 6. 结论与约束

| 维度 | 结论 |
|---|---|
| **功能** | 本地 RTL 仿真 ex9 镜像 **58/58 PASS**；线上评测 **100 分（任务 6785）** |
| **时序** | **未通过**，WNS −2.931 ns，比 ex7/ex8 都差；**不得沿用 ex8 的 −1.564 ns 结论** |
| **线上** | **PASSED**，两次 100 分，同一 bitstream |
| **bit 可用性** | 生成成功、DRC 无 Critical、布线 0 error、线上功能两次通过。但时序余量比前两代都小 |

**线上通过不等于时序通过**：平台只判功能，不判静态时序。−2.931 ns 意味着最差路径需要
22.931 ns 而周期只有 20 ns（差 14.7%），长时间运行或温度/电压偏移下存在偶发错误的理论风险。

## 7. 优化尝试记录（已执行，失败）

在本节记录一次**失败**的优化尝试，供后续参考，避免重复走同一条路。

**尝试内容**（按正确顺序，已确认 directive 生效）：

```tcl
reset_run impl_1
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]
launch_runs impl_1 -to_step write_bitstream -jobs 4
```

**结果：`phys_opt_design` 阶段 Vivado 崩溃**

```
Abnormal program termination (EXCEPTION_ACCESS_VIOLATION)
```

这是工具自身的内存访问违例，非设计错误、非命令错误。

**更有价值的证据在崩溃前的日志**：

```
[Physopt 32-702] Processed net soc_lite/cpu/u_id_stage/fs_pc[31]_i_60_n_0. Optimizations did not improve timing on the net.
[Physopt 32-702] Processed net soc_lite/cpu/u_id_stage/rj_value[25]. Optimizations did not improve timing on the net.
（同类消息重复上百次，随后触发消息抑制）
Caught ... exception.
Abnormal program termination
```

`AggressiveExplore` 反复尝试优化 `ID` 级的两类路径——`fs_pc[31]_i_*`（PC 相关比较，即分支/跳转判断）与 `rj_value[*]`（寄存器读数据）——**每次都返回"优化没有改善时序"**，最终崩溃。

**结论**：时序瓶颈在 **RTL 组合逻辑深度**，不在布局布线质量。换 directive 只是让工具更努力地寻找一个不存在的解，收效为零。

**处置**：放弃实现层优化，回退使用默认策略构建的 bit（`d6dd7fd1`，已过线上两次 100 分）。`reset_run` 期间被删除的 bit 已从备份恢复。

**后续可行的方向（未执行，属 RTL 层，需 B 参与）**：

| 对象 | 问题 | 思路 |
|---|---|---|
| `ID_stage` 五级异常优先级链 | `has_int > ADEF > INE > SYS > BRK`，每级是 **49 位** mux 串联，组合深度叠加 | 改为**分字段选择后拼一次总线**：`ecode`(6) 5 选 1、`esubcode`(9) 5 选 1、`badv_valid`(1) 2 选 1、`badv`(32) 2 选 1。其中 `badv` 仅 ADEF/ALE 会填，其余为 0，可大幅简化 |
| `csr` 的 `has_int` | `\|(ESTAT[12:0] & ECFG[12:0])` 的 13 位与或，输出直连 ID 优先级链顶端，形成跨模块长路径 | 可考虑在 CSR 侧打拍输出，但会改变中断响应时序，需同步改 ID 的采样条件 |
| `EXE` 的 `ale → exc → mem_req_ok` | 三级组合串联（用于屏蔽访存请求） | `mem_req_ok` 的基础条件可与 `ale` 并行计算，最后只需一次与门 |

**这些改动均属 B 的模块范围，且需要重跑 ex7/ex8/ex9 三套镜像回归，验收前执行风险大于收益。**


## 8. 文件清单

| 文件 | 内容 |
|---|---|
| `bit_sha256.txt` | bit 哈希、大小、构建时刻、directive、线上结果、时序摘要 |
| `looongson_remote_top_timing_summary_routed.rpt` | 布线后完整时序报告（672 KB） |
| `looongson_remote_top_drc_routed.rpt` | DRC 报告（16 条 Warning） |
| `looongson_remote_top_utilization_placed.rpt` | 布局后资源利用率 |
| `looongson_remote_top_route_status.rpt` | 布线状态（0 routing error） |

**bit 文件本身未入库**：`.gitignore` 忽略 `soc_verify/**/run_vivado/project/*`，仓库只保存哈希。
