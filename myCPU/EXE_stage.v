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
    wire [31:0] es_alu_src1;
    wire [31:0] es_alu_src2;
    wire [31:0] es_rkd_value;
    wire [31:0] es_pc;
    wire        es_res_from_mem;

    // ALU计算结果
    wire [31:0] es_alu_result;

    // ID打包的顺序必须和这里的拆包顺序完全一致
    assign {
        es_alu_op,
        es_gr_we,
        es_mem_we,
        es_dest,
        es_alu_src1,
        es_alu_src2,
        es_rkd_value,
        es_pc,
        es_res_from_mem
    } = ds_to_es_bus_r;

    // 第一章暂时没有多周期执行操作
    assign es_ready_go = 1'b1;

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

    /*
     * 数据RAM访问在EXE级发起。
     * Block RAM经过时钟后返回的数据将在MEM级使用。
     */
    assign data_sram_en =
           es_valid && es_ready_go && ms_allowin;

    assign data_sram_we =
           {4{es_mem_we && es_valid && ms_allowin}};

    assign data_sram_addr  = es_alu_result;
    assign data_sram_wdata = es_rkd_value;

    // 将执行结果和后续需要的控制信息送给MEM
    assign es_to_ms_bus = {
        es_res_from_mem, // 1位
        es_gr_we,        // 1位
        es_mem_we,       // 1位
        es_dest,         // 5位
        es_alu_result,   // 32位
        es_rkd_value,    // 32位
        es_pc            // 32位
    };

    // 向ID级报告EXE中尚未写回的目的寄存器
    assign es_to_ds_bus = {
        es_valid,
        es_gr_we,
        es_dest
    };

endmodule