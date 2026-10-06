# 计算机组成原理课程设计实验一验收说明

> 项目：LoongArch 32 位单发射五级流水 CPU  
> 内容：ex1（基本五级流水）、ex2（阻塞处理 RAW 冲突）、ex3（前递处理 RAW 冲突）  
> 当前最终版本：Git 分支 `ex3-forwarding`，提交 `e3410f8`，标签 `ex3-pass`  
> 说明：本文中的行号对应上述提交。ex2 的历史代码行号对应标签 `ex2-pass`（提交 `f37267b`）。

## 1. 实验目标与完成情况

实验以原有单周期 LA32 CPU 为基础，将数据通路拆分为经典的五级流水结构：

```text
IF（取指） → ID（译码） → EXE（执行） → MEM（访存） → WB（写回）
```

三个测试目标是逐步递进的：

| 测试目标 | 主要任务 | 处理冲突的方法 | 当前状态 |
|---|---|---|---|
| ex1 | 将单周期 CPU 拆分为五级流水 CPU | 暂不考虑数据冲突 | 功能仿真通过 |
| ex2 | 处理寄存器 RAW 数据相关 | 发现相关后阻塞 ID，等待写回 | 功能仿真通过 |
| ex3 | 优化 RAW 数据相关处理 | EXE/MEM/WB 向 ID 前递，仅 load-use 停顿 | 功能仿真通过 |

最终 ex3 仿真结果：

```text
Test end!
----PASS!!!
$finish called at time : 604465 ns
```

用于对比的运行时间：

| 版本 | 仿真结束时间 | 说明 |
|---|---:|---|
| 单周期参考 gettrace | 约 568095 ns | CPI 约为 1，用于生成参考 trace |
| ex2 阻塞流水 | 约 1322000 ns | 所有 RAW 均等待写回，停顿较多 |
| ex3 前递流水 | 604465 ns | 大部分 RAW 通过旁路解决 |

ex3 相比 ex2 的仿真周期约减少 54%，说明前递显著减少了不必要的流水线停顿。

---

## 2. 工程结构与重要缩写

### 2.1 主要源文件

| 文件 | 功能 |
|---|---|
| `myCPU/mycpu_top.v` | CPU 顶层，实例化五级流水模块并连接总线 |
| `myCPU/mycpu_head.v` | 统一定义各级间总线宽度 |
| `myCPU/IF_stage.v` | 取指、PC 更新、分支错误路径取消 |
| `myCPU/ID_stage.v` | 指令译码、寄存器读取、相关检测、前递选择、分支判断 |
| `myCPU/EXE_stage.v` | ALU 运算、访存地址计算、数据 RAM 请求 |
| `myCPU/MEM_stage.v` | 选择 RAM 返回数据或 ALU 结果 |
| `myCPU/WB_stage.v` | 将最终结果写回寄存器堆并输出 trace |
| `myCPU/alu.v` | 算术逻辑运算单元 |
| `myCPU/regfile.v` | 32 个通用寄存器组成的寄存器堆 |
| `myCPU/tools.v` | 2-4、4-16、5-32、6-64 译码器 |

### 2.2 常用缩写

| 缩写 | 全称 | 含义 |
|---|---|---|
| `fs` | Fetch Stage | IF 取指级 |
| `ds` | Decode Stage | ID 译码级 |
| `es` | Execute Stage | EXE 执行级 |
| `ms` | Memory Stage | MEM 访存级 |
| `ws` | Writeback Stage | WB 写回级 |
| `rf` | Register File | 寄存器堆 |
| `gr` | General Register | 通用寄存器 |
| `we` | Write Enable | 写使能 |
| `dest` | Destination | 目的寄存器号 |
| `src` | Source | 源操作数 |
| `res` | Result | 结果 |
| `valid` | Valid | 当前流水级是否存有有效指令 |
| `allowin` | Allow In | 当前级是否允许前一级送入新指令 |
| `ready_go` | Ready to Go | 当前级工作是否完成、能否送往后一级 |

