# TEAM-ABI-1.0 严格接口规范

> 2026-10-31 拓展说明：本页继续保存 ex8/ex9 的原接口。分支预测采用独立的 [TEAM-BP-1.0 规格](10-branch-prediction.md) 和 [机器副本](branch-prediction-v1.json)。原总线位宽、49/164 位布局不变，但拓展后的 `br_bus` 高位代表 **ID 预测失败纠正**，低 32 位代表正确下一地址；不能再解释为原始实际跳转。新增 34 位 IF→ID 预测信息、68 位 ID→预测器更新总线。实施拓展时同时阅读这份规格；旧 `interface-v1.json` 不含新增接口。此拓展尚未实现或验证，A/C 接收确认待记录。

本文定义**待实现接口**；基线 RTL 没有这些新增端口。以下名称、方向、位宽和时序必须保持一致。所有标量为 1 位，高电平有效；`clk` 上升沿，内部 `reset` 同步高有效。顶层保留原 `resetn` 转换方式。

## 1. CSR 模块 `csr`（A 实现，C 在顶层例化）

除时钟复位外，无握手、无读等待。

| 端口名 | 相对 csr 方向 | 位宽 | 驱动者/用途 |
|---|---|---:|---|
| clk / reset | input | 1 / 1 | 顶层 |
| csr_num | input | 14 | WB，当前读取/写入编号 |
| csr_we | input | 1 | WB，合格的普通 CSR 写提交 |
| csr_wmask / csr_wvalue | input | 32 / 32 | WB，位掩码/原通用寄存器 rd 的值 |
| csr_rvalue | output | 32 | 组合读，未识别 CSR 读零 |
| wb_ex | input | 1 | WB，本周期异常提交 |
| wb_ecode / wb_esubcode | input | 6 / 9 | WB，异常编码 |
| wb_pc | input | 32 | WB，异常指令 PC，不是 PC+4 |
| wb_badv_valid / wb_badv | input | 1 / 32 | WB，错误地址有效/错误地址 |
| ertn_flush | input | 1 | WB，合格的异常返回提交 |
| hw_int_in | input | 8 | 顶层外部输入，ex8 固定 0 |
| ex_entry / ertn_entry | output | 32 / 32 | 组合输出 EENTRY / ERA |
| has_int | output | 1 | 中断状态与使能的组合判断，ex8 固定 0 |
| counter_value | output | 64 | 稳定计数器，ex8 固定 0 |
| tid_value | output | 32 | TID，ex8 固定 0 |

WB 在提交前组合读取旧 CSR，提交上升沿才改变状态。`csr_we` 必须已经满足 `ws_valid && !reset && !wb_ex && !ertn_flush`，且操作为 WR/XCHG。异常事件与返回应互斥；防御优先级见 03。不增加第二套隐含编号或第二读口。

## 2. WB 事件与全局控制（B 产生，C 连接）

WB 新增输入：`csr_rvalue[31:0]`、`tid_value[31:0]`。

WB 新增输出：上述 CSR 输入中除 clk/reset/hw_int_in 外的全部输入端口，即 `csr_num`、`csr_we`、`csr_wmask`、`csr_wvalue`、`wb_ex`、`wb_ecode`、`wb_esubcode`、`wb_pc`、`wb_badv_valid`、`wb_badv`、`ertn_flush`。

顶层组合产生，所有级使用同一事件：

```verilog
pipe_flush = wb_ex || ertn_flush;
redirect_pc = wb_ex ? ex_entry : ertn_entry;
```

`pipe_flush`、`redirect_pc[31:0]` 为 IF 新增输入；ID/EXE/MEM 新增输入 `pipe_flush`。WB 直接使用自己生成的事件清当前 ws_valid，不回接 pipe_flush 形成逻辑环。所有事件组合生成，禁止“ws_valid 因 wb_ex 清零，又用清零后的 ws_valid 组合算 wb_ex”的组合环。

EXE 新增输入：`ms_ex_pending`、`counter_value[63:0]`。ID 新增输入：`has_int`、`es_valid_for_ctrl`、`ms_valid_for_ctrl`、`ws_valid_for_ctrl`、`es_serializing`、`ms_serializing`、`ws_serializing`。

EXE/MEM/WB 各导出对应 `*_valid_for_ctrl` 和 `*_serializing`；MEM 额外导出 `ms_ex_pending`。原始 valid 导出不得依赖本周期冲刷组合屏蔽后的握手输出，否则可能造成 ID 控制环。

定义：

