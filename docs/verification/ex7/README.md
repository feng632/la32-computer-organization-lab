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
