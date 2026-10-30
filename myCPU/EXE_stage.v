`include "mycpu_head.v"

module EXE_stage(
    input  wire                         clk,
    input  wire                         reset,
    input wire                          pipe_flush,
    input wire                          ms_ex_pending,
    input wire [63:0]                   counter_value,

    // MEM级是否允许接收
    input  wire                         ms_allowin,

    // 告诉ID级：EXE是否允许接收
    output wire                         es_allowin,

    // 来自ID级
    input  wire                         ds_to_es_valid,
    input  wire [`DS_TO_ES_BUS_WD-1:0]  ds_to_es_bus,
    input wire [`PIPE_META_WD-1:0] ds_to_es_meta,

    // 发送给MEM级
    output wire                         es_to_ms_valid,
    output wire [`ES_TO_MS_BUS_WD-1:0]  es_to_ms_bus,
    output wire [`PIPE_META_WD-1:0] es_to_ms_meta,

    // 送回ID级，用于数据相关判断
    output wire [`ES_TO_DS_BUS_WD-1:0] es_to_ds_bus,

    output wire es_valid_for_ctrl,
    output wire es_serializing,

    // 数据RAM接口
    output wire                         data_sram_en,
    output wire [3:0]                   data_sram_we,
    output wire [31:0]                  data_sram_addr,
    output wire [31:0]                  data_sram_wdata
);

    // EXE级握手信号
    reg  es_valid;
    wire es_ready_go;

    wire es_exc_valid;
    wire es_mem_req_ok;

    wire es_half_access;
    wire es_word_access;
    wire es_ale;

    wire [`EXC_BUS_WD-1:0] es_exc;

    wire [1:0]  es_cnt_op;
    wire [31:0] es_cnt_value;

    // 保存ID级传来的总线
    reg [`DS_TO_ES_BUS_WD-1:0] ds_to_es_bus_r;

    reg [`PIPE_META_WD-1:0] ds_to_es_meta_r;

    // 从ID级总线中拆出的信号
    wire [11:0] es_alu_op;
    wire        es_gr_we;
    wire        es_mem_we;
    wire [ 4:0] es_dest;
    //ex6
    wire es_store_is_byte;
    wire es_store_is_half;
    wire es_load_is_byte;
    wire es_load_unsigned;
    wire es_load_is_half;

    //ex7
    wire es_inst_mul_w;
    wire es_inst_mulh_w;
    wire es_inst_mulh_wu;
    wire es_inst_div_w;
    wire es_inst_mod_w;
    wire es_inst_div_wu;
    wire es_inst_mod_wu;

    // 有符号除法器接口
    wire        div_signed_req;
    wire        div_signed_out_valid;
    wire [63:0] div_signed_out_data;


    // 无符号除法器接口
    wire        div_unsigned_req;
    wire        div_unsigned_out_valid;
    wire [63:0] div_unsigned_out_data;

    // 当前无符号除法的状态及保存结果
    reg         div_unsigned_sent;
    reg         div_unsigned_done;
    reg  [63:0] div_unsigned_result;

    // 当前EXE指令是否已经向有符号除法器发送请求
    reg div_signed_sent;

    // 当前除法是否已经完成
    reg div_signed_done;

    // 保存商和余数
    reg [63:0] div_signed_result;


    // 两个除法器共用的复位恢复控制
    localparam DIV_RESET_HOLD = 2'd0;
    localparam DIV_RECOVER    = 2'd1;
    localparam DIV_RUN        = 2'd2;

    reg [1:0] div_state;
    reg       div_hold_count;

    wire div_ip_aresetn;
    wire div_can_run;

    assign div_ip_aresetn =
        !reset && !pipe_flush &&
        (div_state != DIV_RESET_HOLD);

    assign div_can_run =
        !reset && !pipe_flush &&
        (div_state == DIV_RUN);

    always @(posedge clk) begin
        if (reset || pipe_flush) begin
            div_state      <= DIV_RESET_HOLD;
            div_hold_count <= 1'b0;
        end
        else begin
            case (div_state)
                DIV_RESET_HOLD: begin
                    if (div_hold_count) begin
                        div_state <= DIV_RECOVER;
                    end
                    else begin
                        div_hold_count <= 1'b1;
                    end
                end

                DIV_RECOVER: begin
                    div_state <= DIV_RUN;
                end

                DIV_RUN: begin
                    div_state <= DIV_RUN;
                end

                default: begin
                    div_state      <= DIV_RESET_HOLD;
                    div_hold_count <= 1'b0;
                end
            endcase
        end
    end

    always @(posedge clk) begin
        if (reset || pipe_flush || !div_can_run) begin
            div_signed_done   <= 1'b0;
            div_signed_result <= 64'b0;
        end
        else if (es_allowin) begin
            div_signed_done <= 1'b0;
        end
        else if (div_signed_out_valid &&
                     div_can_run &&
                     div_signed_sent && !div_signed_done &&
                     es_valid && !es_exc_valid &&
                     (es_inst_div_w || es_inst_mod_w)) begin
            div_signed_done   <= 1'b1;
            div_signed_result <= div_signed_out_data;
        end
    end

    always @(posedge clk) begin
        if (reset || pipe_flush || !div_can_run) begin
            div_unsigned_done   <= 1'b0;
            div_unsigned_result <= 64'b0;
        end
        else if (es_allowin) begin
            div_unsigned_done <= 1'b0;
        end
        else if (div_unsigned_out_valid &&
                     div_can_run &&
                     div_unsigned_sent && !div_unsigned_done &&
                     es_valid && !es_exc_valid &&
                     (es_inst_div_wu || es_inst_mod_wu)) begin
            div_unsigned_done   <= 1'b1;
            div_unsigned_result <= div_unsigned_out_data;
        end
    end

    assign div_signed_req =
        div_can_run &&
        es_valid &&
        (es_inst_div_w || es_inst_mod_w) &&
        !div_signed_sent &&
        !reset && !pipe_flush &&
        !es_exc_valid && !ms_ex_pending;

    assign div_unsigned_req =
        div_can_run &&
        es_valid &&
        (es_inst_div_wu || es_inst_mod_wu) &&
        !div_unsigned_sent &&
        !reset && !pipe_flush &&
        !es_exc_valid && !ms_ex_pending;

    always @(posedge clk) begin
        if (reset || pipe_flush || !div_can_run) begin
            div_signed_sent <= 1'b0;
        end
        else if (es_allowin) begin
            div_signed_sent <= 1'b0;
        end
        else if (div_signed_req) begin
            div_signed_sent <= 1'b1;
        end
    end

    always @(posedge clk) begin
        if (reset || pipe_flush || !div_can_run) begin
            div_unsigned_sent <= 1'b0;
        end
        else if (es_allowin) begin
            div_unsigned_sent <= 1'b0;
        end
        else if (div_unsigned_req) begin
            div_unsigned_sent <= 1'b1;
        end
    end


    wire [31:0] es_alu_src1;
    wire [31:0] es_alu_src2;
    wire [31:0] es_rkd_value;
    wire [31:0] es_pc;
    wire        es_res_from_mem;

    // ALU计算结果
    wire [31:0] es_alu_result;

    // 两个32位操作数相乘，保存完整64位乘积
    wire [63:0] es_mul_result;
    // EXE级选择后的执行结果
    wire [31:0] es_result;

    wire signed [63:0] es_mul_signed_result;

    assign es_mul_signed_result =
        $signed(es_alu_src1) * $signed(es_alu_src2);

    assign es_mul_result = es_alu_src1 * es_alu_src2;
    assign es_result =
        es_inst_mul_w
        ? es_mul_result[31:0]
        : es_inst_mulh_w
        ? es_mul_signed_result[63:32]
        : es_inst_mulh_wu
        ? es_mul_result[63:32]
        : es_inst_div_w
        ? div_signed_result[63:32]
        : es_inst_mod_w
        ? div_signed_result[31:0]
        : es_inst_div_wu
        ? div_unsigned_result[63:32]
        : es_inst_mod_wu
        ? div_unsigned_result[31:0]
        : es_alu_result;


    wire [3:0] es_store_we;

    // ID打包的顺序必须和这里的拆包顺序完全一致
    assign {
        es_alu_op,
        es_gr_we,
        es_mem_we,
        es_store_is_byte,
        es_store_is_half,
        es_dest,
        es_alu_src1,
        es_alu_src2,
        es_rkd_value,
        es_pc,
        es_res_from_mem,
        es_load_is_byte,
        es_load_unsigned,
        es_load_is_half,
        es_inst_mul_w,
        es_inst_mulh_w,
        es_inst_mulh_wu,
        es_inst_div_w,
        es_inst_mod_w,
        es_inst_div_wu,
        es_inst_mod_wu
    } = ds_to_es_bus_r;

    assign es_store_we =
        es_store_is_byte
        ? (4'b0001 << es_alu_result[1:0])
        : es_store_is_half
        ? (es_alu_result[1] ? 4'b1100 : 4'b0011)
        : 4'b1111;

    // 除法等待结果，其他指令本级直接完成
     assign es_ready_go =
        es_exc_valid
        ? 1'b1
        : (es_inst_div_w || es_inst_mod_w)
        ? div_signed_done
        : (es_inst_div_wu || es_inst_mod_wu)
        ? div_unsigned_done
        : 1'b1;

    // EXE为空，或者当前指令能够进入MEM
    assign es_allowin =
           !es_valid ||
           (es_ready_go && ms_allowin);

    // EXE有有效指令，并且执行完成
    assign es_to_ms_valid =
           es_valid && es_ready_go && !pipe_flush;

    // 维护EXE级有效位
    always @(posedge clk) begin
        if (reset) begin
            es_valid <= 1'b0;
        end
        else if (pipe_flush) begin
            es_valid <= 1'b0;
        end
        else if (es_allowin) begin
            es_valid <= ds_to_es_valid;
        end
    end

    // 保存ID级传来的数据
    always @(posedge clk) begin
        if (ds_to_es_valid && es_allowin && !pipe_flush) begin
            ds_to_es_bus_r <= ds_to_es_bus;
            ds_to_es_meta_r <= ds_to_es_meta;
        end
    end

    // ALU
    alu u_alu(
        .alu_op     (es_alu_op),
        .alu_src1   (es_alu_src1),
        .alu_src2   (es_alu_src2),
        .alu_result (es_alu_result)
    );

    // 有符号除法器
    div_signed u_div_signed (
        .aclk                   (clk),
        .aresetn                (div_ip_aresetn),

        .s_axis_divisor_tvalid   (div_signed_req),
        .s_axis_divisor_tdata    (es_alu_src2),

        .s_axis_dividend_tvalid  (div_signed_req),
        .s_axis_dividend_tdata   (es_alu_src1),

        .m_axis_dout_tvalid      (div_signed_out_valid),
        .m_axis_dout_tdata       (div_signed_out_data)
    );

    // 无符号除法器
    div_unsigned u_div_unsigned (
        .aclk                   (clk),
        .aresetn                (div_ip_aresetn),

        .s_axis_divisor_tvalid   (div_unsigned_req),
        .s_axis_divisor_tdata    (es_alu_src2),

        .s_axis_dividend_tvalid  (div_unsigned_req),
        .s_axis_dividend_tdata   (es_alu_src1),

        .m_axis_dout_tvalid      (div_unsigned_out_valid),
        .m_axis_dout_tdata       (div_unsigned_out_data)
    );

    /*
     * 数据RAM访问在EXE级发起。
     * Block RAM经过时钟后返回的数据将在MEM级使用。
     */
    // 前级已有异常就保留，否则检查本级的地址不对齐
    assign es_exc =
        ds_to_es_meta_r[83] ? ds_to_es_meta_r[83:35] :
        es_ale ? {1'b1, 6'h09, 9'b0, 1'b1, es_alu_result} :
                 {`EXC_BUS_WD{1'b0}};

    assign es_exc_valid = es_exc[48];

    // 是否为半字访问：半字load或半字store
    assign es_half_access =
        (es_res_from_mem && es_load_is_half) ||
        (es_mem_we && es_store_is_half);

    // 是否为字访问：既不是字节，也不是半字的load/store
    assign es_word_access =
        (es_res_from_mem &&
         !es_load_is_byte && !es_load_is_half) ||
        (es_mem_we &&
         !es_store_is_byte && !es_store_is_half);

    // 半字检查最低1位；字检查最低2位
    assign es_ale =
        (es_half_access && es_alu_result[0]) ||
        (es_word_access && (es_alu_result[1:0] != 2'b00));

    assign es_mem_req_ok =
        !reset && !pipe_flush && !ms_ex_pending &&
        es_valid && es_ready_go && ms_allowin &&
        !es_exc_valid &&
        (es_res_from_mem || es_mem_we);


    assign data_sram_en = es_mem_req_ok;

    assign data_sram_we =
        (es_mem_req_ok && es_mem_we)
        ? es_store_we
        : 4'b0000;

    assign data_sram_addr  = es_alu_result;
    assign data_sram_wdata =
        es_store_is_byte
        ? {4{es_rkd_value[7:0]}}
        : es_store_is_half
        ? {2{es_rkd_value[15:0]}}
        : es_rkd_value;

    // 将执行结果和后续需要的控制信息送给MEM
    assign es_to_ms_bus = {
        es_res_from_mem, // 1位
        es_load_is_byte,
        es_load_unsigned,
        es_load_is_half,
        (es_gr_we && !es_exc_valid), // 异常指令不写普通结果
        es_mem_we,       // 1位
        es_dest,         // 5位
        es_result, // 32位
        es_rkd_value,    // 32位
        es_pc            // 32位
    };

    assign es_cnt_op = ds_to_es_meta_r[33:32];

    assign es_cnt_value =
        (es_cnt_op == 2'b01) ? counter_value[31:0] :
        (es_cnt_op == 2'b10) ? counter_value[63:32] :
                              32'b0;


    // 将本级保存的元数据送往MEM
    assign es_to_ms_meta = {
        ds_to_es_meta_r[163:84],
        es_exc,
        ds_to_es_meta_r[34:32],  // ertn和计数器操作类型
        es_cnt_value            // 选出的32位计数值
    };

   // 向ID级反馈EXE级的目的寄存器和计算结果
    assign es_to_ds_bus = {
        es_valid,          // 1位：EXE级是否存在有效指令
        es_res_from_mem,   // 1位：结果是否需要从内存读取
        (es_gr_we &&
         !es_exc_valid &&
         (ds_to_es_meta_r[163:162] == 2'b00) &&
         (ds_to_es_meta_r[33:32] == 2'b00)),         // 1位：是否写通用寄存器
        es_dest,           // 5位：目的寄存器号
        es_result,      // 32位：ALU计算结果
        es_ready_go
    };

    // 直接导出本级寄存状态
    assign es_valid_for_ctrl = es_valid;

    assign es_serializing =
        es_valid &&
        ((ds_to_es_meta_r[163:162] != 2'b00) ||
            es_exc_valid ||
          ds_to_es_meta_r[34] ||
         (ds_to_es_meta_r[33:32] != 2'b00));

endmodule
