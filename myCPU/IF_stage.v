`include "mycpu_head.v"

module IF_stage(
    input  wire                         clk,
    input  wire                         reset,

    // ID级是否允许接收新指令
    input  wire                         ds_allowin,

    // ID级传回的分支信息
    input  wire [`BR_BUS_WD-1:0]        br_bus,

    // 全局冲刷与重定向目标（TEAM-ABI-1.0）
    input  wire                         pipe_flush,
    input  wire [31:0]                  redirect_pc,

    // 发送给ID级
    output wire                         fs_to_ds_valid,
    output wire [`FS_TO_DS_BUS_WD-1:0]  fs_to_ds_bus,
    output wire [`EXC_BUS_WD-1:0]       fs_to_ds_ex,

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

    // 重定向缓存：锁存目标，下一拍才用它发请求
    reg         redirect_pending;
    reg  [31:0] redirect_pc_r;
    wire        use_redirect;
    wire [31:0] fetch_addr;
    wire        fetch_req;

    // 拆开ID级传回的分支总线
    assign {br_taken, br_target} = br_bus;

    // IF向ID传递：指令和该指令对应的PC
    assign fs_to_ds_bus = {fs_inst, fs_pc};

    // ex9 才产生 ADEF；骨架阶段恒无异常
    assign fs_to_ds_ex = {`EXC_BUS_WD{1'b0}};

    // 当前阶段暂时没有需要等待的多周期操作
    assign fs_ready_go = 1'b1;

    // 复位结束后，允许开始取指
    assign to_fs_valid = !reset;

    // 顺序执行时PC加4
    assign seq_pc = fs_pc + 32'd4;

    // 如果发生跳转，下一PC选择跳转目标
    assign next_pc = br_taken ? br_target : seq_pc;

    // 有待消费的重定向时，必须用锁存目标，不能再用旧 fs_pc+4
    assign use_redirect = redirect_pending;
    assign fetch_addr   = use_redirect ? redirect_pc_r : next_pc;

    // 本拍是否真正向指令RAM发请求：冲刷当拍一律不发
    assign fetch_req = to_fs_valid && fs_allowin && !pipe_flush;

    // IF为空，或者当前指令能够送往ID时，可以接收新的PC
    assign fs_allowin =
           !fs_valid ||
           (fs_ready_go && ds_allowin);

    // 冲刷当拍即使 fs_valid 仍为1，也不得把旧指令送给ID；
    // 若ID中的分支跳转成立，当前IF指令属于错误路径，同样取消
    assign fs_to_ds_valid =
           fs_valid && fs_ready_go && !br_taken && !pipe_flush;

    // PC：只在真正发出请求的那一拍更新
    always @(posedge clk) begin
        if (reset) begin
            // 下一次加4后得到0x1c000000
            fs_pc <= 32'h1bfffffc;
        end
        else if (fetch_req) begin
            fs_pc <= fetch_addr;
        end
    end

    // 有效位：请求发出的下一拍，BRAM 数据才就绪；
    // 冲刷优先清0，因此旧请求的响应回来时不会被当成有效指令
    always @(posedge clk) begin
        if (reset) begin
            fs_valid <= 1'b0;
        end
        else if (pipe_flush) begin
            fs_valid <= 1'b0;
        end
        else if (fetch_req) begin
            fs_valid <= to_fs_valid;
        end
    end

    // 重定向缓存：新冲刷覆盖尚未消费的旧目标
    always @(posedge clk) begin
        if (reset) begin
            redirect_pending <= 1'b0;
            redirect_pc_r    <= 32'b0;
        end
        else if (pipe_flush) begin
            redirect_pc_r    <= redirect_pc;
            redirect_pending <= 1'b1;
        end
        else if (fetch_req && use_redirect) begin
            redirect_pending <= 1'b0;
        end
    end

    // 指令RAM读取接口
    assign inst_sram_en    = fetch_req;
    assign inst_sram_we    = 4'b0000;
    assign inst_sram_addr  = fetch_addr;
    assign inst_sram_wdata = 32'b0;

    // Block RAM返回的指令
    assign fs_inst = inst_sram_rdata;

endmodule
