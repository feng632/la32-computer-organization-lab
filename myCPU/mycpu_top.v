`include "mycpu_head.v"

module mycpu_top(
    input  wire        clk,
    input  wire        resetn,

    // 指令RAM接口
    output wire        inst_sram_en,
    output wire [ 3:0] inst_sram_we,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire [31:0] inst_sram_rdata,

    // 数据RAM接口
    output wire        data_sram_en,
    output wire [ 3:0] data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    input  wire [31:0] data_sram_rdata,

    // Trace调试接口
    output wire [31:0] debug_wb_pc,
    output wire [ 3:0] debug_wb_rf_we,
    output wire [ 4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);

    // 将外部低电平有效复位转换成内部高电平有效复位
    reg reset;

    always @(posedge clk) begin
        reset <= !resetn;
    end

    /*
     * IF <-> ID
     */
    wire                         fs_to_ds_valid;
    wire [`FS_TO_DS_BUS_WD-1:0] fs_to_ds_bus;
    wire                         ds_allowin;
    wire [`BR_BUS_WD-1:0]       br_bus;

    /*
     * ID <-> EXE
     */
    wire                         ds_to_es_valid;
    wire [`DS_TO_ES_BUS_WD-1:0] ds_to_es_bus;
    wire                         es_allowin;

    /*
     * EXE <-> MEM
     */
    wire                         es_to_ms_valid;
    wire [`ES_TO_MS_BUS_WD-1:0] es_to_ms_bus;
    wire                         ms_allowin;

    /*
     * MEM <-> WB
     */
    wire                         ms_to_ws_valid;
    wire [`MS_TO_WS_BUS_WD-1:0] ms_to_ws_bus;
    wire                         ws_allowin;

    /*
     * WB -> ID寄存器堆
     */
    wire [`WS_TO_RF_BUS_WD-1:0] ws_to_rf_bus;

    // EXE、MEM、WB送回ID的冲突检测信息
    wire [`ES_TO_DS_BUS_WD-1:0] es_to_ds_bus;
    wire [`MS_TO_DS_BUS_WD-1:0] ms_to_ds_bus;
    wire [`WS_TO_DS_BUS_WD-1:0] ws_to_ds_bus;

    // IF：取指
    IF_stage u_if_stage(
        .clk             (clk),
        .reset           (reset),

        .ds_allowin      (ds_allowin),
        .br_bus          (br_bus),

        .fs_to_ds_valid  (fs_to_ds_valid),
        .fs_to_ds_bus    (fs_to_ds_bus),

        .inst_sram_en    (inst_sram_en),
        .inst_sram_we    (inst_sram_we),
        .inst_sram_addr  (inst_sram_addr),
        .inst_sram_wdata (inst_sram_wdata),
        .inst_sram_rdata (inst_sram_rdata)
    );

    // ID：译码和寄存器读取
    ID_stage u_id_stage(
        .clk             (clk),
        .reset           (reset),

        .es_allowin      (es_allowin),
        .ds_allowin      (ds_allowin),

        .fs_to_ds_valid  (fs_to_ds_valid),
        .fs_to_ds_bus    (fs_to_ds_bus),

        .ds_to_es_valid  (ds_to_es_valid),
        .ds_to_es_bus    (ds_to_es_bus),

        .br_bus          (br_bus),
        .ws_to_rf_bus    (ws_to_rf_bus),

        .es_to_ds_bus    (es_to_ds_bus),
        .ms_to_ds_bus    (ms_to_ds_bus),
        .ws_to_ds_bus    (ws_to_ds_bus)
    );

    // EXE：ALU运算和数据RAM请求
    EXE_stage u_exe_stage(
        .clk             (clk),
        .reset           (reset),

        .ms_allowin      (ms_allowin),
        .es_allowin      (es_allowin),

        .ds_to_es_valid  (ds_to_es_valid),
        .ds_to_es_bus    (ds_to_es_bus),

        .es_to_ms_valid  (es_to_ms_valid),
        .es_to_ms_bus    (es_to_ms_bus),

        .data_sram_en    (data_sram_en),
        .data_sram_we    (data_sram_we),
        .data_sram_addr  (data_sram_addr),
        .data_sram_wdata (data_sram_wdata),

        .es_to_ds_bus    (es_to_ds_bus)
    );

    // MEM：选择RAM返回值或ALU结果
    MEM_stage u_mem_stage(
        .clk             (clk),
        .reset           (reset),

        .ws_allowin      (ws_allowin),
        .ms_allowin      (ms_allowin),

        .es_to_ms_valid  (es_to_ms_valid),
        .es_to_ms_bus    (es_to_ms_bus),

        .ms_to_ws_valid  (ms_to_ws_valid),
        .ms_to_ws_bus    (ms_to_ws_bus),

        .data_sram_rdata (data_sram_rdata),

        .ms_to_ds_bus    (ms_to_ds_bus)
    );

    // WB：寄存器写回和Trace输出
    WB_stage u_wb_stage(
        .clk             (clk),
        .reset           (reset),

        .ws_allowin      (ws_allowin),

        .ms_to_ws_valid  (ms_to_ws_valid),
        .ms_to_ws_bus    (ms_to_ws_bus),

        .ws_to_rf_bus    (ws_to_rf_bus),

        .debug_wb_pc      (debug_wb_pc),
        .debug_wb_rf_we   (debug_wb_rf_we),
        .debug_wb_rf_wnum (debug_wb_rf_wnum),
        .debug_wb_rf_wdata(debug_wb_rf_wdata),

        .ws_to_ds_bus    (ws_to_ds_bus)
    );

endmodule
