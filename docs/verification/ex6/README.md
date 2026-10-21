# ex6 本地功能仿真验收记录

日期：2026-10-12。分支：ex6-memory。

实现：ld.b、ld.bu、ld.h、ld.hu、st.b、st.h。
ID→EXE 总线153位，EXE→MEM总线107位。

测试镜像来自课程 for_test_obj/ex6_obj，六个文件与 func/obj 的 SHA-256 全部一致。
inst_ram.coe SHA-256：3B1A8C62ED17D2AFDF633E492D2E99D04084D1E9088C3B5A8B8F728F4ADA96B2。
test.s SHA-256：FB49715DF85519DCBA75F1860E2E1696AD43555C67F83AA9F12F068EF6380DB5。

参考工程 gettrace/gettrace.xpr 重新启动行为仿真并 run all，用户提供的控制台结果：

```text
----Succeed in generating trace file!
$finish called at time : 1003485 ns
```

CPU工程 soc_verify/soc_bram/run_vivado/project/loongson.xpr 重新启动行为仿真，分段运行后 run all，用户提供的最终控制台结果：

```text
----[1078445 ns] Number 8'd39 Functional Test Point PASS!!!
==============================================================
Test end!
----PASS!!!
$finish called at time : 1078935 ns
```

镜像调用 n1～n29、n37～n46，跳过7项乘除法测试，因此共39个测试点；n41～n46对应实际计数34～39。

结论：本次课程ex6镜像的本地功能仿真通过。

后续线上评测：根据用户提供的平台结果截图，2026-10-12上传ex6_remote.bit，任务ID为4735，状态Finished，得分100。该结果来自用户提供的截图，未通过平台接口独立查询。

simulate.partial.log 是保存时从磁盘读取的未完整刷新日志，只到测试点34。完整结束结果来自上述用户提供的Vivado控制台输出，不能将此部分日志当作完整日志。
