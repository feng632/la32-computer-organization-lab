# CSR 独立测试

只实例化 `myCPU/csr.v`，直接驱动模块接口，不需要流水线、RAM 镜像、参考 CPU 或 IP 核。用 Vivado 自带的 xvlog/xelab/xsim 运行。

在仓库根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/team/csr/run.ps1
```

默认工具目录为 `E:\Vivado\Vivado\2023.2\bin`，可通过 `-VivadoBin` 指定。每次在 `%TEMP%` 下建立独立输出目录，结尾打印位置；目录内有三阶段的标准输出/错误、Vivado 日志及 `result.json`（含源码和测试平台 SHA-256）。可用 `-OutputDir` 指定新目录。`-CsrSource` 可测试指定的 CSR 文件，默认使用当前工作区文件。

成功退出码为 0；工具失败、断言失败、超时或缺少成功标记均返回 1。每个工具默认最多运行 120 秒（`-TimeoutSeconds` 可调），仿真最多 100 us。即使 xsim 在 `$fatal` 后返回 0，脚本也会因缺少 `CSR_TEST_PASS` 返回失败。

`tb_csr.sv` 按以下顺序测试。每条断言使用四态比较，X/Z 也算失败；失败打印组号、检查项、仿真时间、期望和实际值。各组失败后继续跑其余组，最后汇总。

| 组 | 覆盖内容 |
|---|---|
| A01 | 两拍复位、全部实现 CSR 的复位读值、入口/TID/中断输出 |
| A02 | 沿前旧值、沿后掩码新值、零掩码保持、SAVE 独立存储、TID 输出 |
| A03 | 未实现编号、可写位/保留位、EENTRY 对齐、ESTAT 写权限、TVAL 只读、TICLR 读零、BADV 软件掩码写 |
| A04 | 异常 > ERTN > 普通写；ERA/PRMD/完整异常码；BADV 有效位；复位与全部事件竞争 |
| A05 | SYS 保存原 PC/模式，清 PLV/IE，不自动覆盖 SAVE |
| A06 | 两个软件中断源、LIE/IE 门控、无 IPI 源、定时中断挂起与门控分离 |
| A07 | 八路硬中断逐位采样/撤销；硬中断、软件写、定时到期及异常码同拍独立更新 |
| A08 | 单次/周期初值 4 和 0；停止/重启；掩码合并配置；禁用保持；旧值为 0/1 时关闭及重配；异常/ERTN 屏蔽配置写而不停止计时 |
| A09 | TICLR 掩码/写值有效性；异常/ERTN 屏蔽清除；旧值为 0/1 时清除；到期置位优先 |
| A10 | 所有测试边沿自动核对稳定计数器 +1；无提交时继续计数；异常/ERTN/TCFG 不重置；低 32 位进位及 64 位回绕 |

测试只在 `clk=0` 时驱动输入，通过 `tick()` 明确推进一个上升沿，沿后 1 ns 再检查，避免与非阻塞赋值竞争。组合读不会暗中推进时钟。

A10 为避免运行 2^32 拍，明确向 `dut._STABLE_COUNTER` 做两次测试专用内部赋值（`0x00000000ffffffff` 和 `0xffffffffffffffff`），随后检查真实时钟更新。这不是 CPU 指令激励，也不修改 RTL；若将来内部名称变化，只需调整这两处测试引用。CSR 没有 stall/pipe_flush 端口，因此“无提交”及 wb_ex/ertn_flush 是模块级覆盖，不能替代整机暂停/冲刷连线验证。

测试依据为 `document/05-validation.md` 的 A01～A10、`04-ex9-design.md` 的计时边界及接口约定。权限使用集成分支提交 `6584084a52f552a106f915023a0434e8525c70f3` 中 `document/09-errata.md` 的纠正：**BADV 软件 RW，ECFG 可写掩码为 `0x00001bff`（含 LIE[12]），ESTAT.IS[12] 无中断源仍为 0**。当前分支旧文档尚未同步时，不应把测试改回旧权限。

这里验证 CSR 模块契约，不验证指令译码、流水线传输、整机异常跳转、课程参考 CPU 在边界上的行为或 FPGA 时序。初次运行记录见 [result-2026-10-29.md](result-2026-10-29.md)。
