# 远程 bit 构建记录（ex8 代码，2026-10-30）

本目录是 ex8 代码（含 A 的 `csr` 完整实现、B 的 ex8 流水线与异常通路）的**首次远程 bit 构建**证据。
功能验证见 `docs/verification/ex8/ex8-full-2026-10-30.log`（ex8 镜像 47/47 PASS）。

## 1. 构建配置

| 项 | 值 |
|---|---|
| 工程 | `soc_verify/soc_bram/run_vivado/project/loongson.xpr` |
| 设计顶层 | `looongson_remote_top`（**注意原名就是三个 o**，非笔误引入） |
| 仿真顶层 | `tb_top`（不变） |
| 器件 | `xc7a200tfbg676-1` |
| Vivado | v2023.2 (win64) Build 4029153 |
| 时钟约束 | `clk_50M` 20 ns（50 MHz），`clk_11M0592` 90.422 ns |
| PLL | `PRIM_IN_FREQ` 100→50，`MMCM_CLKFBOUT_MULT_F` 9→18（输出频率不变） |
| 约束文件 | 仅 `remote/loongson_remote.xdc`（254 条引脚约束）；`constraints/soc_lite_top.xdc` 已禁用（88 条本地板引脚，与远程板冲突） |
| 源文件路径 | 已从盘外 `D:/cdp_ede_remote-master/` 改为仓库内 `soc_verify/soc_bram/run_vivado/remote/` |
| IP 综合方式 | `inst_ram` / `data_ram` 的 `SYNTHESISFLOW` 由 OUT_OF_CONTEXT 改为 GLOBAL |

## 2. 构建结果

| 项 | 值 |
|---|---|
| bit 文件 | `looongson_remote_top.bit` |
| 大小 | 4,773,807 字节（4.55 MB） |
| **SHA-256** | `FEC816DCB98DAC8666510385DB405D28DC8EAE308BED98ED2A5FBD42F618C5A8` |
| 完成时刻 | 2026-10-30 10:53:58 |
| `write_bitstream` | completed successfully |
| 实现日志 ERROR | **0** |
| 布线 | 14386 个可路由网全部布通，**routing errors = 0** |
| DRC | **16 条，全部 Warning（DPOP-1 / DPOP-2），无 Critical、无 Error** |

**DRC 明细**：16 条全部是 `DPOP-1` / `DPOP-2`（各 8 条），内容为"乘法器 DSP48 输出未加流水寄存器，建议加 PREG/MREG 以提升性能"。这是性能建议，不是规则违规。ex7 同期为 18 条，本次更少。

**资源占用**：

| 资源 | 使用 | 可用 | 占比 |
|---|---|---|---|
| Slice LUTs | 5,291 | 133,800 | 3.95% |
| Slice Registers | 8,440 | 269,200 | 3.14% |
| Block RAM Tile | 320 | 365 | **87.67%** |
| DSPs | 8 | 740 | 1.08% |
| Bonded IOB | 140 | 400 | 35.00% |

## 3. 时序结果（**未通过，且比 ex7 更差**）

| 项 | ex7 历史 | 本次（ex8 代码） | 变化 |
|---|---|---|---|
| **WNS** | −1.127 ns | **−1.564 ns** | 恶化 0.437 ns |
| **TNS** | −208.302 ns | **−462.940 ns** | 恶化 254.6 ns（2.22 倍） |
| **TNS 失败端点** | 566 | **1029** | +463（+81.8%） |
| 时序总端点 | 21,557 | 23,385 | +1,828（+8.5%） |
| **WHS** | +0.019 ns | **+0.031 ns** | 略好 |
| THS | 0.000 ns | 0.000 ns | 持平 |
| 约束状态 | **not met** | **not met** | 均未通过 |

失败路径全部集中在 `cpu_clk_clk_pll` 域（WNS −1.564 / TNS −462.940 / 1029 端点 / 该域共 23221 端点）。`clk_50M` 域无 setup 路径失败（它只驱动 PLL 输入）。

## 4. 恶化的原因分析（三条，按影响排序）

