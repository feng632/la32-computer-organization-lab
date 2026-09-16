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
    input  wire [`WS_TO_RF_BUS_WD-1:0]  ws_to_rf_bus
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

    // 第一章暂不考虑冲突，ID级总能在一个周期内完成
    assign ds_ready_go = 1'b1;

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

    /*
     * 当前只是ID级外壳，具体译码逻辑下一步加入。
     * 暂时将输出置零，避免输出悬空。
     */
    assign ds_to_es_bus = {`DS_TO_ES_BUS_WD{1'b0}};
    assign br_bus       = {`BR_BUS_WD{1'b0}};

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
    wire inst_xor;
    wire inst_slli_w;
    wire inst_srli_w;
    wire inst_srai_w;
    wire inst_addi_w;
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

    // 立即数和分支偏移
    wire [31:0] imm;
    wire [31:0] br_offs;
    wire [31:0] jirl_offs;

    // ALU操作类型
    assign alu_op[0] =
        inst_add_w  |
        inst_addi_w |
        inst_ld_w   |
        inst_st_w   |
        inst_jirl   |
        inst_bl;

    assign alu_op[1]  = inst_sub_w;
    assign alu_op[2]  = inst_slt;
    assign alu_op[3]  = inst_sltu;
    assign alu_op[4]  = inst_and;
    assign alu_op[5]  = inst_nor;
    assign alu_op[6]  = inst_or;
    assign alu_op[7]  = inst_xor;
    assign alu_op[8]  = inst_slli_w;
    assign alu_op[9]  = inst_srli_w;
    assign alu_op[10] = inst_srai_w;
    assign alu_op[11] = inst_lu12i_w;

    assign need_ui5 =
       inst_slli_w |
       inst_srli_w |
       inst_srai_w;

    assign need_si12 =
        inst_addi_w |
        inst_ld_w   |
        inst_st_w;

    assign need_si16 =
        inst_jirl |
        inst_beq  |
        inst_bne;

    assign need_si20 =
        inst_lu12i_w;

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

    // jirl和bl的ALU第一个操作数是PC
    assign src1_is_pc =
        inst_jirl |
        inst_bl;

    // 以下指令的ALU第二个操作数使用立即数
    assign src2_is_imm =
        inst_slli_w  |
        inst_srli_w  |
        inst_srai_w  |
        inst_addi_w  |
        inst_ld_w    |
        inst_st_w    |
        inst_lu12i_w |
        inst_jirl    |
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

endmodule