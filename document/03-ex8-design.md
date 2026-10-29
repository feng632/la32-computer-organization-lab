# ex8 实施设计

## 1. 范围与取舍

实现 CSRRD/CSRWR/CSRXCHG、SYSCALL、ERTN，以及本章 CSR。保持课程直接地址访问环境，不引入 MMU、TLB、缓存、虚拟地址翻译、嵌套异常自动堆栈或完整特权检查。PLV/IE 状态仍需正确保存恢复。指令编码须对照课程指令手册与测试反汇编，不猜 opcode。

译码结果：CSR 写指令读取原 rd；XCHG 额外读取 rj 掩码。三个 CSR 指令都将 CSR **写前旧值**写入 rd（rd=0 时通用寄存器写入无效，但 CSR 写入不能因此取消）。syscall/ertn 不写通用寄存器、不访问数据 RAM。

## 2. CSR 寄存器表（A 维护）

这是课程子集的实现选择；未实现字段读零写忽略。下表中“团队复位 0”是便于复现的确定性实现选择，不代表架构要求所有这些字段必须清零。

| 名称 | 14 位编号 | 实现字段 | 软件可写 | 团队复位值 |
|---|---|---|---|---|
| CRMD | 0x000 | PLV[1:0]、IE[2]；DA[3]=1，其余0 | [2:0] | 0x00000008 |
| PRMD | 0x001 | PPLV[1:0]、PIE[2] | [2:0] | 0 |
| ESTAT | 0x005 | IS[1:0]；Ecode[21:16]、EsubCode[30:22] | 仅 IS[1:0] | 0 |
| ERA | 0x006 | PC[31:0] | 全32位 | 0 |
| EENTRY | 0x00c | VA[31:6]，低6位读0 | [31:6] | 0 |
| SAVE0～3 | 0x030～0x033 | 全32位 | 全32位 | 0 |

ex8 的 ESTAT 其他中断位固定零，has_int=0；ex9 再开放 04 的字段。没有实现的编号，包括 ex8 尚未实现的计时 CSR，读零写忽略。

写新值：对可写字段使用 `(old & ~effective_mask) | (csr_wvalue & effective_mask)`，effective_mask 是指令掩码与可写位掩码的交集。保持保留位和只读位规则。

## 3. WB 提交

- `wb_ex = ws_valid && ws_exc.valid && !reset`。
- `ertn_flush = ws_valid && ws_ertn && !ws_exc.valid && !reset`。
- 普通通用寄存器写入：原 gr_we、ws_valid、!reset、!wb_ex、!ertn_flush，同时 rd 非0。debug_wb_rf_we 与实际通用寄存器写使能一致。
- 普通 CSR 写入：上述事件无效，csr_op 为 WR/XCHG；不能受 rd 是否0影响。
- CSR 指令最终结果=csr_rvalue；ex9 计数器指令按04选择；其他指令仍用 ws_final_result。WB 前递和 debug 使用同一个最终结果。
- wb_pc 始终提供当前 ws_pc；badv_valid 无效时 badv 输出0。

CSR 状态控制优先级：reset > wb_ex > ertn_flush > 普通软件写入。事件只允许在当前有效 WB 指令上产生一拍；冲刷后 ws_valid 清0。WB 不允许在异常/返回边沿接收后面 MEM 指令。

上述优先级针对同一寄存器字段的竞争；ex9的硬中断采样、定时器、稳定计数器是独立更新路径，不能因wb_ex/ERTN而暂停，也不能把整套csr放进一个大else-if导致这些状态停更。

异常提交：PRMD 保存 CRMD.PLV/IE；CRMD.PLV/IE清0；ERA保存wb_pc；ESTAT保存编码。SYS编码为 Ecode=0x0b、EsubCode=0，BADV不更新。EENTRY不因异常自动改写。

ERTN：CRMD.PLV/IE恢复PRMD；跳转使用原ERA，不自动+4。syscall处理程序如需继续下一条，应先将ERA增加4再返回。异常入口必须由软件先设置有效地址。

## 4. 保守序列化（B 实现）