**① 本次未执行 ex7 的二次时序优化**

ex7 的 `docs/verification/ex7/remote/build.tcl` 在首次 `route_design` 后有一段条件优化：

```tcl
if {slack < 0} {
    phys_opt_design -directive AggressiveExplore
    route_design -directive Explore
    # 优化后若更差，回退到未优化的 routed checkpoint
}
```

本次用 GUI 的 `launch_runs impl_1 -to_step write_bitstream`，走的是默认策略（`phys_opt_design` 默认 directive、`route_design` 默认 directive），**没有这段激进优化**。这是最可能的主因。

**② 新逻辑增加了 1828 个时序端点**

ex8 相比 ex7 增加了 CSR 模块、异常提交通路、164 位 meta 总线、序列化与排空逻辑。总端点 21,557 → 23,385（+8.5%），组合逻辑深度和布线拥塞随之上升。

**③ DSP 输出未流水**

DRC 的 16 条 `DPOP-1/2` 警告指向同一件事：`es_mul_result` 的 DSP48 输出没有额外寄存器级。这既是性能建议，也说明乘法器相关路径偏长。

## 5. 线上评测

| 项 | 值 |
|---|---|
| 结果 | **PASSED** |
| 任务 ID | **6702** |
| 状态 | Finished |
| 得分 | **100** |
| 提交时间 | 2026-10-30 10:59:25 |
| 评测页面 | `exp_8` |
| 提交文件 | `looongson_remote_top.bit`（4,773,807 B） |
| 证据来源 | **用户提供的平台截图**（`user_provided_screenshot`），未经平台接口独立查询 |

与 ex7 对照：ex7 任务 5890，得分 100，bit 5,000,107 B、SHA `9E3D44C5...`。

**线上 100 分不改变第 3 节的时序结论。** 评测平台判的是功能（bit 能跑对），不判静态时序是否收敛。

## 6. 结论与约束

| 结论 | 内容 |
|---|---|
| **功能** | 本地 RTL 仿真 ex8 镜像 47/47 PASS；线上评测 100 分（任务 6702）。**bit 本身未做逐条写回比对** |
| **时序** | **未通过**（WNS −1.564 ns / TNS −462.940 ns / 1029 失败端点），且相对 ex7 恶化；**不得声称继承 ex7 的 −1.127 ns** |
| **线上** | **PASSED**，任务 6702，得分 100，证据为用户截图 |
| **bit 可用性** | 生成成功、DRC 无 Critical、布线 0 error、线上功能通过。但时序未收敛，长时间/极限工况下存在偶发错误的理论风险 |

**按 06 文档要求，功能、线上、时序三条结论必须分开记录，不得互相替代。线上通过不等于时序通过。**

## 7. 可选改进路径（尚未执行）

若要把时序拉回 ex7 水平，两条路：

1. **重跑带优化的实现**（约 25 分钟）：对 `impl_1` 设置
   `STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE = AggressiveExplore`、
   `STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE = Explore`，再 `reset_run` + `launch_runs`
2. **改用 ex7 的 `build.tcl` 独立工程流程**：与 ex7 构建方式完全一致，便于横向对比，但需另建工程目录

本次未执行上述优化，本记录只反映默认流程的结果。

## 8. 文件清单

| 文件 | 内容 |
|---|---|
| `bit_sha256.txt` | bit 哈希、大小、构建时刻、工具与器件、线上结果 |
| `build_result.json` | 机器可读的构建与线上评测结果（字段与 ex7 的 `build_result.json` 对齐） |
| `looongson_remote_top_timing_summary_routed.rpt` | 布线后完整时序报告（674 KB，含全部失败路径） |
| `looongson_remote_top_drc_routed.rpt` | 布线后 DRC 报告（16 条 Warning） |
| `looongson_remote_top_utilization_placed.rpt` | 布局后资源利用率 |
| `looongson_remote_top_route_status.rpt` | 布线状态（0 routing error） |

**bit 文件本身未入库**：`.gitignore` 第 2 行忽略 `soc_verify/**/run_vivado/project/*`，仓库只保存哈希。
