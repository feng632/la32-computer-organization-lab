`include "mycpu_head.v"

module WB_stage(
    input  wire                         clk,
    input  wire                         reset,


    // CSR模块提供的读值
    input wire [31:0] csr_rvalue,
    input wire [31:0] tid_value,

    // 提供给ID的控制状态
    output wire ws_valid_for_ctrl,
    output wire ws_serializing,

    // 普通CSR访问接口
    output wire [13:0] csr_num,
    output wire        csr_we,
    output wire [31:0] csr_wmask,
    output wire [31:0] csr_wvalue,

    // 异常与异常返回事件
    output wire        wb_ex,
    output wire [5:0]  wb_ecode,
    output wire [8:0]  wb_esubcode,
    output wire [31:0] wb_pc,
    output wire        wb_badv_valid,
    output wire [31:0] wb_badv,
    output wire        ertn_flush,

    // 告诉MEM级：WB是否允许接收
    output wire                         ws_allowin,

    // 来自MEM级
    input  wire                         ms_to_ws_valid,
    input  wire [`MS_TO_WS_BUS_WD-1:0]  ms_to_ws_bus,
    input wire [`PIPE_META_WD-1:0] ms_to_ws_meta,

    // 送回ID级寄存器堆
    output wire [`WS_TO_RF_BUS_WD-1:0]  ws_to_rf_bus,

    // 送回ID级，用于数据相关判断
    output wire [`WS_TO_DS_BUS_WD-1:0] ws_to_ds_bus,

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
    reg [`PIPE_META_WD-1:0] ms_to_ws_meta_r;

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
            ms_to_ws_meta_r <= ms_to_ws_meta;
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

   // 向ID级反馈WB级的目的寄存器和最终结果
    assign ws_to_ds_bus = {
        ws_valid,          // 1位：WB级是否存在有效指令
        ws_gr_we,          // 1位：是否写通用寄存器
        ws_dest,           // 5位：目的寄存器号
        ws_final_result    // 32位：最终写回结果
    };

        assign ws_valid_for_ctrl = ws_valid;

    assign ws_serializing =
        ws_valid &&
        ((ms_to_ws_meta_r[163:162] != 2'b00) ||
          ms_to_ws_meta_r[83] ||
          ms_to_ws_meta_r[34] ||
         (ms_to_ws_meta_r[33:32] != 2'b00));

    // G1骨架：新增操作暂不生效
    assign csr_num       = 14'b0;
    assign csr_we        = 1'b0;
    assign csr_wmask     = 32'b0;
    assign csr_wvalue    = 32'b0;

    assign wb_ex         = 1'b0;
    assign wb_ecode      = 6'b0;
    assign wb_esubcode   = 9'b0;
    assign wb_pc         = ws_pc;
    assign wb_badv_valid = 1'b0;
    assign wb_badv       = 32'b0;
    assign ertn_flush    = 1'b0;

endmodule