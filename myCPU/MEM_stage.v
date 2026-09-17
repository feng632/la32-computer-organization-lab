`include "mycpu_head.v"

module MEM_stage(
    input  wire                         clk,
    input  wire                         reset,

    // WB级是否允许接收
    input  wire                         ws_allowin,

    // 告诉EXE级：MEM是否允许接收
    output wire                         ms_allowin,

    // 来自EXE级
    input  wire                         es_to_ms_valid,
    input  wire [`ES_TO_MS_BUS_WD-1:0]  es_to_ms_bus,

    // 发送给WB级
    output wire                         ms_to_ws_valid,
    output wire [`MS_TO_WS_BUS_WD-1:0]  ms_to_ws_bus,

    // 数据RAM返回值
    input  wire [31:0]                  data_sram_rdata
);

    // MEM级握手信号
    reg  ms_valid;
    wire ms_ready_go;

    // 保存EXE级传来的数据
    reg [`ES_TO_MS_BUS_WD-1:0] es_to_ms_bus_r;

    // 从EXE总线中拆出的信号
    wire        ms_res_from_mem;
    wire        ms_gr_we;
    wire        ms_mem_we;
    wire [ 4:0] ms_dest;
    wire [31:0] ms_alu_result;
    wire [31:0] ms_rkd_value;
    wire [31:0] ms_pc;

    // 当前指令最终产生的结果
    wire [31:0] ms_final_result;

    // 拆开EXE传来的104位总线
    assign {
        ms_res_from_mem,
        ms_gr_we,
        ms_mem_we,
        ms_dest,
        ms_alu_result,
        ms_rkd_value,
        ms_pc
    } = es_to_ms_bus_r;

    // 当前所有MEM操作都能在本阶段完成
    assign ms_ready_go = 1'b1;

    // MEM为空，或者当前结果可以送给WB
    assign ms_allowin =
           !ms_valid ||
           (ms_ready_go && ws_allowin);

    // MEM中有有效指令，并且访存完成
    assign ms_to_ws_valid =
           ms_valid && ms_ready_go;

    // 维护MEM级有效位
    always @(posedge clk) begin
        if (reset) begin
            ms_valid <= 1'b0;
        end
        else if (ms_allowin) begin
            ms_valid <= es_to_ms_valid;
        end
    end

    // 保存EXE级传来的信息
    always @(posedge clk) begin
        if (es_to_ms_valid && ms_allowin) begin
            es_to_ms_bus_r <= es_to_ms_bus;
        end
    end

    /*
     * ld.w选择RAM返回的数据；
     * 其他需要写回的指令选择ALU结果。
     */
    assign ms_final_result =
           ms_res_from_mem
           ? data_sram_rdata
           : ms_alu_result;

    // 打包送给WB级
    assign ms_to_ws_bus = {
        ms_gr_we,        // 1位
        ms_dest,         // 5位
        ms_final_result, // 32位
        ms_pc            // 32位
    };

endmodule