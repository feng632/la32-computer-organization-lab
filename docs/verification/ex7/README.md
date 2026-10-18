# ex7 乘除法本地验收记录

日期：2026-10-18。分支：ex7-muldiv。

实现指令：mul.w、mulh.w、mulh.wu、div.w、mod.w、div.wu、mod.wu。
ID→EXE总线160位，EXE→ID总线41位；除法使用单次请求、结果缓存、EXE等待和ID相关阻塞。

## 除法器配置

Vivado 2023.2，Divider Generator 5.1，两个32位输入，整数余数，Radix2，NonBlocking，Clocks per Division=1，开启ARESETN。
div_signed使用Signed、自动延迟36周期；div_unsigned使用Unsigned、自动延迟34周期。
结果高32位为商，低32位为余数。

以下两个原始IP配置纳入版本控制，生成产品不纳入：

- soc_verify/soc_bram/run_vivado/project/loongson.srcs/sources_1/ip/div_signed/div_signed.xci
- soc_verify/soc_bram/run_vivado/project/loongson.srcs/sources_1/ip/div_unsigned/div_unsigned.xci

重建工程时需将这两个XCI添加为设计源，在Vivado中Generate Output Products。CPU源码单独复制而不添加IP，无法完成编译。

## 测试镜像和结果

使用课程for_test_obj/ex7_obj的六个文件，逐一核对与func/obj的SHA-256一致。该镜像包含全部46个测试点。

参考仿真已直接核验磁盘日志，末尾为：

```text
----[1085115 ns] Number 8'd46 Functional Test Point PASS!!!
gettrace end!
----Succeed in generating trace file!
$finish called at time : 1085445 ns
```

用户提供的CPU仿真最终控制台输出：

```text
Test end!
----PASS!!!
$finish called at time : 1376195 ns
run: Time (s): cpu = 00:00:34 ; elapsed = 00:05:08
```

保存记录时，CPU simulate.log尚未完整刷新，仅到测试点34附近，存为simulate.partial.log；不能把此部分日志称为完整日志。最终通过依据是上述用户提供的控制台结束输出。

结论：本次ex7课程镜像本地功能仿真PASS。此记录不表示线上评测通过，也不表示综合实现后的时序通过。

## 远程bit构建

源码提交06cc150，标签ex7-pass。已建立独立目录E:/LA32/ex7_remote，采用与主工程哈希一致的CPU及课程ex7_obj镜像，包含两个除法器IP和既有远程板卡接口。

Vivado 2023.2，目标xc7a200tfbg676-1，CPU时钟50 MHz。综合、布局、布线、bit生成成功；输出E:/LA32/ex7_remote/ex7_remote.bit，5000107字节。

执行一轮布线后物理优化与重新布线。最终WNS为−1.127 ns，TNS为−208.302 ns，566个建立时间失败端点；WHS为+0.019 ns，保持时间无失败端点。静态时序未完全通过。

DRC为0错误、18警告（16条DSP乘法器流水寄存器建议、2条时钟缓冲连接建议），布线错误为0。生成成功不代表线上评测通过；本次未上传评测平台。

remote/目录保存构建脚本、资源/时序/DRC/布线报告、CPU哈希、bit哈希及构建结果。build.tcl运行时以脚本所在目录为独立工程根目录，需要先按本次目录结构放好源码、RAM/时钟IP、两个除法器XCI、ex7测试镜像及远程板卡接口，不能仅在文档目录直接运行。为避免仓库膨胀，bit和DCP保留在独立构建目录，不纳入Git。
