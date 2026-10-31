# A：分支预测器独立测试

实现：`myCPU/branch_predictor.v`，由原 `bp.v` 补全并改名，接口遵循 TEAM-BP-1.0。

运行（仓库根目录）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/team/predictor/run.ps1
```

可用 `-VivadoBin` 指定 Vivado bin 目录，`-OutputDir` 指定生成文件目录；默认输出到系统临时目录。

2026-10-31：Vivado 2023.2 xvlog/xelab/xsim，`PREDICTOR_PASS checks=157`。
覆盖复位清空所有字段、冷启动、首次分配、饱和加减、同索引替换、类别切换、目标更新和低位保留、非分支匹配失效与冲突保护、关闭时不查询不更新、无效更新、未对齐查询、复位优先、同沿查询采样旧值。

只验证预测器独立行为；未运行 CPU 联合回归、综合、时序或云测。顶层当前仍有预测输出 tie-off，需 C 用真实模块替换并加入工程源文件。预测器没有 WB flush 输入，冲刷不清预测表。