例如 `es_gr_we` 表示“EXE 级指令的通用寄存器写使能”。

---

## 3. ex1：不考虑冲突的五级流水 CPU

### 3.1 CPU 顶层接口调整

指导书要求为指令 RAM 和数据 RAM 增加片选信号，并将写使能改为 4 位字节写使能。最终接口位于 `myCPU/mycpu_top.v:3-25`：

```verilog
module mycpu_top(
    input  wire        clk,
    input  wire        resetn,

    output wire        inst_sram_en,
    output wire [ 3:0] inst_sram_we,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire [31:0] inst_sram_rdata,

    output wire        data_sram_en,
    output wire [ 3:0] data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    input  wire [31:0] data_sram_rdata,
    ...
);
```

`inst_sram_en` 和 `data_sram_en` 为高电平有效的片选信号：只有片选有效时 RAM 才响应访问。4 位写使能分别控制 32 位数据的四个字节：

```text
we[0] → data[7:0]
we[1] → data[15:8]
we[2] → data[23:16]
we[3] → data[31:24]
```

当前 `st.w` 按整字写入，因此 `myCPU/EXE_stage.v:106-113` 使用复制运算符把一位写条件扩展为四位：

```verilog
assign data_sram_en =
       es_valid && es_ready_go && ms_allowin;

assign data_sram_we =
       {4{es_mem_we && es_valid && ms_allowin}};

assign data_sram_addr  = es_alu_result;
assign data_sram_wdata = es_rkd_value;
```

`{4{condition}}` 表示将一位条件复制四次：条件为 1 时得到 `4'b1111`，条件为 0 时得到 `4'b0000`。

### 3.2 五级流水划分

顶层在 `myCPU/mycpu_top.v:75-173` 分别实例化 `IF_stage`、`ID_stage`、`EXE_stage`、`MEM_stage` 和 `WB_stage`。各级职责如下：

| 流水级 | 主要输入 | 主要工作 | 主要输出 |
|---|---|---|---|
| IF | PC、分支总线 | 产生取指地址并获得指令 | 指令、PC |
| ID | 指令、PC、寄存器堆 | 译码、读取操作数、生成控制信号 | ALU 控制、操作数、写回控制 |
| EXE | 操作数、ALU 控制 | 算术逻辑计算、生成访存地址 | ALU 结果、访存控制 |
| MEM | ALU 结果、RAM 返回值 | 选择最终写回结果 | 最终结果、目的寄存器 |
| WB | 最终结果、目的寄存器 | 写寄存器堆、输出 trace | `ws_to_rf_bus`、调试信号 |

### 3.3 级间总线定义

总线宽度集中定义在 `myCPU/mycpu_head.v:5-24`：

```verilog
`define BR_BUS_WD       33
`define FS_TO_DS_BUS_WD 64
`define DS_TO_ES_BUS_WD 148
`define ES_TO_MS_BUS_WD 104
`define MS_TO_WS_BUS_WD 70
`define WS_TO_RF_BUS_WD 38

`define ES_TO_DS_BUS_WD 40
`define MS_TO_DS_BUS_WD 39
`define WS_TO_DS_BUS_WD 39
```

前六条是基本流水通路，后三条是 ex2/ex3 中后级反馈给 ID 的冲突处理通路。主要总线内容为：

| 总线 | 宽度 | 内容 |
|---|---:|---|
| `br_bus` | 33 | `br_taken` 1 位 + `br_target` 32 位 |
| `fs_to_ds_bus` | 64 | 指令 32 位 + PC 32 位 |
| `ds_to_es_bus` | 148 | ALU 控制、写回/访存控制、目的寄存器、两个 ALU 源、存储数据、PC、访存结果选择 |
| `es_to_ms_bus` | 104 | 访存/写回控制、目的寄存器、ALU 结果、存储数据、PC |
| `ms_to_ws_bus` | 70 | 写回使能、目的寄存器、最终结果、PC |
| `ws_to_rf_bus` | 38 | 写使能、写地址、写数据 |

以 ID→EXE 为例，`myCPU/ID_stage.v:355-366` 将后续阶段需要的全部信息打包：

```verilog
assign ds_to_es_bus = {
    alu_op,         // 12位
    gr_we,          // 1位
    mem_we,         // 1位
    dest,           // 5位
    alu_src1,       // 32位
    alu_src2,       // 32位
    rkd_value,      // 32位
    ds_pc,          // 32位
    res_from_mem    // 1位
};
```

总线的打包与下一级拆包顺序必须完全一致，否则虽然位宽可能正确，每段比特的含义却会错位。

### 3.4 valid/allowin/ready_go 握手机制

每一级使用三个关键信号控制流水：

```text
valid：本级是否有有效指令
ready_go：本级工作是否已经完成
allowin：本级是否能接收前一级的新指令
```

通用关系为：

```verilog
this_allowin = !this_valid || (this_ready_go && next_allowin);
this_to_next_valid = this_valid && this_ready_go;
```

ID 级的实现位于 `myCPU/ID_stage.v:327-352`：

```verilog
assign ds_ready_go = !load_use_hazard;

