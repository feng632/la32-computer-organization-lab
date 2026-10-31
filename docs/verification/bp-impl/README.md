# 分支预测器版本的综合与实现记录

## 综合（2026-10-31 21:52，Vivado 2023.2）

命令：`synth_design -top looongson_remote_top -part xc7a200tfbg676-1 -verilog_define BP_ENABLE_ON`

`synth_1` 上的设置：
`STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS = {-verilog_define BP_ENABLE_ON}`

### 资源对比

| 指标 | 基准（ex9，BP 之前，placed） | 本版（BP=1，synthesized） | 差 |
|---|---|---|---|
| Slice LUTs | 5342 | **8313** | +2971（+56%） |
| Slice Registers | 8721 | **12760** | **+4039** |
| Block RAM Tile | 320 | 320 | 0 |
| DSP48E1 | — | 8 | — |

FF 增量拆解：表本体 64 × 60 = 3840 bit，余下约 200 为流水线寄存与 retiming。
综合日志中的 `24 Bit Registers := 64`（tag[0:63]）与 `2 Bit Registers := 64`（state[0:63]）
是预测器进网表的直接证据。

### 综合日志中值得记下的两条

1. `WARNING: [Synth 8-3936] Found unconnected internal register 'fs_to_ds_bp_r_reg' and it is trimmed from '34' to '32' bits`
   —— `fs_to_ds_bp` 的 `{hit, taken}` 两位在 ID 阶段没有被使用（ID 只用 `[31:0]` 的 next_pc 做比较），
   被综合裁掉。这是设计冗余，不是缺陷；`BP_META_WD=34` 由规格固定，本次不改。
2. `WARNING: [Timing 38-316] Clock period '1000.000' specified during out-of-context synthesis of div_signed/div_unsigned ... different from actual 20.000`
   —— 除法器 IP 的 OOC 约束是老问题，BP 之前就存在，与本版无关。

## 关键路径预判（尚未实测）

BP 之前的最差路径（WNS −2.931 ns，ex9 routed）：

```
u_id_stage/fs_pc[31]_i_5   ID 计算分支目标
  → fs_pc[17]_i_1          14.10 ns
  → inst_ram/addra[15]
  → redirect_pending_reg_repN_alias
  → ram_ena → RAMB36E1/ENARDEN
```

27 级逻辑，数据延迟 22.1 ns，其中布线 12.3 ns（55.6%）。

预测器的查表链路是 `fetch_addr → tag 比较 → target mux → bp_next_pc_r`（寄存器收口），
设计上不回灌 `fetch_addr`，**不在这条路径上**。因此预期预测器不会直接加长该路径，
但 LUT 增加 56% 会加剧布线拥塞，实际结果必须实测。

## 实现与布线（2026-10-31 22:08）

布线状态：21285 / 21285 条可布网络全部布通，0 条 routing error。

### 时序：未通过

| 指标 | BP 之前（基准） | 本版 BP=1 |
|---|---|---|
| WNS | −2.931 ns | **−8.871 ns** |
| TNS | 未记录 | **−22265.475 ns** |
| Setup 失败端点 | 未记录 | **4612 / 35551** |
| WHS | 通过 | **+0.013 ns**（0 失败） |
| THS | 通过 | 0.000 ns（0 失败） |
| WPWS | 通过 | +4.500 ns（0 失败） |
| 理论最高频率 | 43.7 MHz | **34.6 MHz** |

hold 与脉宽都过，**只有 setup 大面积不过**：35551 个端点里 4612 个违规（13%），
不是个别路径，是整片时序被拉长。

### 关键路径（本版 WNS −8.871 ns）

```
fetch_addr
  → u_branch_predictor/query_hit0        64 路 24 位 tag 全等比较
  → u_branch_predictor/bp_next_pc_r[31]_i_6 / _39 / _102 / _198(,MUXF7)
                                         64:1 × 32 位 target 选择
  → u_if_stage/bp_next_pc_r_reg[22]/D
arrival 26.145 ns   required 17.274 ns   slack −8.871
```

上一版本文档预判"查表约 3 ns、`fetch_addr` 14.1 ns 起算仍有余量"——**该预判错误**，
实测 `fetch_addr` 到锁存需约 12 ns，查表直接成为最差路径。

### 实现后资源

| 指标 | 基准 | 本版 | 差 |
|---|---|---|---|
| Slice LUTs | 5342 | 8842 | +3500 |
| Slice Registers | 8721 | 12648 | +3927 |

## 结论与待决策

1. 时序不合格，且缺口（8.9 ns）远超基准已有的缺口（2.9 ns）。
2. 按时序反推，本版在 50 MHz 下不能保证正确运行（理论上限约 34.6 MHz）。
3. 基准版本（BP=0）本身就是 −2.931，**时序没过不是预测器单独造成的**，
   但预测器把缺口扩大了约 3 倍。
4. bit 未生成。要不要在时序不达标的情况下出 bit 上线，需要单独决策。

## 待做

- 决策：接受现状 / 改 RTL 修时序 / 回退 BP=0。
- 若改 RTL，候选方向见下（需 A 或 C 分别负责）：
  - A：target 只存低位（PC[19:0]，省 12 位 mux 宽度）
  - A：表项 64 → 32（mux 少一级 MUXF8，比较树浅一级）
  - C：`bp_query_pc` 改用 `seq_pc` 而非 `fetch_addr`（查表链路提前约 5~6 ns，
    代价是 redirect 后第一次取指不查表）
- bit 生成与 SHA-256（仅在时序结论明确后）。
