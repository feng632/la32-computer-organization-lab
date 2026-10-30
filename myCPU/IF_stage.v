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

    // ex9 ADEF：取指地址错误
    wire        pc_misaligned;      // 本拍要发起的地址是否错误
    wire        fs_pc_misaligned;   // 已锁存到IF的PC是否错误
    wire        fetch_exc;          // 本拍产生一个取指异常标记

    // 拆开ID级传回的分支总线
    assign {br_taken, br_target} = br_bus;

    // IF向ID传递：指令和该指令对应的PC
    // 取指地址错误时指令字强制为0，不允许ID把上一次读出的数据当指令译码
    assign fs_to_ds_bus = {fs_pc_misaligned ? 32'b0 : fs_inst, fs_pc};

    // ex9 ADEF：{valid, ecode=0x08, esubcode=0, badv_valid=1, badv=错误PC}
    // 无异常时整个49位清零（02约定：不允许X/Z占位）
    assign fs_to_ds_ex = fs_pc_misaligned ?
        {1'b1, 6'h08, 9'b0, 1'b1, fs_pc} : {`EXC_BUS_WD{1'b0}};

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

    // ex9 ADEF：课程只检查指令地址 PC[1:0]!=0
    assign pc_misaligned    = (fetch_addr[1:0] != 2'b00);
    assign fs_pc_misaligned = (fs_pc[1:0]     != 2'b00);

    // 地址错误的这一拍不向RAM发请求，但仍要产生一个有效的异常标记送ID
    assign fetch_exc = to_fs_valid && fs_allowin && !pipe_flush && pc_misaligned;

    // 本拍是否真正向指令RAM发请求：冲刷当拍一律不发
    assign fetch_req = to_fs_valid && fs_allowin && !pipe_flush && !pc_misaligned;

    // IF为空，或者当前指令能够送往ID时，可以接收新的PC
    assign fs_allowin =
           !fs_valid ||
           (fs_ready_go && ds_allowin);

    // 冲刷当拍即使 fs_valid 仍为1，也不得把旧指令送给ID；
    // 若ID中的分支跳转成立，当前IF指令属于错误路径，同样取消
    assign fs_to_ds_valid =
           fs_valid && fs_ready_go && !br_taken && !pipe_flush;

    // PC：发出请求或产生取指异常的那一拍更新
    // 地址错误时不发RAM请求，但仍需把错误PC锁存下来作为ADEF的badv
    always @(posedge clk) begin
        if (reset) begin
            // 下一次加4后得到0x1c000000
            fs_pc <= 32'h1bfffffc;
        end
        else if (fetch_req || fetch_exc) begin
            fs_pc <= fetch_addr;
        end
    end

    // 有效位：请求发出的下一拍，BRAM 数据才就绪；
    // 冲刷优先清0，因此旧请求的响应回来时不会被当成有效指令
    // 取指异常同样是有效标记，必须置位才能送到ID
    always @(posedge clk) begin
        if (reset) begin
            fs_valid <= 1'b0;
        end
        else if (pipe_flush) begin
            fs_valid <= 1'b0;
        end
        else if (fetch_req || fetch_exc) begin
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
        else if ((fetch_req || fetch_exc) && use_redirect) begin
            // 取指异常也算消费了重定向，否则错误目标会被反复取，形成ADEF循环
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