assign ds_allowin =
       !ds_valid ||
       (ds_ready_go && es_allowin);

assign ds_to_es_valid =
       ds_valid && ds_ready_go;

always @(posedge clk) begin
    if (reset)
        ds_valid <= 1'b0;
    else if (ds_allowin)
        ds_valid <= fs_to_ds_valid;
end

always @(posedge clk) begin
    if (fs_to_ds_valid && ds_allowin)
        fs_to_ds_bus_r <= fs_to_ds_bus;
end
```

含义如下：

1. 本级为空时可以直接接收新指令；
2. 本级指令完成且下一级允许接收时，可以把旧指令送出并接收新指令；
3. 下一级阻塞时，本级保存原有 `valid` 和缓存数据，不能覆盖；
4. `valid=0` 表示空泡，不需要清除总线上所有数据，只要保证无效数据不产生体系结构作用即可。

### 3.5 IF 级 PC 与复位设计

`myCPU/IF_stage.v:65-95`：

```verilog
assign seq_pc  = fs_pc + 32'd4;
assign next_pc = br_taken ? br_target : seq_pc;

always @(posedge clk) begin
    if (reset)
        fs_pc <= 32'h1bfffffc;
    else if (to_fs_valid && fs_allowin)
        fs_pc <= next_pc;
end

assign inst_sram_en    = to_fs_valid && fs_allowin;
assign inst_sram_we    = 4'b0000;
assign inst_sram_addr  = next_pc;
assign inst_sram_wdata = 32'b0;
```

复位时没有直接写入 `0x1c000000`，而是写入 `0x1bfffffc`。复位解除后的首次更新执行 `PC+4`，刚好得到体系结构规定的复位入口 `0x1c000000`。

### 3.6 指令译码

ID 将指令字段送入多个独热译码器，代码位于 `myCPU/ID_stage.v:218-260`：

```verilog
decoder_6_64 u_dec0(.in(op_31_26), .out(op_31_26_d));
decoder_4_16 u_dec1(.in(op_25_22), .out(op_25_22_d));
decoder_2_4  u_dec2(.in(op_21_20), .out(op_21_20_d));
decoder_5_32 u_dec3(.in(op_19_15), .out(op_19_15_d));

