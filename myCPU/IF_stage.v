`include "mycpu_head.v"

module IF_stage(
    input  wire                         clk,
    input  wire                         reset,

    // ID级是否允许接收新指令
    input  wire                         ds_allowin,

    // ID级传回的分支信息
    input  wire [`BR_BUS_WD-1:0]        br_bus,

    // 发送给ID级
    output wire                         fs_to_ds_valid,
    output wire [`FS_TO_DS_BUS_WD-1:0]  fs_to_ds_bus,

    // 指令RAM接口
    output wire                         inst_sram_en,
    output wire [3:0]                   inst_sram_we,
    output wire [31:0]                  inst_sram_addr,
    output wire [31:0]                  inst_sram_wdata,
    input  wire [31:0]                  inst_sram_rdata
);

    // IF级握手信号
    reg  fs_valid;
    wire fs_ready_go;
    wire fs_allowin;
    wire to_fs_valid;

    // PC相关信号
    reg  [31:0] fs_pc;
    wire [31:0] seq_pc;
    wire [31:0] next_pc;

    // 分支信息
    wire        br_taken;
    wire [31:0] br_target;

    // 取回的指令
    wire [31:0] fs_inst;

    // 拆开ID级传回的分支总线
    assign {br_taken, br_target} = br_bus;

    // IF向ID传递：指令和该指令对应的PC
    assign fs_to_ds_bus = {fs_inst, fs_pc};

    // 当前阶段暂时没有需要等待的多周期操作
    assign fs_ready_go = 1'b1;

    // IF为空，或者当前指令能够送往ID时，可以接收新的PC
    assign fs_allowin =
           !fs_valid ||
           (fs_ready_go && ds_allowin);

    // IF有一条有效指令并且取指完成时送往ID；
    // 若ID中的分支跳转成立，当前IF指令属于错误路径，必须取消
    assign fs_to_ds_valid =
           fs_valid && fs_ready_go && !br_taken;

    // 复位结束后，允许开始取指
    assign to_fs_valid = !reset;

    // 顺序执行时PC加4
    assign seq_pc = fs_pc + 32'd4;

    // 如果发生跳转，下一PC选择跳转目标
    assign next_pc = br_taken ? br_target : seq_pc;

    // 维护IF级有效位
    always @(posedge clk) begin
        if (reset) begin
            fs_valid <= 1'b0;
        end
        else if (fs_allowin) begin
            fs_valid <= to_fs_valid;
        end
    end

    // 更新PC
    always @(posedge clk) begin
        if (reset) begin
            // 下一次加4后得到0x1c000000
            fs_pc <= 32'h1bfffffc;
        end
        else if (to_fs_valid && fs_allowin) begin
            fs_pc <= next_pc;
        end
    end

    // 指令RAM读取接口
    assign inst_sram_en    = to_fs_valid && fs_allowin;
    assign inst_sram_we    = 4'b0000;
    assign inst_sram_addr  = next_pc;
    assign inst_sram_wdata = 32'b0;

    // Block RAM返回的指令
    assign fs_inst = inst_sram_rdata;

endmodule
