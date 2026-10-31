# P2 联合正确性测试（分支预测）

对照 `document/10-branch-prediction.md` 第 7 节 P2 的四条要求。
用自建汇编器 + 行为级 RAM 跑定向程序，**不依赖交叉工具链与课程镜像**；
ex9 完整镜像的回归另见 `docs/verification/ex9/`。

## 为什么需要这一套

课程镜像（ex8/ex9）只能证明"程序跑通了"，无法主动构造：

- 循环、连续分支、同索引冲突、间接跳转目标变化
- 错误路径上放"写寄存器 / 写内存 / 写 CSR / syscall"这类有副作用的指令

而分支预测的正确性核心恰恰是：**预测错误时，错误路径不得产生任何架构副作用**。
这类场景在课程程序里可能一次都不出现，必须主动造。

## 文件

| 文件 | 作用 |
|---|---|
| `asm.py` | 微型汇编器。编码全部从 `func/obj/test.s` 的真实反汇编反推，`--selftest` 对 18 个样本重新编码比对 |
| `tb_bp_p2.sv` | 测试台。行为级指令/数据 RAM，`-d BP_ON` 时 `BP_EN=1` |
| `run_bp_p2.ps1` | 一键复现，`-BpOn` 切换配置 |
| `prog/*.s` / `*.expect` | 定向程序与期望值 |

## 运行方法

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
./tests/team/integration/bp_p2/run_bp_p2.ps1            # BP=0 对照
./tests/team/integration/bp_p2/run_bp_p2.ps1 -BpOn      # BP=1 预测生效
```

snapshot 名分别为 `p2_bp0` / `p2_bp1`，两次互不干扰。

## 程序清单与判据

| 程序 | 对应 P2 条目 | 构造 | 判据 |
|---|---|---|---|
| `p1_loop` | ① 循环 | 10 次后向分支 | r5=30，mem[0]=30 |
| `p3_conflict` | ① 同索引冲突 | 三处 `b`，含 PC[7:2] 相同但 tag 不同的项 | r5=7 |
| `p4_jirl` | ① 目标变化 | 同一 jirl 站点在 t1/t2 间切换 | r5=5 |
| `p2_wrong` | ② 写寄存器 + 写内存 | 错误路径改 r8、写 mem[1] | mem[0]=0xdead，**mem[1]=0** |
| `p7_csr_wrong` | ② **CSR 写** | 循环 3 次，错误路径 `csrwr r6, save0`（r6=0x5a5a 已在正确路径备好） | **r7(save0)=0**；r6 仍 0x5a5a；mem[0]=0，mem[1]=0x5a5a |
| `p8_syscall_wrong` | ② **syscall** | 循环 3 次，错误路径 `syscall 0` | r10=3，mem[0]=3 |
| `p9_cross` | ③ **load-use 交叉** | `ld.w` 后紧跟依赖该值的 `beq`，ID 阻塞等数据时 IF 已取入错误路径指令 | r6=3，mem[0]=3；纠正丢失则 r6=0x5ad |
| `p10_alt` | ① **交替方向** | r8 在 0/1 翻转，主分支因此交替 taken/not-taken，2-bit 状态在 10/01 间来回、每轮都错 | r6=8，mem[0]=8；两条路径各执行一次 `+1`，若丢指令或重复执行即偏离 |

`p7` 的判据是双向的：若 `csrwr` 被执行，`save0` 变 0x5a5a（r7 读到非 0），
同时 `r6` 被回写旧值 0，两个判据同时失败。
`p8` 若 syscall 误执行，会跳向未初始化的 EENTRY，永远写不到结束标志，TB 超时判 FAIL。

## 结果（2026-10-31 22:54）

8 个程序 × 2 种配置，**16 次运行全部 PASS，0 项失败**。

| 程序 | BP=0 周期 | BP=1 周期 | 检查项 |
|---|---|---|---|
| p1_loop | 50 | 43 | 2 |
| p2_wrong | 14 | 14 | 2 |
| p3_conflict | 17 | 17 | 2 |
| p4_jirl | 43 | 43 | 2 |
| p7_csr_wrong | 34 | 31 | 4 |
| p8_syscall_wrong | 28 | 26 | 2 |
| p9_cross | 34 | 32 | 2 |
| p10_alt | 91 | 87 | 2 |

日志：`docs/verification/bp_p2/p2-bp0-2026-10-31.log`、`p2-bp1-2026-10-31.log`。

## 对照 P2 四条

| P2 要求 | 覆盖情况 |
|---|---|
| ① 真实模块 + 短程序覆盖循环 / 交替方向 / 连续分支 / 同索引冲突 / 目标变化 | **完成**：循环 p1、交替方向 p10、连续分支 p3、同索引冲突 p3、目标变化 p4 |
| ② 错误路径写寄存器、写内存、CSR 写、syscall/break，无架构副作用 | **除 break 外全覆盖**。break 机器码在 `func/obj/test.s` 无样本，`asm.py` 无编码来源，按"禁止臆造"未添加 |
| ③ 与除法等待、load-use、异常/ERTN 冲刷交叉，验证不死锁及优先级 | **load-use 已定向（p9）**；除法与异常/ERTN 交叉**无定向程序**，仅由 ex9 完整镜像间接覆盖 |
| ④ BP=0 和 BP=1 分别运行完整 ex9 及参考轨迹 | **完成**，见 `docs/verification/ex9/ex9-bp0/1-2026-10-31.log` |

## 已知局限（如实记录，不外推）

1. **break 未测**：无真实编码样本，不臆造。
2. **除法等待交叉未定向**：本 TB 的 `div_signed` / `div_unsigned` 是占位模块，
   一经请求即 `$fatal`，无法在此环境跑除法。ex9 镜像含除法指令且 58/58 通过，
   属间接覆盖，不等价于"定向验证交叉优先级"。
3. **交替方向的预期就是"错"**：`p10_alt` 在 P3 统计下 BP=1 准确率仅 39.4%
   （7 次漏预测 + 8 次过度预测），这是 2-bit 预测器的固有局限，
   不是实现缺陷。该程序的用途是证明"持续错预测时结果仍正确"，不是证明性能。