assign inst_add_w =
   op_31_26_d[6'h00] &&
   op_25_22_d[4'h0]  &&
   op_21_20_d[2'h1]  &&
   op_19_15_d[5'h00];
```

四个译码器分别处理不同长度的 opcode 字段。每个译码器输出中只有一位为 1；最终用逻辑与组合多个字段，判断完整指令。不同译码器的独热输出不会拼接成一个“大独热码”，而是分别参与指令条件判断。

### 3.7 MEM 结果选择与 WB 写回

`myCPU/MEM_stage.v:87-102`：

```verilog
assign ms_final_result =
       ms_res_from_mem
       ? data_sram_rdata
       : ms_alu_result;

assign ms_to_ws_bus = {
    ms_gr_we,
    ms_dest,
    ms_final_result,
    ms_pc
};
```

所有指令都会经过 MEM 流水级，但不一定访问 RAM：

- `ld.w`：`ms_res_from_mem=1`，写回 RAM 返回的数据；
- ALU 指令：`ms_res_from_mem=0`，直接传递 ALU 结果；
- `st.w`：访问 RAM，但 `ms_gr_we=0`，不写通用寄存器。

WB 写回逻辑位于 `myCPU/WB_stage.v:76-96`：

```verilog
assign rf_we = ws_gr_we && ws_valid;

assign ws_to_rf_bus = {
    rf_we,
    ws_dest,
    ws_final_result
};

assign debug_wb_pc       = ws_pc;
assign debug_wb_rf_we    = {4{rf_we}};
assign debug_wb_rf_wnum  = ws_dest;
assign debug_wb_rf_wdata = ws_final_result;
```

`ws_gr_we` 表示指令类型需要写寄存器，`ws_valid` 表示 WB 中确实有有效指令，两者同时为 1 才能真正写寄存器堆。

### 3.8 控制相关处理

转移指令在 ID 确定跳转时，IF 已经取出了顺序地址上的下一条指令。该指令属于错误路径，必须取消。`myCPU/IF_stage.v:57-60`：

```verilog
assign fs_to_ds_valid =
       fs_valid && fs_ready_go && !br_taken;
```

当 `br_taken=1` 时，不将当前 IF 指令标记为有效，从而用 `valid` 机制取消错误路径指令。同时 `next_pc` 选择 `br_target`。

最终版本还在 `myCPU/ID_stage.v:602-609` 使用 `ds_ready_go` 约束分支：

```verilog
assign br_taken =
   (
       (inst_beq &&  rj_eq_rkd) ||
       (inst_bne && !rj_eq_rkd) ||
       inst_jirl || inst_bl || inst_b
   ) && ds_valid && ds_ready_go;
```

这样可以防止 ID 因数据尚未就绪而停顿时，使用旧操作数提前作出错误分支决定。

---

## 4. ex2：使用阻塞处理 RAW 数据相关

### 4.1 ex2 要解决的问题

考虑：

```assembly
addi.w $r1, $r0, 10
add.w  $r2, $r1, $r3
```

第二条指令在 ID 读取 `$r1` 时，第一条可能还在 EXE/MEM，尚未到 WB 写回。如果直接读取寄存器堆，会得到 `$r1` 的旧值，这属于 RAW（Read After Write，写后读）真相关。

本实验为顺序单发射流水线，因此不会发生需要额外处理的 WAW 和 WAR：指令按序进入流水线，写回顺序也不会颠倒。

### 4.2 后三级向 ID 报告待写寄存器

ex2 中三条反馈总线均为 7 位：

```text
valid 1位 + gr_we 1位 + dest 5位 = 7位
```

典型打包逻辑为：

```verilog
assign es_to_ds_bus = {
    es_valid,
    es_gr_we,
    es_dest
};
```

ID 据此知道后三级是否存在尚未写回的目的寄存器。

### 4.3 判断一条指令是否真的使用寄存器

不能只比较指令字段，因为某些指令虽然相应比特碰巧等于某寄存器号，却不一定真的读取该端口。最终版本中的源操作数使用判断位于 `myCPU/ID_stage.v:483-514`：

```verilog
assign src1_is_reg =
    inst_add_w | inst_sub_w | inst_slt | inst_sltu |
    inst_nor   | inst_and   | inst_or  | inst_xor  |
    inst_slli_w | inst_srli_w | inst_srai_w |
    inst_addi_w | inst_ld_w | inst_st_w |
    inst_jirl | inst_beq | inst_bne;

assign src2_is_reg =
    inst_add_w | inst_sub_w | inst_slt | inst_sltu |
    inst_nor   | inst_and   | inst_or  | inst_xor  |
    inst_st_w  | inst_beq   | inst_bne;
```

例如 `addi.w` 使用 `rj` 和立即数，因此只属于 `src1_is_reg`；`add.w` 使用 `rj`、`rk`，两者都为真；`st.w` 既需要地址基址，也需要待写入内存的数据，因此使用两个寄存器源。

### 4.4 ex2 的 RAW 判断

历史版本位置：`ex2-pass:f37267b` 的 `myCPU/ID_stage.v:503-533`。

```verilog
assign es_raw_hazard =
    es_valid_for_ds &&
    es_gr_we_for_ds &&
    (es_dest_for_ds != 5'd0) &&
    (
        (src1_is_reg && (rf_raddr1 == es_dest_for_ds)) ||
        (src2_is_reg && (rf_raddr2 == es_dest_for_ds))
    );

assign ms_raw_hazard =
    ms_valid_for_ds &&
    ms_gr_we_for_ds &&
    (ms_dest_for_ds != 5'd0) &&
    (
        (src1_is_reg && (rf_raddr1 == ms_dest_for_ds)) ||
        (src2_is_reg && (rf_raddr2 == ms_dest_for_ds))
    );

assign ws_raw_hazard =
    ws_valid_for_ds &&
    ws_gr_we_for_ds &&
    (ws_dest_for_ds != 5'd0) &&
    (
        (src1_is_reg && (rf_raddr1 == ws_dest_for_ds)) ||
        (src2_is_reg && (rf_raddr2 == ws_dest_for_ds))
    );

assign raw_hazard =
    ds_valid &&
    (es_raw_hazard || ms_raw_hazard || ws_raw_hazard);
```

判断条件依次保证：

1. 后级中有有效指令；
2. 后级指令会写通用寄存器；
3. 目的寄存器不是恒为零的 `$r0`；
4. ID 当前指令确实使用相应源寄存器；
5. 源寄存器号与后级目的寄存器号相同。

### 4.5 如何实现阻塞

历史版本位置：`ex2-pass:f37267b` 的 `myCPU/ID_stage.v:313-323`。

```verilog
assign ds_ready_go = !raw_hazard;

assign ds_allowin =
       !ds_valid ||
       (ds_ready_go && es_allowin);

assign ds_to_es_valid =
       ds_valid && ds_ready_go;
```

发生 RAW 时 `raw_hazard=1`，于是 `ds_ready_go=0`：

- `ds_to_es_valid=0`：当前相关指令不能进入 EXE，EXE 接收到一个空泡；
- `ds_allowin=0`：ID 不接收 IF 的新指令，保留当前指令；
- IF 因 ID 不允许接收而同步停住；
- EXE/MEM/WB 中更早的指令继续向后流动，直到结果写回寄存器堆。

ex2 保证了正确性，但即使 ALU 结果已经在 EXE 产生，也要继续等到 WB 写回，因此性能较低。

---

## 5. ex3：使用前递处理 RAW 数据相关

### 5.1 前递的基本思想

前递（forward/bypass）不等待结果写回寄存器堆，而是把后级已经产生的结果直接送回 ID：

```text
                ┌──────── EXE result ────────┐
                ├──────── MEM result ────────┤
寄存器堆 ───────┴──────── WB result ─────────┴──→ ID操作数选择
                                                     ↓
                                                    EXE
```

当多个阶段都准备写同一寄存器时，优先选择离 ID 最近的最新指令：

```text
EXE > MEM > WB > 寄存器堆
```

### 5.2 扩展反馈总线

最终宽度位于 `myCPU/mycpu_head.v:22-24`：

```verilog
`define ES_TO_DS_BUS_WD 40
`define MS_TO_DS_BUS_WD 39
`define WS_TO_DS_BUS_WD 39
```

各条总线定义如下：

| 总线 | 字段 | 总宽度 |
|---|---|---:|
| EXE→ID | `valid(1) + res_from_mem(1) + gr_we(1) + dest(5) + alu_result(32)` | 40 |
| MEM→ID | `valid(1) + gr_we(1) + dest(5) + final_result(32)` | 39 |
| WB→ID | `valid(1) + gr_we(1) + dest(5) + final_result(32)` | 39 |

#### EXE→ID

`myCPU/EXE_stage.v:126-133`：

```verilog
assign es_to_ds_bus = {
    es_valid,
    es_res_from_mem,
    es_gr_we,
    es_dest,
    es_alu_result
};
```

`es_res_from_mem` 用于标记加载指令。对 `ld.w` 而言，EXE 的 `es_alu_result` 只是访存地址，不是最终加载数据，因此不能直接前递为操作数。

#### MEM→ID

`myCPU/MEM_stage.v:104-110`：

```verilog
assign ms_to_ds_bus = {
    ms_valid,
    ms_gr_we,
    ms_dest,
    ms_final_result
};
```

MEM 中的 `ms_final_result` 已经在 RAM 返回值和 ALU 结果之间完成选择，可以直接前递。

#### WB→ID

`myCPU/WB_stage.v:98-104`：

```verilog
assign ws_to_ds_bus = {
    ws_valid,
    ws_gr_we,
    ws_dest,
    ws_final_result
};
```

显式 WB 前递可避免依赖寄存器堆“同周期写、同周期读”的具体实现行为。

ID 的拆包位于 `myCPU/ID_stage.v:177-198`，顺序与三个发送端严格一致。

### 5.3 源寄存器匹配

`myCPU/ID_stage.v:518-565` 分别判断两个源寄存器与 EXE/MEM/WB 的匹配关系：

```verilog
assign es_src1_match =
    ds_valid &&
    src1_is_reg &&
    es_valid_for_ds &&
    es_gr_we_for_ds &&
    (es_dest_for_ds != 5'd0) &&
    (rf_raddr1 == es_dest_for_ds);

assign ms_src1_match =
    ds_valid &&
    src1_is_reg &&
    ms_valid_for_ds &&
    ms_gr_we_for_ds &&
    (ms_dest_for_ds != 5'd0) &&
    (rf_raddr1 == ms_dest_for_ds);

assign ws_src1_match =
    ds_valid &&
    src1_is_reg &&
    ws_valid_for_ds &&
    ws_gr_we_for_ds &&
    (ws_dest_for_ds != 5'd0) &&
    (rf_raddr1 == ws_dest_for_ds);
```

源寄存器 2 采用同样结构，只是比较 `rf_raddr2`。这里的 `match` 不只是寄存器号相等，还包含 `ds_valid`、`src_is_reg`、后级 `valid`、`gr_we` 和非零目的寄存器检查，所以表示“ID 确实正在使用后级将写入的寄存器”。

两个源必须独立判断，因为一条双源指令可能从不同阶段取得两个值，例如源 1 来自 EXE、源 2 来自 MEM。

### 5.4 前递优先级选择

`myCPU/ID_stage.v:583-595`：

```verilog
assign rj_value =
    es_src1_match ? es_result_for_ds :
    ms_src1_match ? ms_result_for_ds :
    ws_src1_match ? ws_result_for_ds :
                    rf_rdata1;

assign rkd_value =
    es_src2_match ? es_result_for_ds :
    ms_src2_match ? ms_result_for_ds :
    ws_src2_match ? ws_result_for_ds :
                    rf_rdata2;
```

三目运算符从上到下形成优先级。必须让 EXE 优先于 MEM、MEM 优先于 WB。例如：

```assembly
addi.w $r1, $r0, 1   # 较旧，可能位于 MEM
addi.w $r1, $r1, 1   # 较新，可能位于 EXE，结果为 2
add.w  $r2, $r1, $r0 # 必须取得较新的 2
```

前递选择放在 ID，是因为 `rj_value/rkd_value` 不只供 ALU 使用，还参与：

- `beq/bne` 的比较；
- `jirl` 的目标地址计算；
- `st.w` 的存储数据；
- 送往 EXE 的两个 ALU 操作数。

### 5.5 load-use 冲突仍需停顿

前递不能消除所有停顿。考虑：

```assembly
ld.w  $r1, $r2, 0
add.w $r3, $r1, $r4
```

当 `ld.w` 位于 EXE 时，ALU 只算出了地址，RAM 数据要到 MEM 才可用。因此后一条指令必须等待一拍。

判断逻辑位于 `myCPU/ID_stage.v:567-570`：

```verilog
assign load_use_hazard =
    es_res_from_mem_for_ds &&
    (es_src1_match || es_src2_match);
```

`es_src1_match/es_src2_match` 已经包含“ID 确实使用源寄存器”和有效性检查。若命中 EXE 中的加载目的寄存器，则 `load_use_hazard=1`。

它通过 `myCPU/ID_stage.v:327-336` 控制流水：

```verilog
assign ds_ready_go = !load_use_hazard;

assign ds_allowin =
       !ds_valid ||
       (ds_ready_go && es_allowin);

assign ds_to_es_valid =
       ds_valid && ds_ready_go;
```

逐周期效果：

| 周期 | MEM | EXE | ID | 动作 |
|---|---|---|---|---|
| N | 前序指令 | `ld.w`，只有地址 | 依赖该结果的 `add.w` | `load_use_hazard=1`，ID/IF 保持，EXE 下一拍插入空泡 |
| N+1 | `ld.w`，RAM 数据可用 | 空泡 | 同一条 `add.w` | 从 `ms_result_for_ds` 前递，ID 恢复前进 |
| N+2 | 空泡/后续 | `add.w` | 下一条指令 | 正常流水 |

因此最终策略是：

```text
EXE 普通 ALU 相关 → EXE 前递，不阻塞
MEM 结果相关      → MEM 前递，不阻塞
WB 结果相关       → WB 前递，不阻塞
EXE 加载结果相关  → 阻塞一拍，下一拍从 MEM 前递
无相关            → 使用寄存器堆值
```

---

## 6. 从单周期到五级流水的本质

Verilog 不是像 C/Java 那样逐行顺序执行的软件程序。硬件中的连续赋值和组合逻辑始终并行响应输入变化，`always @(posedge clk)` 描述触发器在时钟上升沿更新状态。

把单周期 CPU 变为五级流水的关键是：

1. 按 IF、ID、EXE、MEM、WB 划分组合逻辑；
2. 在级间加入寄存器保存数据和控制信号；
3. 用 `valid` 表示每级是否有有效指令；
4. 用 `ready_go/allowin` 决定级间何时传递；
5. 因为每一级都有独立级间寄存器，所以同一时刻可以容纳多条不同指令。

稳态流水示例：

| 时钟周期 | IF | ID | EXE | MEM | WB |
|---|---|---|---|---|---|
| 1 | I1 |  |  |  |  |
| 2 | I2 | I1 |  |  |  |
| 3 | I3 | I2 | I1 |  |  |
| 4 | I4 | I3 | I2 | I1 |  |
| 5 | I5 | I4 | I3 | I2 | I1 |
| 6 | I6 | I5 | I4 | I3 | I2 |

流水线不能降低单条指令经过五级所需的阶段数，但在理想稳态下可以做到每周期完成一条指令，提高吞吐率和硬件利用率。

---

## 7. 验证方法与结果判定

### 7.1 测试流程

1. 将对应 `exN_obj` 的文件复制到 `mycpu_env/func/obj`；
2. 打开 `gettrace/gettrace.xpr`，执行 `run all` 生成该测试对应的 `golden_trace.txt`；
3. 打开 `soc_verify/soc_bram/run_vivado/project/loongson.xpr`；
4. 运行 Behavioral Simulation；
5. Tcl Console 输入 `run all`；
6. 测试平台逐条比较参考 trace 与 CPU 的写回信息。

比较的四项通常为：

```text
写回有效标记、写回 PC、目的寄存器号、写回数据
```

它们对应 WB 输出的：

```verilog
debug_wb_pc
debug_wb_rf_we
debug_wb_rf_wnum
debug_wb_rf_wdata
```

### 7.2 通过标准

最终出现以下输出才算完整通过：

```text
Number 8'd01 Functional Test Point PASS!!!
...
Number 8'd20 Functional Test Point PASS!!!
Test end!
----PASS!!!
```

`launch_simulation` 成功只表示仿真器成功启动，不代表 CPU 功能正确；必须以最终 trace 比对结果为准。

### 7.3 Git 保存点

| 阶段 | 标签 | 提交 |
|---|---|---|
| 原始单周期 CPU | 无 | `2530556` |
| ex1 通过 | `ex1-pass` | `c5a6bc3` |
| ex2 通过 | `ex2-pass` | `f37267b` |
| ex3 通过 | `ex3-pass` | `e3410f8` |

验收时可以使用以下命令查看不同版本：

```powershell
git show ex2-pass:myCPU/ID_stage.v
git diff ex2-pass ex3-pass -- myCPU
git log --oneline --decorate
```

---

## 8. 常见验收问题简答

### 8.1 `gr_we` 是什么？

`gr_we` 是 General Register Write Enable，即通用寄存器写使能。它表示该指令最终是否需要修改通用寄存器。`add.w`、`ld.w` 为 1，`st.w`、普通分支指令为 0。

### 8.2 为什么所有指令都经过 MEM，但有些不访问 RAM？

MEM 首先是流水级的位置，不代表每条指令都必须使用存储器。ALU 指令在 MEM 只传递 ALU 结果；`ld.w/st.w` 才真正访问数据 RAM。

### 8.3 为什么 `$r0` 不参与相关判断？

LA32 的 `$r0` 恒为 0，对它的写入没有体系结构效果。若不排除 `$r0`，可能产生无意义的阻塞或前递。

### 8.4 ex2 和 ex3 的核心区别是什么？

ex2 解决“读到旧数据”的正确性问题，方法是等待结果写回；ex3 解决“等待太久”的性能问题，方法是直接前递已经产生的结果。

### 8.5 为什么前递优先级是 EXE > MEM > WB？

在顺序流水线中，EXE 的指令比 MEM/WB 中的指令更新。若多条连续指令写同一寄存器，ID 必须取得程序顺序上最近一次写入的结果。

### 8.6 为什么 `ld.w` 后紧跟使用仍要停一拍？

加载指令在 EXE 只计算地址，真正的数据在 MEM 访问 RAM 后才产生。EXE 没有可前递的加载结果，因此依赖指令必须等待一拍。

### 8.7 阻塞时各级发生什么？

ID 的 `ready_go` 变为 0，导致 ID 保持当前指令、IF 也保持，ID 不向 EXE 声明有效指令，因此 EXE 插入空泡；更后面的旧指令继续流动。

### 8.8 `valid` 和总线数据是什么关系？

总线中可能残留旧值，但只有 `valid=1` 时这些数据才代表真实指令。清空流水线通常只需把对应 `valid` 置 0，而不必把所有数据位清零。

### 8.9 为什么分支判断也需要前递值？

`beq/bne` 在 ID 比较 `rj_value` 和 `rkd_value`，`jirl` 在 ID 使用 `rj_value` 计算目标地址。如果只在 EXE 前递，ID 仍可能根据旧值作出错误跳转，因此本设计在 ID 统一选择前递数据。

---

## 9. 总结

本实验完成了从单周期 LA32 CPU 到可处理数据相关的五级流水 CPU 的演进：

1. ex1 通过级间缓存和握手机制建立 IF/ID/EXE/MEM/WB 五级流水；
2. ex2 检测 ID 源寄存器与 EXE/MEM/WB 目的寄存器之间的 RAW 相关，并用阻塞保证正确性；
3. ex3 将后三级结果前递到 ID，按照 `EXE > MEM > WB > RF` 选择最新值，仅为 load-use 冲突保留一拍停顿；
4. 最终 ex3 通过全部功能测试，并将仿真结束时间从 ex2 的约 1322000 ns 降至 604465 ns。

设计的关键不只是“把代码拆成五个文件”，而是利用级间寄存器和 `valid/ready_go/allowin` 构造可暂停、可传递、可插入空泡的流水数据通路，再通过阻塞和前递保证相关指令的正确执行。