- `*_serializing = *_valid && (csr_op != NONE || ertn || exc.valid || cnt_op != NONE)`。ex8的cnt_op恒NONE；ex9计数器读取也使用保守序列化。
- `ms_ex_pending = ms_valid && ms_meta.exc.valid`，直接来自 MEM 寄存器。
- 已知 CSR 尚未得到 WB 旧值时，EXE/MEM 前递的 gr_we 必须屏蔽；WB 才向 ID 前递实际 CSR 旧值。不能改原 41/39/39 位反馈布局。
- 所有 stage 的新增信息在 `valid && next_allowin && !pipe_flush` 成功传输时与原数据同时锁存；阻塞时保持，气泡时不可被当作有效事件。

## 3. 数据总线保持基线原样

| 原宏 | 固定宽度 |
|---|---:|
| BR_BUS_WD | 33 |
| FS_TO_DS_BUS_WD | 64 |
| DS_TO_ES_BUS_WD | 160 |
| ES_TO_MS_BUS_WD | 107 |
| MS_TO_WS_BUS_WD | 70 |
| WS_TO_RF_BUS_WD | 38 |
| ES_TO_DS_BUS_WD / MS_TO_DS_BUS_WD / WS_TO_DS_BUS_WD | 41 / 39 / 39 |

原字段打包顺序以基线 RTL 为准，保持不动。新增定义由 B 写入 `mycpu_head.v`：`EXC_BUS_WD=49`、`PIPE_META_WD=164`。新增并行端口：

| 生产者 → 接收者 | 端口名 | 宽度 |
|---|---|---:|
| IF → ID | fs_to_ds_ex | 49 |
| ID → EXE | ds_to_es_meta | 164 |
| EXE → MEM | es_to_ms_meta | 164 |
| MEM → WB | ms_to_ws_meta | 164 |

不增加独立 meta_valid；必须跟随同名原 valid/allowin。ex8 起就用完整预留宽度。所有未用字段置零，不允许 X/Z 占位。

## 4. 异常子总线 EXC（49 位）

拼接顺序高到低：`{valid, ecode, esubcode, badv_valid, badv}`。

| 字段 | 位区间 |
|---|---|
| valid | [48] |
| ecode | [47:42] |
| esubcode | [41:33] |
| badv_valid | [32] |
| badv | [31:0] |

无异常时整个 49 位清零。PC 已在原总线内，禁止把 BADV 当作异常 PC。ADEF 的 badv=指令 PC；ALE 的 badv=原始有效访存地址。

## 5. 元数据 META（164 位）

拼接顺序高到低：`{csr_op, csr_num, csr_wmask, csr_wvalue, exc, ertn, cnt_op, cnt_value}`。

| 字段 | 宽度 | 位区间 |
|---|---:|---|
| csr_op | 2 | [163:162] |
| csr_num | 14 | [161:148] |
| csr_wmask | 32 | [147:116] |
| csr_wvalue | 32 | [115:84] |
| exc | 49 | [83:35] |
| ertn | 1 | [34] |
| cnt_op | 2 | [33:32] |
| cnt_value | 32 | [31:0] |

`csr_op`：NONE=00、RD=01、WR=10、XCHG=11。

`cnt_op`：NONE=00、LOW=01、HIGH=10、ID=11。这里ID枚举表示读取计时器标识，不是流水线ID级。ex8 全部 00。ID级输出 cnt_value=0；EXE 对 LOW/HIGH 在成功进入 MEM 的那个上升沿采样 counter_value 相应半部，后续锁存，不继续读取实时计数器；cnt_op==ID的实际值由 WB 的 tid_value 选择。

WR 的 wmask=32'hffffffff；RD/NONE 的 wmask/wvalue=0；XCHG 的 wmask=通用寄存器 rj 值。WR/XCHG 的 wvalue=原通用寄存器 rd 值。CSR 指令目的寄存器也是 rd，不能误用掩码寄存器 rj 作为目的。

## 6. ex9 顶层中断端口

`mycpu_top` 在实施 ex9 时新增 `input wire [7:0] hw_int_in`，直接送 CSR；C 更新全部例化。没有外设中断源的仿真/原有 SoC 显式接 `8'b0`，不能悬空。真实异步引脚先由 SoC 同步后进入此端口；测试平台在时钟边沿外驱动同步输入。团队不实现核间中断。

## 7. 接口验收

A/B/C 逐端口对照本表；逐字段检查 49/164 位拼接；运行全不同比特图样的元数据传输测试；阻塞两拍确认保持，冲刷确认丢弃。`interface-v1.json` 为机器可核对副本，任何差异必须先修正文档，不能按个人偏好选择一种。
