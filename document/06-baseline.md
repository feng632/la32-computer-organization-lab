# 团队基线、环境与材料获取

## 1. 固定起点

仓库：https://github.com/feng632/la32-computer-organization-lab

完整工程基线：`48dc551bbc685e5351a057b7a26c8115bc7ddcf6`。后续main会前进，不能仅写“用最新main”。本目录是随后增加的文档，不改变这个CPU基线。

课程原始源码历史：ex6 CPU `abe2780`；ex7 CPU `06cc150`；ex7原始分支含构建报告的提交 `7e9d1ce`。**原始ex7分支不等于main发布的完整环境**，两个XCI在main中已整理到rtl/xilinx_ip。

从同一克隆取得当前document后，C以完整基线创建integration-ex8-ex9，把本资料目录的文档提交合入集成分支，再组织G1接口骨架；A/B/C功能分支从同一个G1提交建立。不要从尚未接齐端口的不同中间提交分别开工。

示例（仅在对应分支尚未存在时，由C执行）：

```bash
git fetch origin --tags
git switch -c integration-ex8-ex9 48dc551bbc685e5351a057b7a26c8115bc7ddcf6
# 把本次document文档提交合入，再开始接口骨架；实际提交号看仓库历史。
```

如已有同名共享分支，跟踪现有分支，不重建、不强制覆盖。每人先保存本地修改。

## 2. 环境

- Vivado 2023.2，器件xc7a200tfbg676-1。
- CPU工程：`soc_verify/soc_bram/run_vivado/project/loongson.xpr`。
- 参考工程：`gettrace/gettrace.xpr`；参考工程不能换成待测CPU。
- CPU仿真顶层tb_top，设计顶层soc_lite_top。旧sync_ram.v不能和RAM IP重复作为仿真模型。
- 指令/数据RAM镜像在func/obj；换镜像后更新IP并重新启动仿真。
- 有符号/无符号除法XCI：`soc_verify/soc_bram/rtl/xilinx_ip/div_signed/div_signed.xci`与对应div_unsigned。
- 两者Radix2、32/32、整数余数、NonBlocking、每拍接收能力、ARESETN开启、ACLKEN关闭，自动延迟36/34拍。Generate Output Products必须真实生成，不能用空壳替代。
- 既有远程bit CPU时钟50MHz；这不代表任何新建工程或默认仿真时钟也自动等于50MHz。

## 3. 已知历史证据

ex7本地PASS来自既有记录，线上任务5890得分100。远程构建报告WNS=-1.127ns、TNS=-208.302ns，DRC 0错误/18警告：**功能与线上通过，静态时序未完全通过**。详见`../docs/verification/ex7/README.md`。

G0仍由C在团队环境复现一次，并记录实际结果；这是未来开工要求，不是本次已重跑。ex8/ex9尚未实施，无通过记录。

## 4. 文件核对

`baseline.json`记录基线Git内容SHA-256（LF归一化，避免Windows CRLF差异）和本机课程输入文件的原始字节SHA-256。基线清单包括CPU、五个XCI、镜像及golden_trace；不要把本目录后续变动与CPU基线混淆。

基线核对命令（将PATH替换为清单里的相对路径）：

```bash
git show 48dc551bbc685e5351a057b7a26c8115bc7ddcf6:PATH
```

哈希只证明文件相同，不证明仿真已执行。测试结果必须另外填写07。

## 5. 必须给各自AI的资料

1. 当前本地工程，注明当前commit、分支、接口版本。
2. 本目录公共规范和本人roles任务书。
3. 课程《计组课设指导书LA版-2025.pdf》第6章及评分说明；《计算机组成原理课程设计说明LA+2026.pptx》第10～11页。
4. 课程`appendix_la/A01_龙芯架构32位精简版参考手册.pdf`（核验版本1.03，见新增基线资料哈希）；它优先于现代LoongArch在线手册。后者指令命名/字段可能不同，不能据此猜课程rdcnt编码。
5. 课程for_test_obj/ex8_obj、ex9_obj镜像；测试源码或反汇编；最新交付与问题记录。

课程资料由团队通过课程渠道自行取得。PDF、PPT和额外测试镜像本次不公开上传，只在baseline.json记录本机核验哈希。组员路径可以不同，不能在RTL、Tcl或测试中写死作者E盘路径。

如果AI拿不到某项资料，应列出缺项，继续不依赖它的解释/自测准备；不得伪造读过资料、跑过工具或通过测试。暂缓依赖未知编码/字段的实施，直到取得资料或从官方/课程来源核对。
