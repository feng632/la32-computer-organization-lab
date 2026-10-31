`include "mycpu_head.v"

module mycpu_top #(
    // 分支预测开关（TEAM-BP-1.0）：只传给预测器 enable，外部引脚不变。
    // 关闭时仍走同一套纠正逻辑，只是所有预测均为顺序地址。
    parameter BP_ENABLE = 1'b0
)(
    input  wire        clk,
    input  wire        resetn,

    // 外部硬中断：ex9 使用；无中断源的仿真环境与原有SoC必须显式接8'b0
    input  wire [ 7:0] hw_int_in,

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
    wire [`EXC_BUS_WD-1:0]      fs_to_ds_ex;
    wire                         ds_allowin;
    wire [`BR_BUS_WD-1:0]       br_bus;

    /*
     * ID <-> EXE
     */
    wire                         ds_to_es_valid;
    wire [`DS_TO_ES_BUS_WD-1:0] ds_to_es_bus;
    wire [`PIPE_META_WD-1:0]    ds_to_es_meta;
    wire                         es_allowin;

    /*
     * EXE <-> MEM
     */
    wire                         es_to_ms_valid;
    wire [`ES_TO_MS_BUS_WD-1:0] es_to_ms_bus;
    wire [`PIPE_META_WD-1:0]    es_to_ms_meta;
    wire                         ms_allowin;

    /*
     * MEM <-> WB
     */
    wire                         ms_to_ws_valid;
    wire [`MS_TO_WS_BUS_WD-1:0] ms_to_ws_bus;
    wire [`PIPE_META_WD-1:0]    ms_to_ws_meta;
    wire                         ws_allowin;

    /*
     * WB -> ID寄存器堆
     */
    wire [`WS_TO_RF_BUS_WD-1:0] ws_to_rf_bus;

    // EXE、MEM、WB送回ID的冲突检测信息
    wire [`ES_TO_DS_BUS_WD-1:0] es_to_ds_bus;
    wire [`MS_TO_DS_BUS_WD-1:0] ms_to_ds_bus;
    wire [`WS_TO_DS_BUS_WD-1:0] ws_to_ds_bus;

    /*
     * 后三级的控制状态：供ID判断序列化与排空
     */
    wire es_valid_for_ctrl;
    wire ms_valid_for_ctrl;
    wire ws_valid_for_ctrl;
    wire es_serializing;
    wire ms_serializing;
    wire ws_serializing;
    wire ms_ex_pending;

    /*
     * CSR模块接口
     */
    wire [13:0] csr_num;
    wire        csr_we;
    wire [31:0] csr_wmask;
    wire [31:0] csr_wvalue;
    wire [31:0] csr_rvalue;
    wire [31:0] ex_entry;
    wire [31:0] ertn_entry;
    wire        has_int;
    wire [63:0] counter_value;
    wire [31:0] tid_value;

    // WB提交事件
    wire        wb_ex;
    wire [ 5:0] wb_ecode;
    wire [ 8:0] wb_esubcode;
    wire [31:0] wb_pc;
    wire        wb_badv_valid;
    wire [31:0] wb_badv;
    wire        ertn_flush;

    // 全局冲刷与重定向：组合产生，全流水使用同一事件
    wire        pipe_flush;
    wire [31:0] redirect_pc;

    assign pipe_flush  = wb_ex || ertn_flush;
    assign redirect_pc = wb_ex ? ex_entry : ertn_entry;

    /*
     * 分支预测（TEAM-BP-1.0）
     */
    wire [31:0] bp_query_pc;
    wire        bp_query_hit;
    wire        bp_predict_taken;
    wire [31:0] bp_predict_target;
    wire [33:0] fs_to_ds_bp;
    wire [67:0] bp_update_bus;

    // 分支预测器（TEAM-BP-1.0，A 实现）
    // enable 由参数 BP_ENABLE 构建时固定，不运行中切换
    branch_predictor u_branch_predictor (
        .clk            (clk),
        .reset          (reset),
        .enable         (BP_ENABLE),
        .query_pc       (bp_query_pc),
        .bp_update_bus  (bp_update_bus),
        .query_hit      (bp_query_hit),
        .predict_taken  (bp_predict_taken),
        .predict_target (bp_predict_target)
    );

    // IF：取指
    IF_stage u_if_stage(
        .clk             (clk),
        .reset           (reset),

        .ds_allowin      (ds_allowin),
        .br_bus          (br_bus),

        .bp_query_pc       (bp_query_pc),
        .bp_query_hit      (bp_query_hit),
        .bp_predict_taken  (bp_predict_taken),
        .bp_predict_target (bp_predict_target),

        .pipe_flush      (pipe_flush),
        .redirect_pc     (redirect_pc),

        .fs_to_ds_valid  (fs_to_ds_valid),
        .fs_to_ds_bus    (fs_to_ds_bus),
        .fs_to_ds_ex     (fs_to_ds_ex),
        .fs_to_ds_bp     (fs_to_ds_bp),

        .inst_sram_en    (inst_sram_en),
        .inst_sram_we    (inst_sram_we),
        .inst_sram_addr  (inst_sram_addr),
        .inst_sram_wdata (inst_sram_wdata),
        .inst_sram_rdata (inst_sram_rdata)
    );

    // ID：译码和寄存器读取
    ID_stage u_id_stage(
        .clk                (clk),
        .reset              (reset),

        .pipe_flush         (pipe_flush),
        .has_int            (has_int),

        .es_valid_for_ctrl  (es_valid_for_ctrl),
        .ms_valid_for_ctrl  (ms_valid_for_ctrl),
        .ws_valid_for_ctrl  (ws_valid_for_ctrl),
        .es_serializing     (es_serializing),
        .ms_serializing     (ms_serializing),
        .ws_serializing     (ws_serializing),

        .es_allowin         (es_allowin),
        .ds_allowin         (ds_allowin),

        .fs_to_ds_valid     (fs_to_ds_valid),
        .fs_to_ds_bus       (fs_to_ds_bus),
        .fs_to_ds_ex        (fs_to_ds_ex),
        .fs_to_ds_bp        (fs_to_ds_bp),

        .ds_to_es_valid     (ds_to_es_valid),
        .ds_to_es_bus       (ds_to_es_bus),
        .ds_to_es_meta      (ds_to_es_meta),

        .br_bus             (br_bus),
        // 待 A 的 branch_predictor 交付后接入其 bp_update_bus 输入
        .bp_update_bus      (bp_update_bus),
        .ws_to_rf_bus       (ws_to_rf_bus),

        .es_to_ds_bus       (es_to_ds_bus),
        .ms_to_ds_bus       (ms_to_ds_bus),
        .ws_to_ds_bus       (ws_to_ds_bus)
    );

    // EXE：ALU运算和数据RAM请求
    EXE_stage u_exe_stage(
        .clk                (clk),
        .reset              (reset),

        .pipe_flush         (pipe_flush),
        .ms_ex_pending      (ms_ex_pending),
        .counter_value      (counter_value),

        .ms_allowin         (ms_allowin),
        .es_allowin         (es_allowin),

        .ds_to_es_valid     (ds_to_es_valid),
        .ds_to_es_bus       (ds_to_es_bus),
        .ds_to_es_meta      (ds_to_es_meta),

        .es_to_ms_valid     (es_to_ms_valid),
        .es_to_ms_bus       (es_to_ms_bus),
        .es_to_ms_meta      (es_to_ms_meta),

        .es_to_ds_bus       (es_to_ds_bus),

        .es_valid_for_ctrl  (es_valid_for_ctrl),
        .es_serializing     (es_serializing),

        .data_sram_en       (data_sram_en),
        .data_sram_we       (data_sram_we),
        .data_sram_addr     (data_sram_addr),
        .data_sram_wdata    (data_sram_wdata)
    );

    // MEM：选择RAM返回值或ALU结果
    MEM_stage u_mem_stage(
        .clk                (clk),
        .reset              (reset),

        .pipe_flush         (pipe_flush),

        .ws_allowin         (ws_allowin),
        .ms_allowin         (ms_allowin),

        .es_to_ms_valid     (es_to_ms_valid),
        .es_to_ms_bus       (es_to_ms_bus),
        .es_to_ms_meta      (es_to_ms_meta),

        .ms_to_ws_valid     (ms_to_ws_valid),
        .ms_to_ws_bus       (ms_to_ws_bus),
        .ms_to_ws_meta      (ms_to_ws_meta),

        .ms_to_ds_bus       (ms_to_ds_bus),

        .ms_valid_for_ctrl  (ms_valid_for_ctrl),
        .ms_serializing     (ms_serializing),
        .ms_ex_pending      (ms_ex_pending),

        .data_sram_rdata    (data_sram_rdata)
    );

    // WB：寄存器写回和Trace输出
    WB_stage u_wb_stage(
        .clk                (clk),
        .reset              (reset),

        .csr_rvalue         (csr_rvalue),
        .tid_value          (tid_value),

        .ws_valid_for_ctrl  (ws_valid_for_ctrl),
        .ws_serializing     (ws_serializing),

        .csr_num            (csr_num),
        .csr_we             (csr_we),
        .csr_wmask          (csr_wmask),
        .csr_wvalue         (csr_wvalue),

        .wb_ex              (wb_ex),
        .wb_ecode           (wb_ecode),
        .wb_esubcode        (wb_esubcode),
        .wb_pc              (wb_pc),
        .wb_badv_valid      (wb_badv_valid),
        .wb_badv            (wb_badv),
        .ertn_flush         (ertn_flush),

        .ws_allowin         (ws_allowin),

        .ms_to_ws_valid     (ms_to_ws_valid),
        .ms_to_ws_bus       (ms_to_ws_bus),
        .ms_to_ws_meta      (ms_to_ws_meta),

        .ws_to_rf_bus       (ws_to_rf_bus),

        .debug_wb_pc        (debug_wb_pc),
        .debug_wb_rf_we     (debug_wb_rf_we),
        .debug_wb_rf_wnum   (debug_wb_rf_wnum),
        .debug_wb_rf_wdata  (debug_wb_rf_wdata),

        .ws_to_ds_bus       (ws_to_ds_bus)
    );

    // CSR：控制状态寄存器（A负责实现）
    csr u_csr(
        .clk            (clk),
        .reset          (reset),

        .csr_num        (csr_num),
        .csr_we         (csr_we),
        .csr_wmask      (csr_wmask),
        .csr_wvalue     (csr_wvalue),

        .wb_ex          (wb_ex),
        .wb_ecode       (wb_ecode),
        .wb_esubcode    (wb_esubcode),
        .wb_pc          (wb_pc),
        .wb_badv_valid  (wb_badv_valid),
        .wb_badv        (wb_badv),

        .ertn_flush     (ertn_flush),
        .hw_int_in      (hw_int_in),

        .csr_rvalue     (csr_rvalue),
        .ex_entry       (ex_entry),
        .ertn_entry     (ertn_entry),
        .has_int        (has_int),
        .counter_value  (counter_value),
        .tid_value      (tid_value)
    );

endmodule
