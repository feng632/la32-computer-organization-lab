`include "mycpu_head.v"

module ID_stage(
    input  wire                         clk,
    input  wire                         reset,

    // EXE级是否允许接收
    input  wire                         es_allowin,

    // 告诉IF级：ID是否允许接收
    output wire                         ds_allowin,

    // 来自IF级
    input  wire                         fs_to_ds_valid,
    input  wire [`FS_TO_DS_BUS_WD-1:0]  fs_to_ds_bus,

    // 发送给EXE级
    output wire                         ds_to_es_valid,
    output wire [`DS_TO_ES_BUS_WD-1:0]  ds_to_es_bus,

    // 发送给IF级的分支信息
    output wire [`BR_BUS_WD-1:0]        br_bus,

    // 来自WB级的寄存器写回信息
    input  wire [`WS_TO_RF_BUS_WD-1:0]  ws_to_rf_bus,

    // 后三级的待写寄存器信息，用于检测数据相关
    input wire [`ES_TO_DS_BUS_WD-1:0] es_to_ds_bus,
    input wire [`MS_TO_DS_BUS_WD-1:0] ms_to_ds_bus,
    input wire [`WS_TO_DS_BUS_WD-1:0] ws_to_ds_bus
);

    // ID级的有效位
    reg  ds_valid;

    // 当前ID级是否完成工作
    wire ds_ready_go;

    // 保存IF传来的总线
    reg [`FS_TO_DS_BUS_WD-1:0] fs_to_ds_bus_r;

    // ID级当前使用的指令和PC
    wire [31:0] ds_inst;
    wire [31:0] ds_pc;

    // 指令中的各字段
    wire [ 5:0] op_31_26;
    wire [ 3:0] op_25_22;
    wire [ 1:0] op_21_20;
    wire [ 4:0] op_19_15;

    wire [ 4:0] rd;
    wire [ 4:0] rj;
    wire [ 4:0] rk;

    wire [11:0] i12;
    wire [19:0] i20;
    wire [15:0] i16;
    wire [25:0] i26;

    // 译码器输出
    wire [63:0] op_31_26_d;
    wire [15:0] op_25_22_d;
    wire [ 3:0] op_21_20_d;
    wire [31:0] op_19_15_d;

    // 当前指令类型
    wire inst_add_w;
    wire inst_sub_w;
    wire inst_slt;
    wire inst_sltu;
    wire inst_nor;
    wire inst_and;
    wire inst_or;
    wire inst_ori;
    wire inst_xor;
    wire inst_slli_w;
    wire inst_sll_w;
    wire inst_srli_w;
    wire inst_srl_w;
    wire inst_srai_w;
    wire inst_sra_w;
    wire inst_addi_w;
    wire inst_slti;
    wire inst_sltui;
    wire inst_andi;
    wire inst_xori;
    wire inst_pcaddu12i;

    wire inst_ld_w;
    wire inst_st_w;
    wire inst_jirl;
    wire inst_b;
    wire inst_bl;
    wire inst_beq;
    wire inst_bne;
    wire inst_lu12i_w;

    // ALU控制信号
    wire [11:0] alu_op;

    // 立即数类型
    wire need_ui5;
    wire need_si12;
    wire need_si16;
    wire need_si20;
    wire need_si26;
    wire need_ui12;

    // 操作数选择
    wire src1_is_pc;
    wire src2_is_imm;
    wire src2_is_4;
    wire src_reg_is_rd;

    // 访存和写回控制
    wire res_from_mem;
    wire gr_we;
    wire mem_we;
    wire dst_is_r1;

    // 目的寄存器
    wire [4:0] dest;

    // 寄存器堆读端口
    wire [ 4:0] rf_raddr1;
    wire [31:0] rf_rdata1;
    wire [ 4:0] rf_raddr2;
    wire [31:0] rf_rdata2;

    // 寄存器堆写端口，来自WB级
    wire        rf_we;
    wire [ 4:0] rf_waddr;
    wire [31:0] rf_wdata;

    // ID级读出的两个源操作数
    wire [31:0] rj_value;
    wire [31:0] rkd_value;

    // 立即数和分支偏移
    wire [31:0] imm;
    wire [31:0] br_offs;
    wire [31:0] jirl_offs;

    // 分支判断
    wire        rj_eq_rkd;
    wire        br_taken;
    wire [31:0] br_target;

    // 送往EXE的两个ALU操作数
    wire [31:0] alu_src1;
    wire [31:0] alu_src2;

    // EXE级反馈给ID的信息
    wire        es_valid_for_ds;
    wire        es_res_from_mem_for_ds;
    wire        es_gr_we_for_ds;
    wire [ 4:0] es_dest_for_ds;
    wire [31:0] es_result_for_ds;

    // MEM级反馈给ID的信息
    wire        ms_valid_for_ds;
    wire        ms_gr_we_for_ds;
    wire [ 4:0] ms_dest_for_ds;
    wire [31:0] ms_result_for_ds;

    // WB级反馈给ID的信息
    wire        ws_valid_for_ds;
    wire        ws_gr_we_for_ds;
    wire [ 4:0] ws_dest_for_ds;
    wire [31:0] ws_result_for_ds;

    // 当前ID指令是否真正使用两个寄存器读端口
    wire src1_is_reg;
    wire src2_is_reg;

    // 两个源寄存器与EXE、MEM、WB目的寄存器的匹配结果
    wire es_src1_match;
    wire es_src2_match;
    wire ms_src1_match;
    wire ms_src2_match;
    wire ws_src1_match;
    wire ws_src2_match;

    // EXE中的加载指令与ID之间的数据相关
    wire load_use_hazard;

    // 拆出EXE、MEM、WB反馈给ID的信息
    assign {
        es_valid_for_ds,
        es_res_from_mem_for_ds,
        es_gr_we_for_ds,
        es_dest_for_ds,
        es_result_for_ds
    } = es_to_ds_bus;

    assign {
        ms_valid_for_ds,
        ms_gr_we_for_ds,
        ms_dest_for_ds,
        ms_result_for_ds
    } = ms_to_ds_bus;

    assign {
        ws_valid_for_ds,
        ws_gr_we_for_ds,
        ws_dest_for_ds,
        ws_result_for_ds
    } = ws_to_ds_bus;

    // 从IF传来的64位总线中拆出指令和PC
    assign {ds_inst, ds_pc} = fs_to_ds_bus_r;

    // 拆分指令编码字段
    assign op_31_26 = ds_inst[31:26];
    assign op_25_22 = ds_inst[25:22];
    assign op_21_20 = ds_inst[21:20];
    assign op_19_15 = ds_inst[19:15];

    assign rd = ds_inst[4:0];
    assign rj = ds_inst[9:5];
    assign rk = ds_inst[14:10];

    assign i12 = ds_inst[21:10];
    assign i20 = ds_inst[24:5];
    assign i16 = ds_inst[25:10];
    assign i26 = {ds_inst[9:0], ds_inst[25:10]};

    decoder_6_64 u_dec0(
    .in  (op_31_26),
    .out (op_31_26_d)
    );

    decoder_4_16 u_dec1(
        .in  (op_25_22),
        .out (op_25_22_d)
    );

    decoder_2_4 u_dec2(
        .in  (op_21_20),
        .out (op_21_20_d)
    );

    decoder_5_32 u_dec3(
        .in  (op_19_15),
        .out (op_19_15_d)
    );

    assign inst_add_w =
       op_31_26_d[6'h00] &&
       op_25_22_d[4'h0]  &&
       op_21_20_d[2'h1]  &&
       op_19_15_d[5'h00];

    // slti译码
    assign inst_slti =
        op_31_26_d[6'h00] &&
        op_25_22_d[4'h8];

    assign inst_sltui =
        op_31_26_d[6'h00] &&
        op_25_22_d[4'h9];

    // andi译码
    assign inst_andi =
        op_31_26_d[6'h00] &&
        op_25_22_d[4'hd];
    // ori译码
    assign inst_ori =
        op_31_26_d[6'h00] &&
        op_25_22_d[4'he];

    // xori译码
    assign inst_xori =
        op_31_26_d[6'h00] &&
        op_25_22_d[4'hf];

    // sll.w译码
    assign inst_sll_w =
        op_31_26_d[6'h00] &&
        op_25_22_d[4'h0]  &&
        op_21_20_d[2'h1]  &&
        op_19_15_d[5'h0e];

    // srl.w译码
    assign inst_srl_w =
        op_31_26_d[6'h00] &&
        op_25_22_d[4'h0]  &&
        op_21_20_d[2'h1]  &&
        op_19_15_d[5'h0f];

    // sra.w译码
    assign inst_sra_w =
        op_31_26_d[6'h00] &&
        op_25_22_d[4'h0]  &&
        op_21_20_d[2'h1]  &&
        op_19_15_d[5'h10];

    // pcaddu12i译码
    assign inst_pcaddu12i =
        op_31_26_d[6'h07] &&
        !ds_inst[25];

    assign inst_sub_w =
        op_31_26_d[6'h00] &&
        op_25_22_d[4'h0]  &&
        op_21_20_d[2'h1]  &&
        op_19_15_d[5'h02];

    assign inst_slt =
        op_31_26_d[6'h00] &&
        op_25_22_d[4'h0]  &&
        op_21_20_d[2'h1]  &&
        op_19_15_d[5'h04];

    assign inst_sltu =
        op_31_26_d[6'h00] &&
        op_25_22_d[4'h0]  &&
        op_21_20_d[2'h1]  &&
        op_19_15_d[5'h05];

    assign inst_nor =
        op_31_26_d[6'h00] &&
        op_25_22_d[4'h0]  &&
        op_21_20_d[2'h1]  &&
        op_19_15_d[5'h08];

    assign inst_and =
        op_31_26_d[6'h00] &&
        op_25_22_d[4'h0]  &&
        op_21_20_d[2'h1]  &&
        op_19_15_d[5'h09];

    assign inst_or =
        op_31_26_d[6'h00] &&
        op_25_22_d[4'h0]  &&
        op_21_20_d[2'h1]  &&
        op_19_15_d[5'h0a];

    assign inst_xor =
        op_31_26_d[6'h00] &&
        op_25_22_d[4'h0]  &&
        op_21_20_d[2'h1]  &&
        op_19_15_d[5'h0b];

    assign inst_slli_w =
        op_31_26_d[6'h00] &&
        op_25_22_d[4'h1]  &&
        op_21_20_d[2'h0]  &&
        op_19_15_d[5'h01];

    assign inst_srli_w =
        op_31_26_d[6'h00] &&
        op_25_22_d[4'h1]  &&
        op_21_20_d[2'h0]  &&
        op_19_15_d[5'h09];

    assign inst_srai_w =
        op_31_26_d[6'h00] &&
        op_25_22_d[4'h1]  &&
        op_21_20_d[2'h0]  &&
        op_19_15_d[5'h11];

    assign inst_addi_w =
        op_31_26_d[6'h00] &&
        op_25_22_d[4'ha];

    assign inst_ld_w =
        op_31_26_d[6'h0a] &&
        op_25_22_d[4'h2];

    assign inst_st_w =
        op_31_26_d[6'h0a] &&
        op_25_22_d[4'h6];

    assign inst_jirl = op_31_26_d[6'h13];
    assign inst_b    = op_31_26_d[6'h14];
    assign inst_bl   = op_31_26_d[6'h15];
    assign inst_beq  = op_31_26_d[6'h16];
    assign inst_bne  = op_31_26_d[6'h17];

    assign inst_lu12i_w =
        op_31_26_d[6'h05] &&
        !ds_inst[25];

    // 只有EXE中的加载结果尚未返回时，ID才阻塞
    assign ds_ready_go = !load_use_hazard;

    // ID为空，或者当前指令可以送给EXE时，允许IF送入新指令
    assign ds_allowin =
           !ds_valid ||
           (ds_ready_go && es_allowin);

    // ID中有有效指令，并且译码工作完成
    assign ds_to_es_valid =
           ds_valid && ds_ready_go;

    // 维护ID级有效位
    always @(posedge clk) begin
        if (reset) begin
            ds_valid <= 1'b0;
        end
        else if (ds_allowin) begin
            ds_valid <= fs_to_ds_valid;
        end
    end

    // 保存IF级传来的指令和PC
    always @(posedge clk) begin
        if (fs_to_ds_valid && ds_allowin) begin
            fs_to_ds_bus_r <= fs_to_ds_bus;
        end
    end

    // 将ID级控制信息和操作数打包送往EXE级
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
    
    assign br_bus = {br_taken, br_target};

    // ALU操作类型
    assign alu_op[0] =
        inst_add_w      |
        inst_addi_w     |
        inst_ld_w       |
        inst_st_w       |
        inst_pcaddu12i  |
        inst_jirl       |
        inst_bl;

    assign alu_op[1]  = inst_sub_w;
    assign alu_op[2] =
            inst_slt |
            inst_slti;
    assign alu_op[3] =
            inst_sltu |
            inst_sltui;
    assign alu_op[4] =
            inst_and |
            inst_andi;
    assign alu_op[5]  = inst_nor;
    assign alu_op[6] =
            inst_or |
            inst_ori;
    assign alu_op[7] =
            inst_xor |
            inst_xori;
    assign alu_op[8] =
        inst_sll_w |
        inst_slli_w;
    assign alu_op[9] =
        inst_srl_w |
        inst_srli_w;
    assign alu_op[10] =
        inst_sra_w |
        inst_srai_w;
    assign alu_op[11] = inst_lu12i_w;

    assign need_ui12 =
        inst_andi |
        inst_ori  |
        inst_xori;

    assign need_ui5 =
       inst_slli_w |
       inst_srli_w |
       inst_srai_w;

    assign need_si12 =
        inst_addi_w |
        inst_slti   |
        inst_ld_w   |
        inst_sltui  |
        inst_st_w;

    assign need_si16 =
        inst_jirl |
        inst_beq  |
        inst_bne;

    assign need_si20 =
        inst_lu12i_w |
        inst_pcaddu12i;

    assign need_si26 =
        inst_b |
        inst_bl;

    assign src2_is_4 =
        inst_jirl |
        inst_bl;

    assign imm =
        src2_is_4 ? 32'd4 :
        need_si20 ? {i20, 12'b0} :
        need_ui5  ? {27'b0, rk} :
        need_ui12 ? {20'b0, i12} :
                    {{20{i12[11]}}, i12};

    assign br_offs =
       need_si26
       ? {{4{i26[25]}}, i26, 2'b0}
       : {{14{i16[15]}}, i16, 2'b0};

    assign jirl_offs =
        {{14{i16[15]}}, i16, 2'b0};

    // beq、bne和st.w的第二个寄存器号位于rd字段
    assign src_reg_is_rd =
        inst_beq |
        inst_bne |
        inst_st_w;

    // jirl、bl和pcaddu12i的ALU第一个操作数是PC
    assign src1_is_pc =
        inst_jirl |
        inst_bl   |
        inst_pcaddu12i;

    // 以下指令的ALU第二个操作数使用立即数
    assign src2_is_imm =
        inst_slli_w  |
        inst_srli_w  |
        inst_srai_w  |
        inst_addi_w  |
        inst_slti    |
        inst_sltui   |
        inst_andi    |
        inst_ori     |
        inst_xori    |
        inst_ld_w    |
        inst_st_w    |
        inst_lu12i_w |
        inst_jirl    |
        inst_pcaddu12i |
        inst_bl;

    // ld.w最终写回的是内存数据
    assign res_from_mem = inst_ld_w;

    // bl固定写入1号寄存器
    assign dst_is_r1 = inst_bl;

    // 这些指令不写通用寄存器，其余已实现指令需要写
    assign gr_we =
        !inst_st_w &&
        !inst_beq  &&
        !inst_bne  &&
        !inst_b;

    // st.w需要写数据RAM
    assign mem_we = inst_st_w;

    // bl写r1，其余写rd
    assign dest = dst_is_r1 ? 5'd1 : rd;

    // WB级送回：写使能、目标寄存器号、写回数据
    assign {rf_we, rf_waddr, rf_wdata} = ws_to_rf_bus;

    // 第一个源寄存器始终由rj字段指定
    assign rf_raddr1 = rj;

    // 大多数指令使用rk；beq、bne和st.w使用rd字段
    assign rf_raddr2 = src_reg_is_rd ? rd : rk;

    // 使用rj作为源操作数的指令
    assign src1_is_reg =
        inst_add_w   |
        inst_sub_w   |
        inst_slt     |
        inst_slti    |
        inst_sltui   |
        inst_sltu    |
        inst_nor     |
        inst_and     |
        inst_andi    |
        inst_or      |
        inst_ori     |
        inst_xor     |
        inst_xori    |
        inst_slli_w  |
        inst_sll_w   |
        inst_srli_w  |
        inst_srl_w   |
        inst_srai_w  |
        inst_sra_w   |
        inst_addi_w  |
        inst_ld_w    |
        inst_st_w    |
        inst_jirl    |
        inst_beq     |
        inst_bne;

    // 使用第二个寄存器操作数的指令
    assign src2_is_reg =
        inst_add_w |
        inst_sub_w |
        inst_slt   |
        inst_sltu  |
        inst_sll_w |
        inst_srl_w |
        inst_sra_w |
        inst_nor   |
        inst_and   |
        inst_or    |
        inst_xor   |
        inst_st_w  |
        inst_beq   |
        inst_bne;


    // 源寄存器1与后三级目的寄存器匹配
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

    // 源寄存器2与后三级目的寄存器匹配
    assign es_src2_match =
        ds_valid &&
        src2_is_reg &&
        es_valid_for_ds &&
        es_gr_we_for_ds &&
        (es_dest_for_ds != 5'd0) &&
        (rf_raddr2 == es_dest_for_ds);

    assign ms_src2_match =
        ds_valid &&
        src2_is_reg &&
        ms_valid_for_ds &&
        ms_gr_we_for_ds &&
        (ms_dest_for_ds != 5'd0) &&
        (rf_raddr2 == ms_dest_for_ds);

    assign ws_src2_match =
        ds_valid &&
        src2_is_reg &&
        ws_valid_for_ds &&
        ws_gr_we_for_ds &&
        (ws_dest_for_ds != 5'd0) &&
        (rf_raddr2 == ws_dest_for_ds);

    // EXE中是加载指令，并且其目的寄存器被ID使用时，需要阻塞一拍
    assign load_use_hazard =
        es_res_from_mem_for_ds &&
        (es_src1_match || es_src2_match);

    regfile u_regfile(
    .clk    (clk),
    .raddr1 (rf_raddr1),
    .rdata1 (rf_rdata1),
    .raddr2 (rf_raddr2),
    .rdata2 (rf_rdata2),
    .we     (rf_we),
    .waddr  (rf_waddr),
    .wdata  (rf_wdata)
);

    // 为源寄存器1选择最新的数据
    assign rj_value =
        es_src1_match ? es_result_for_ds :
        ms_src1_match ? ms_result_for_ds :
        ws_src1_match ? ws_result_for_ds :
                        rf_rdata1;

    // 为源寄存器2选择最新的数据
    assign rkd_value =
        es_src2_match ? es_result_for_ds :
        ms_src2_match ? ms_result_for_ds :
        ws_src2_match ? ws_result_for_ds :
                        rf_rdata2;



    // 判断两个源寄存器的值是否相等
    assign rj_eq_rkd = (rj_value == rkd_value);

    assign br_taken =
       (
           (inst_beq &&  rj_eq_rkd) ||
           (inst_bne && !rj_eq_rkd) ||
           inst_jirl ||
           inst_bl   ||
           inst_b
       ) && ds_valid && ds_ready_go;

    //两类目标地址的计算方法
    assign br_target =
       (inst_beq || inst_bne || inst_bl || inst_b)
       ? ds_pc + br_offs
       : rj_value + jirl_offs;

    //选择两个操作数
    assign alu_src1 =
       src1_is_pc ? ds_pc : rj_value;

    assign alu_src2 =
       src2_is_imm ? imm : rkd_value;

endmodule
