`include "mycpu_head.v"

module WB_stage(
    input  wire                         clk,
    input  wire                         reset,

    // 告诉MEM级：WB是否允许接收
    output wire                         ws_allowin,

    // 来自MEM级
    input  wire                         ms_to_ws_valid,
    input  wire [`MS_TO_WS_BUS_WD-1:0]  ms_to_ws_bus,

    // 送回ID级寄存器堆
    output wire [`WS_TO_RF_BUS_WD-1:0]  ws_to_rf_bus,

    // Trace调试接口
    output wire [31:0]                  debug_wb_pc,
    output wire [ 3:0]                  debug_wb_rf_we,
    output wire [ 4:0]                  debug_wb_rf_wnum,
    output wire [31:0]                  debug_wb_rf_wdata
);

    // WB级有效位
    reg  ws_valid;
    wire ws_ready_go;

    // 保存MEM级传来的数据
    reg [`MS_TO_WS_BUS_WD-1:0] ms_to_ws_bus_r;

    // 从MEM总线拆出的信号
    wire        ws_gr_we;
    wire [ 4:0] ws_dest;
    wire [31:0] ws_final_result;
    wire [31:0] ws_pc;

    // 最终寄存器堆写使能
    wire rf_we;

    // 拆开MEM传来的70位总线
    assign {
        ws_gr_we,
        ws_dest,
        ws_final_result,
        ws_pc
    } = ms_to_ws_bus_r;

    // WB没有后续流水级，本阶段总能完成
    assign ws_ready_go = 1'b1;

    // WB为空，或者当前写回已经完成
    assign ws_allowin =
           !ws_valid ||
           ws_ready_go;

    // 维护WB级有效位
    always @(posedge clk) begin
        if (reset) begin
            ws_valid <= 1'b0;
        end
        else if (ws_allowin) begin
            ws_valid <= ms_to_ws_valid;
        end
    end

    // 保存MEM传来的数据
    always @(posedge clk) begin
        if (ms_to_ws_valid && ws_allowin) begin
            ms_to_ws_bus_r <= ms_to_ws_bus;
        end
    end

    /*
     * 必须同时满足：
     * 1. 当前指令需要写通用寄存器
     * 2. 当前WB级指令有效
     */
    assign rf_we =
           ws_gr_we && ws_valid;

    // 送回ID级中的寄存器堆
    // ws_dest指向具体的哪个寄存器
    assign ws_to_rf_bus = {
        rf_we,           // 1位
        ws_dest,         // 5位
        ws_final_result  // 32位
    };

    // 送给测试平台的Trace信息
    assign debug_wb_pc       = ws_pc;
    assign debug_wb_rf_we    = {4{rf_we}};
    assign debug_wb_rf_wnum  = ws_dest;
    assign debug_wb_rf_wdata = ws_final_result;

endmodule