# ex8 在 BP_ENABLE=1 下的回归：操作清单

目的：补上"预测器接入后 ex8 镜像是否仍正确"这一项。ex8 上一次运行是 2026-10-30 15:38，
早于预测器接入（RTL 定稿 10-31 20:20），结论已过期。

## 0. 动手前必须确认的事

**只替换 `func/obj` 和 `golden_trace.txt` 是不够的。** IP 的输出产物是独立文件，
Vivado 不会因为外部 COE 变了而自动重新生成。

当前实测状态（2026-10-31 21:10）：

| 位置 | MD5 | 大小 | 镜像 |
|---|---|---|---|
| `func/obj/inst_ram.mif` | `01ae4e99e1dac874ef8fcd06c3f6c376` | 4332075 | ex8，正确 |
| `rtl/xilinx_ip/inst_ram/inst_ram.mif` | `ee63aff55fac76c4908de0b0f894dd9b` | 4397217 | **ex9，需替换** |
| `ip_user_files/mem_init_files/inst_ram.mif` | `ee63aff55fac76c4908de0b0f894dd9b` | 4397217 | **ex9，需替换** |
| `sim_1/behav/xsim/inst_ram.mif` | `ee63aff55fac76c4908de0b0f894dd9b` | 4397217 | **ex9，需替换** |

`inst_ram.xci` 里 COE 路径是 `../../../../../func/obj/inst_ram.coe`，指向仓库的 `func/obj`，
所以走第 1 步重新生成即可，不需要手工复制文件。

`golden_trace.txt` 已是 ex8 版本：87100 行，末行 `1 1c000100 0c bfaff091`，
`0x1c000100` 正是 TB 的 `END_PC`。

## 1. 重新生成 inst_ram（关键步骤）

打开工程 `soc_verify/soc_bram/run_vivado/project/loongson.xpr`。

GUI：Sources → IP Sources → 右键 `inst_ram` → **Reset Output Products**，
再右键 → **Generate Output Products**。

Tcl Console 等价操作：

```tcl
reset_target all [get_ips inst_ram]
generate_target all [get_ips inst_ram]
```

验收：重新生成后 `rtl/xilinx_ip/inst_ram/inst_ram.mif` 的修改时间应变成刚才，
大小应从 4397217 变成 **4332075** 左右（ex8 的长度）。

## 2. 打开预测器

Tcl Console：

```tcl
set_property -dict [list xsim.compile.xvlog.more_options {-d BP_ENABLE_ON}] [get_filesets sim_1]
```

或在 Settings → Simulation → 编译选项里加 `-d BP_ENABLE_ON`。

**必须在本步之后才 Launch Simulation**，否则跑的是 BP=0。

## 3. Launch Simulation → Run All

## 4. 判据（四项全中才算通过）

| 判据 | 期望 |
|---|---|
| 检测点数量 | **47 项** `Functional Test Point PASS`（出现 58 项说明还是 ex9 镜像） |
| 轨迹比对 | **0 条** `Error!!!`（该报错会直接 `$finish`，仿真当场停） |
| 结束标志 | `Test end!` + `----PASS!!!` |
| 结束时间 | `$finish` **不晚于** 1385245 ns（BP=0 基线）；明显更早说明预测生效 |

第 4 项只作辅助判断，不能单独当结论：ex8 程序的分支密度未知，
周期变化可能很小。真正的判据是前三项 + 与 `golden_trace.txt` 逐条一致。

## 5. 保存证据

把 xsim 输出保存为 `docs/verification/ex8/ex8-bp1-2026-10-31.log`，
里面必须能看到第 4 步的四项。同时记录本次 `inst_ram.mif` 的 MD5 与大小，
以便别人确认跑的是 ex8 而不是 ex9。

## 6. 可能踩的坑

| 现象 | 原因 | 处理 |
|---|---|---|
| 跑出来 58 项 | IP 没重新生成，还是 ex9 | 回第 1 步，检查 mif 大小 |
| Generate 报找不到 COE | `func/obj/inst_ram.coe` 路径或内容有问题 | 确认该文件存在且第一行是 `memory_initialization_radix` |
| `$finish` 时间与基线完全相同 | 宏没生效，跑的是 BP=0 | 检查 `xsim.compile.xvlog.more_options` 属性 |
| 出现 `Error!!!` 且停在半路 | 轨迹或镜像版本不匹配 | 先比对 mif MD5，再确认 golden_trace 是 87100 行 |

## 7. 跑完要回答的问题

1. 47 项是否全过、有没有 `Error!!!`（→ 功能是否被预测器改坏）
2. `$finish` 相对 1385245 ns 的差值与符号（→ 性能方向）
3. 本次运行的镜像 MD5 与轨迹行数（→ 证明跑的是哪套）

三项分别记录，不互相替代：功能通过不能推出时序可用，周期变化也不能反推功能正确。