`serial_inflight = es_serializing || ms_serializing || ws_serializing`；`older_valid = es_valid_for_ctrl || ms_valid_for_ctrl || ws_valid_for_ctrl`。

ID在判断是否需要排空时，使用本周期组合形成的候选异常（含ex9的has_int），不是等待发射后才出现的元数据寄存器；异常标记只在成功发射时锁存。这样“需要排空”和“锁存中断”之间不会互相等待。

1. ID 中 CSR / syscall / ertn，或已经带异常的指令，必须等待 older_valid=0 才能向 EXE 发射。ex9对cnt_op!=NONE同样处理。
2. serial_inflight=1 时，任何年轻 ID 指令都不能发射，也不能产生分支跳转。
3. 正常 RAW / load-use / 除法未完成相关仍保留；不能因“序列化”删除 ex7 机制。
4. 旧指令继续前进，不能把 EXE/MEM/WB 一起停住。CSR 正常提交后，下一拍解除序列化；异常/返回则冲刷。
5. EXE/MEM 中 CSR 指令不能把普通 ALU 值当作 CSR 结果前递。WB 使用真实旧 CSR 值前递；序列化提供额外保护。

本策略性能保守但能避免读CSR旧状态、中断使能变更、ERA紧邻ertn等冲突。不增加对某些CSR的特殊前递优化。

## 5. 冲刷与访存保护

所有流水 valid：reset > 全局冲刷 > 正常allowin。冲刷不等待 es_ready_go；元数据寄存器可以不全清，但无效指令不得产生任何作用。

IF在冲刷边沿清旧fs_valid、锁存redirect_pc并置redirect_pending；冲刷当拍不发旧路径请求。下一拍使用锁存地址发起新取指，不能重新使用旧fs_pc+4；新请求/返回配对后才将fs_valid置1。新冲刷覆盖尚未消费的redirect_pending；reset清pending。同步BRAM已经发出的旧响应必须丢弃，不能重新标有效。ex9错误目标按04生成ADEF标记，不实际访问。

EXE数据请求使能至少同时满足：

```text
!reset && !pipe_flush && !ms_ex_pending
&& es_valid && es_ready_go && ms_allowin
&& !es_exc.valid && (当前指令是load或store)
```

store的4位写使能只在该请求合格且确为store时非零。发现自身异常或MEM中存在较老异常时，即使WB尚未报异常，也不得发出数据读写。已经发出的正常store不能回滚，因此这里必须是组合屏蔽。

带异常的EXE指令只传递异常标记，应视为本级已完成（es_ready_go=1），不得再等待原指令的load/除法结果；请求及普通写使能均关闭，避免异常标记自己卡住。

对年轻分支：br_taken 至少受 ds_valid、ds_ready_go、es_allowin、!pipe_flush、!serial_inflight、!ds_exc.valid约束；跳转只在该ID指令被接受时生效。

## 6. 除法取消（固定方案）

冲刷同时取消两个IP：清sent/done/结果有效状态，立即撤销输入tvalid并拉低两个aresetn。保持低电平覆盖至少两个完整上升沿，再拉高并保留一个完整恢复周期；恢复结束后才允许新请求。reset或重复冲刷重新开始恢复过程。

使用独立恢复状态机 RESET_HOLD → RECOVER → RUN；EXE发新除法请求必须处于RUN，且当前指令有效、无异常、无较老异常、未发送、非reset/flush。结果只在RUN且sent且未done且当前除法类型匹配时接收。恢复期间忽略所有旧out_valid。

EXE可以先接收新除法指令并等待RUN，但不能把恢复中的无效结果标成done。普通ALU指令不必因IP恢复暂停。稳定计数器/定时器不受pipe_flush复位。

不能只清done/sent：基线IP可能仍在计算。不能直接用`~(reset || pipe_flush)`作为唯一复位控制：单拍冲刷不足以满足IP复位及恢复时序。

## 7. 实施顺序

接口骨架 → CSR访问 → syscall入口与ERTN返回 → 冲突/冲刷/副作用保护 → 课程ex8完整验证。骨架阶段所有新控制为零，不应改变ex7结果。最小闭环只是调试里程碑，不能代替完整异常保护验收。
