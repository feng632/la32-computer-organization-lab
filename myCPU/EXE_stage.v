`include "mycpu_head.v"

module EXE_stage(
    input  wire                         clk,
    input  wire                         reset,

    // MEM级是否允许接收
    input  wire                         ms_allowin,

    // 告诉ID级：EXE是否允许接收
    output wire                         es_allowin,

    // 来自ID级
    input  wire                         ds_to_es_valid,
    input  wire [`DS_TO_ES_BUS_WD-1:0]  ds_to_es_bus,

    // 发送给MEM级
    output wire                         es_to_ms_valid,
    output wire [`ES_TO_MS_BUS_WD-1:0]  es_to_ms_bus,

    // 送回ID级，用于数据相关判断
    output wire [`ES_TO_DS_BUS_WD-1:0] es_to_ds_bus,

    // 数据RAM接口
    output wire                         data_sram_en,
    output wire [3:0]                   data_sram_we,
    output wire [31:0]                  data_sram_addr,
    output wire [31:0]                  data_sram_wdata
);

    // EXE级握手信号
    reg  es_valid;
    wire es_ready_go;

    // 保存ID级传来的总线
    reg [`DS_TO_ES_BUS_WD-1:0] ds_to_es_bus_r;

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

    always @(posedge clk) begin
        if (reset) begin
            div_signed_done   <= 1'b0;
            div_signed_result <= 64'b0;
        end
        else if (es_allowin) begin
            div_signed_done <= 1'b0;
        end
        else if (div_signed_out_valid) begin
            div_signed_done   <= 1'b1;
            div_signed_result <= div_signed_out_data;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            div_unsigned_done   <= 1'b0;
            div_unsigned_result <= 64'b0;
        end
        else if (es_allowin) begin
            div_unsigned_done <= 1'b0;
        end
        else if (div_unsigned_out_valid) begin
            div_unsigned_done   <= 1'b1;
            div_unsigned_result <= div_unsigned_out_data;
        end
    end

    assign div_signed_req =
        es_valid &&
        (es_inst_div_w || es_inst_mod_w) &&
        !div_signed_sent &&
        !reset;

    assign div_unsigned_req =
        es_valid &&
        (es_inst_div_wu || es_inst_mod_wu) &&
        !div_unsigned_sent &&
        !reset;

    always @(posedge clk) begin
        if (reset) begin
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
        if (reset) begin
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
        (es_inst_div_w || es_inst_mod_w)
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
           es_valid && es_ready_go;

    // 维护EXE级有效位
    always @(posedge clk) begin
        if (reset) begin
            es_valid <= 1'b0;
        end
        else if (es_allowin) begin
            es_valid <= ds_to_es_valid;
        end
    end

    // 保存ID级传来的数据
    always @(posedge clk) begin
        if (ds_to_es_valid && es_allowin) begin
            ds_to_es_bus_r <= ds_to_es_bus;
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
        .aresetn                (~reset),

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
        .aresetn                (~reset),

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
    assign data_sram_en =
           es_valid && es_ready_go && ms_allowin;

    assign data_sram_we =
           (es_mem_we && es_valid && ms_allowin)
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
        es_gr_we,        // 1位
        es_mem_we,       // 1位
        es_dest,         // 5位
        es_result, // 32位
        es_rkd_value,    // 32位
        es_pc            // 32位
    };

   // 向ID级反馈EXE级的目的寄存器和计算结果
    assign es_to_ds_bus = {
        es_valid,          // 1位：EXE级是否存在有效指令
        es_res_from_mem,   // 1位：结果是否需要从内存读取
        es_gr_we,          // 1位：是否写通用寄存器
        es_dest,           // 5位：目的寄存器号
        es_result,      // 32位：ALU计算结果
        es_ready_go
    };

endmodule
