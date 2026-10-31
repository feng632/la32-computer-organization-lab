`timescale 1ns/1ps
// =============================================================================
// C 的 P1 模块级测试：IF 的预测查询、锁存、纠正与优先级（TEAM-BP-1.0）
//
// Level : mycpu_top 模块级。指令 RAM 为同步读模型（1 拍延迟），内容固定为
//         addi.w $r0,$r0,0；只观察取指时序与预测信息，不关心指令语义。
// Stim  : force 顶层 ds_allowin / br_bus / bp_query_* / wb_ex / ex_entry。
//         这是 05-validation 允许的"模块激励"，**不代表课程程序会自然触发**。
//         本测试不例化 A 的 branch_predictor，预测查询结果由 TB 直接给出，
//         因此不构成对预测器算法的任何验证。
//
// 覆盖（10-validation 第 7 节 P1 的 C 列表）：
//   BP8  复位第一地址准确               ：首个请求必须是 0x1c000000
//   BP1  预测信息与 RAM 响应对齐        ：fs_to_ds_bp 与 fs_pc 同拍锁存；
//                                        预测命中且跳转时不得取消指令
//   BP2  IF 阻塞保持                    ：阻塞期间 PC/预测信息不随表变化漂移
//   BP3  纠正当拍新请求不被清 valid 丢弃：纠正同时发新请求，新响应要保留
//   BP4  WB 优先                        ：冲刷与纠正同拍，只认 WB 目标
//   BP5  目标跨阻塞不丢                 ：锁存目标在阻塞期间不被覆盖
//   BP6  纠正目标未对齐生成 ADEF        ：不发 RAM 请求，异常字段完整
//   BP7  错误路线 ADEF 被取消           ：纠正走正确目标后，旧 ADEF 不送 ID
// =============================================================================
module tb_bp_fetch;

    // ---------------------------------------------------------------- clock
    reg clk    = 1'b0;
    reg resetn = 1'b0;
    always #10 clk = ~clk;              // 20 ns 周期，50 MHz

    // ---------------------------------------------------------------- DUT
    wire        inst_en;
    wire [ 3:0] inst_we;
    wire [31:0] inst_addr, inst_wdata;
    wire [31:0] inst_rdata;

    wire        data_en;
    wire [ 3:0] data_we;
    wire [31:0] data_addr, data_wdata;

    wire [31:0] dbg_pc, dbg_wdata;
    wire [ 3:0] dbg_rf_we;
    wire [ 4:0] dbg_wnum;

    mycpu_top u_cpu (
        .clk             (clk),
        .resetn          (resetn),
        .hw_int_in       (8'b0),

        .inst_sram_en    (inst_en),
        .inst_sram_we    (inst_we),
        .inst_sram_addr  (inst_addr),
        .inst_sram_wdata (inst_wdata),
        .inst_sram_rdata (inst_rdata),

        .data_sram_en    (data_en),
        .data_sram_we    (data_we),
        .data_sram_addr  (data_addr),
        .data_sram_wdata (data_wdata),
        .data_sram_rdata (32'b0),

        .debug_wb_pc     (dbg_pc),
        .debug_wb_rf_we  (dbg_rf_we),
        .debug_wb_rf_wnum(dbg_wnum),
        .debug_wb_rf_wdata(dbg_wdata)
    );

    // ----------------------------- 指令 RAM：同步读，1 拍延迟
    // en 高时采样地址，下一拍数据出现在 rdata，与 IF 的 fetch_req/fs_valid 配对
    localparam [31:0] NOP = 32'h0280_0000;   // addi.w $r0,$r0,0

    reg [31:0] inst_rdata_r;
    always @(posedge clk) begin
        if (inst_en) inst_rdata_r <= NOP;
    end
    assign inst_rdata = inst_rdata_r;

    // ------------------------------------------------------- internal probes
    wire         fs_valid         = u_cpu.u_if_stage.fs_valid;
    wire         fetch_req        = u_cpu.u_if_stage.fetch_req;
    wire         fetch_exc        = u_cpu.u_if_stage.fetch_exc;
    wire [31:0]  fetch_addr       = u_cpu.u_if_stage.fetch_addr;
    wire         fs_allowin       = u_cpu.u_if_stage.fs_allowin;
    wire [31:0]  seq_pc           = u_cpu.u_if_stage.seq_pc;
    wire         redirect_pending = u_cpu.u_if_stage.redirect_pending;
    wire [31:0]  redirect_pc_r    = u_cpu.u_if_stage.redirect_pc_r;
    wire [31:0]  fs_pc            = u_cpu.u_if_stage.fs_pc;
    wire         fs_to_ds_valid   = u_cpu.u_if_stage.fs_to_ds_valid;
    wire [63:0]  fs_to_ds_bus     = u_cpu.u_if_stage.fs_to_ds_bus;
    wire [48:0]  fs_to_ds_ex      = u_cpu.u_if_stage.fs_to_ds_ex;
    wire [33:0]  fs_to_ds_bp      = u_cpu.u_if_stage.fs_to_ds_bp;

    wire         bp_hit_r         = u_cpu.u_if_stage.bp_hit_r;
    wire         bp_taken_r       = u_cpu.u_if_stage.bp_taken_r;
    wire [31:0]  bp_next_pc_r     = u_cpu.u_if_stage.bp_next_pc_r;

    wire [31:0]  bp_query_pc      = u_cpu.bp_query_pc;

    wire         bp_redirect_valid= u_cpu.u_if_stage.bp_redirect_valid;
    wire [31:0]  bp_redirect_pc   = u_cpu.u_if_stage.bp_redirect_pc;

    wire         pipe_flush       = u_cpu.pipe_flush;
    wire [31:0]  redirect_pc      = u_cpu.redirect_pc;
    wire         ds_allowin       = u_cpu.ds_allowin;

    // ------------------------------------------------------------- checkers
    int checks = 0;
    int fails  = 0;

    task automatic chk32(input string name, input [31:0] actual, input [31:0] exp_v);
        checks++;
        if (actual !== exp_v) begin
            fails++;
            $display("  [FAIL] %-48s actual=0x%08x  expected=0x%08x  @%0t",
                     name, actual, exp_v, $time);
        end else begin
            $display("  [PASS] %-48s = 0x%08x", name, actual);
        end
    endtask

    task automatic chk1(input string name, input logic actual, input logic exp_v);
        checks++;
        if (actual !== exp_v) begin
            fails++;
            $display("  [FAIL] %-48s actual=%b  expected=%b  @%0t",
                     name, actual, exp_v, $time);
        end else begin
            $display("  [PASS] %-48s = %b", name, actual);
        end
    endtask

    // ------------------------------------------------------------- utilities
    task automatic clear_forces();
        release u_cpu.ds_allowin;
        release u_cpu.br_bus;
        release u_cpu.wb_ex;
        release u_cpu.ex_entry;
        release u_cpu.bp_query_hit;
        release u_cpu.bp_predict_taken;
        release u_cpu.bp_predict_target;
        // 本 TB 注入的是"合成预测"，与真实指令流不一致；若让真 ID 参与判断，
        // 它会按实际后继发出纠正，把 IF 自身的行为掩盖掉。
        // 因此默认把纠正总线压成 0（等价于 BP_ENABLE=0 时无纠正的状态），
        // 需要测纠正的场景再单独 force 覆盖。
        force u_cpu.br_bus = 33'b0;
    endtask

    // 复位并停在"首个取指请求已发出、尚未被时钟采样"的那一拍
    // 注意：mycpu_top 内部 reset 是寄存器（reset <= !resetn），
    // 故撤销 resetn 后需再过一个上升沿，reset 才真正撤销
    task automatic reset_to_first_req();
        resetn = 1'b0;
        repeat (4) @(posedge clk);
        @(negedge clk);
        #1;
        resetn = 1'b1;
        @(posedge clk);     // 本沿复位寄存器被撤销
        #1;                 // 组合稳定：本拍 inst_en/inst_addr 已可观察
    endtask

    // 复位后走完首个请求的采样沿，进入"第一条指令已就绪"的稳态
    task automatic reset_to_first_inst();
        reset_to_first_req();
        @(posedge clk);
        #1;
    endtask

    // ============================================================== BP8
    task automatic scen_bp8();
        $display("\n===== BP8: reset first fetch address =====");
        clear_forces();
        force u_cpu.ds_allowin = 1'b1;
        reset_to_first_req();

        chk1 ("BP8.1 first request issued",            inst_en,  1'b1);
        chk32("BP8.2 reset fetch addr is 0x1c000000",  inst_addr, 32'h1c00_0000);
        chk32("BP8.3 query addr equals request addr",  bp_query_pc, 32'h1c00_0000);
        chk32("BP8.4 reset cursor is 0x1c000000",      bp_next_pc_r, 32'h1c00_0000);
        chk1 ("BP8.5 fetch addr is aligned",           fetch_req, 1'b1);
    endtask

    // ============================================================== BP1
    task automatic scen_bp1();
        $display("\n===== BP1: prediction info aligned with RAM response =====");
        clear_forces();
        force u_cpu.ds_allowin       = 1'b1;
        force u_cpu.bp_query_hit     = 1'b1;
        force u_cpu.bp_predict_taken = 1'b1;
        force u_cpu.bp_predict_target= 32'h1c00_2000;
        reset_to_first_req();

        chk32("BP1.1 first request addr",              inst_addr, 32'h1c00_0000);
        chk32("BP1.2 query addr = request addr",       bp_query_pc, 32'h1c00_0000);

        @(posedge clk); #1;                 // 请求被接受，预测信息随之锁存
        chk32("BP1.3 fs_pc captured",                  fs_pc,          32'h1c00_0000);
        chk1 ("BP1.4 fs_valid set",                    fs_valid,       1'b1);
        chk1 ("BP1.5 bp hit latched",                  bp_hit_r,       1'b1);
        chk1 ("BP1.6 bp taken latched",                bp_taken_r,     1'b1);
        chk32("BP1.7 bp next_pc latched",              bp_next_pc_r,   32'h1c00_2000);
        chk1 ("BP1.8 bp hit field on bus",             fs_to_ds_bp[33],1'b1);
        chk1 ("BP1.9 bp taken field on bus",           fs_to_ds_bp[32],1'b1);
        chk32("BP1.10 bp next_pc field on bus",        fs_to_ds_bp[31:0], 32'h1c00_2000);
        // 关键：预测命中且实际跳转时，指令不得被取消
        chk1 ("BP1.11 predicted-taken instr NOT killed", fs_to_ds_valid, 1'b1);
        // 游标按预测前进，而不是 PC+4
        chk32("BP1.12 cursor advanced by prediction",  seq_pc,        32'h1c00_2000);
        chk32("BP1.13 next request follows prediction",inst_addr,     32'h1c00_2000);
    endtask

    // ============================================================== BP2
    task automatic scen_bp2();
        $display("\n===== BP2: hold while IF blocked by ID =====");
        clear_forces();
        force u_cpu.ds_allowin       = 1'b1;
        force u_cpu.bp_query_hit     = 1'b1;
        force u_cpu.bp_predict_taken = 1'b1;
        force u_cpu.bp_predict_target= 32'h1c00_2000;
        reset_to_first_inst();
        chk32("BP2.1 fs_pc before blocking",           fs_pc,        32'h1c00_0000);
        chk32("BP2.2 bp info before blocking",         fs_to_ds_bp[31:0], 32'h1c00_2000);

        // 阻塞 ID，并在阻塞期间把预测查询换成另一个值
        @(negedge clk);
        force u_cpu.ds_allowin = 1'b0;
        force u_cpu.bp_predict_target = 32'h1c00_9000;
        force u_cpu.bp_predict_taken  = 1'b0;
        repeat (3) begin
            @(posedge clk); #1;
        end

        chk1 ("BP2.3 no request while blocked",        inst_en,      1'b0);
        chk32("BP2.4 PC held across blocking",         fs_pc,        32'h1c00_0000);
        chk1 ("BP2.5 instruction still valid",         fs_valid,     1'b1);
        chk1 ("BP2.6 bp taken NOT re-sampled",         fs_to_ds_bp[32], 1'b1);
        chk32("BP2.7 bp next_pc NOT re-sampled",       fs_to_ds_bp[31:0], 32'h1c00_2000);
        chk32("BP2.8 latched bp_next_pc unchanged",    bp_next_pc_r, 32'h1c00_2000);

        @(negedge clk);
        force u_cpu.ds_allowin = 1'b1;
        #1;
        chk1 ("BP2.9 request resumes after release",   inst_en,      1'b1);
        chk32("BP2.10 resumes at predicted successor",  inst_addr,   32'h1c00_2000);
    endtask

    // ============================================================== BP3
    task automatic scen_bp3();
        $display("\n===== BP3: correction issues a new request in the same cycle =====");
        clear_forces();
        force u_cpu.ds_allowin = 1'b1;
        reset_to_first_inst();            // 无预测：fs_pc=0x1c000000, 游标 0x1c000004
        chk32("BP3.1 seq successor without prediction", seq_pc,     32'h1c00_0004);
        chk1 ("BP3.2 instruction valid before correction", fs_valid, 1'b1);

        @(negedge clk);
        force u_cpu.br_bus = {1'b1, 32'h1c00_3000};   // ID 判定预测错误
        #1;
        chk1 ("BP3.3 redirect valid seen by IF",       bp_redirect_valid, 1'b1);
        chk32("BP3.4 redirect target seen by IF",      bp_redirect_pc, 32'h1c00_3000);
        chk1 ("BP3.5 stale IF instr NOT sent to ID",   fs_to_ds_valid, 1'b0);
        chk1 ("BP3.6 new request issued same cycle",   inst_en,      1'b1);
        chk32("BP3.7 new request goes to target",      inst_addr,    32'h1c00_3000);

        @(posedge clk); #1;
        chk32("BP3.8 fs_pc follows correction",        fs_pc,        32'h1c00_3000);
        chk1 ("BP3.9 new response NOT discarded",      fs_valid,     1'b1);
        chk1 ("BP3.10 no spurious ADEF on aligned target", fs_to_ds_ex[48], 1'b0);

        // 真实 ID 的纠正只拉一拍；撤掉后才能观察"新指令能否进 ID"
        @(negedge clk);
        release u_cpu.br_bus;
        #1;
        chk1 ("BP3.11 instr reaches ID once correction drops", fs_to_ds_valid, 1'b1);
    endtask

    // ============================================================== BP4
    task automatic scen_bp4();
        $display("\n===== BP4: WB flush wins over same-cycle correction =====");
        clear_forces();
        force u_cpu.ds_allowin = 1'b1;
        reset_to_first_inst();

        @(negedge clk);
        force u_cpu.wb_ex     = 1'b1;
        force u_cpu.ex_entry  = 32'h1c00_4000;
        force u_cpu.br_bus    = {1'b1, 32'h1c00_3000};   // 同拍纠正
        #1;
        chk1 ("BP4.1 pipe_flush active",               pipe_flush,   1'b1);
        chk32("BP4.2 redirect_pc is ex_entry",         redirect_pc,  32'h1c00_4000);
        chk1 ("BP4.3 no request in flush cycle",       inst_en,      1'b0);
        chk1 ("BP4.4 stale instr not sent to ID",      fs_to_ds_valid, 1'b0);

        @(posedge clk); #1;
        chk1 ("BP4.5 WB target latched",               redirect_pending, 1'b1);
        chk32("BP4.6 latched target is WB target",     redirect_pc_r, 32'h1c00_4000);

        @(negedge clk);
        release u_cpu.wb_ex;
        release u_cpu.ex_entry;
        #1;
        chk1 ("BP4.7 request issued after flush",      inst_en,      1'b1);
        chk32("BP4.8 WB target wins over correction",  inst_addr,    32'h1c00_4000);

        @(posedge clk); #1;
        chk32("BP4.9 fs_pc is WB target",              fs_pc,        32'h1c00_4000);
        chk1 ("BP4.10 pending consumed",               redirect_pending, 1'b0);

        @(negedge clk);
        release u_cpu.br_bus;
    endtask

    // ============================================================== BP5
    task automatic scen_bp5();
        $display("\n===== BP5: latched target not lost or overridden while blocked =====");
        clear_forces();
        force u_cpu.ds_allowin = 1'b1;
        reset_to_first_inst();                  // fs_pc=0x1c000000, fs_valid=1

        // 在 ID 被阻塞的那一拍发生冲刷：目标被锁存
        @(negedge clk);
        force u_cpu.ds_allowin = 1'b0;
        force u_cpu.wb_ex      = 1'b1;
        force u_cpu.ex_entry   = 32'h1c00_5000;
        @(posedge clk); #1;
        chk1 ("BP5.1 target latched while blocked",    redirect_pending, 1'b1);
        chk32("BP5.2 latched target value",            redirect_pc_r, 32'h1c00_5000);
        chk1 ("BP5.3 stale instr dropped by flush",    fs_valid,     1'b0);

        // 下一拍仍被阻塞，且同拍来了一个纠正：锁存目标优先，不能被覆盖或丢失
        @(negedge clk);
        release u_cpu.wb_ex;
        release u_cpu.ex_entry;
        force u_cpu.br_bus = {1'b1, 32'h1c00_5800};
        #1;
        chk1 ("BP5.4 request issued although ds_allowin=0", inst_en,  1'b1);
        chk32("BP5.5 request goes to held target",     inst_addr,    32'h1c00_5000);
        chk32("BP5.6 pending not overridden by correction", redirect_pc_r, 32'h1c00_5000);

        @(posedge clk); #1;
        chk32("BP5.7 fs_pc follows held target",       fs_pc,        32'h1c00_5000);
        chk1 ("BP5.8 pending consumed after issue",    redirect_pending, 1'b0);

        @(negedge clk);
        release u_cpu.br_bus;
    endtask

    // ============================================================== BP6
    task automatic scen_bp6();
        $display("\n===== BP6: correction to misaligned target generates ADEF =====");
        clear_forces();
        force u_cpu.ds_allowin = 1'b1;
        reset_to_first_inst();

        @(negedge clk);
        force u_cpu.br_bus = {1'b1, 32'h1c00_6002};   // 未对齐的纠正目标
        #1;
        chk1 ("BP6.1 no RAM request for misaligned addr", inst_en,   1'b0);
        chk1 ("BP6.2 fetch exception generated",        fetch_exc,   1'b1);

        @(posedge clk); #1;
        chk32("BP6.3 misaligned PC latched",            fs_pc,       32'h1c00_6002);
        chk1 ("BP6.4 ADEF marker valid",                fs_to_ds_ex[48], 1'b1);
        chk32("BP6.5 ADEF badv = misaligned PC",        fs_to_ds_ex[31:0], 32'h1c00_6002);
        chk1 ("BP6.6 badv_valid set",                   fs_to_ds_ex[32], 1'b1);
        chk32("BP6.7 instruction word forced to zero",  fs_to_ds_bus[63:32], 32'h0);
        chk1 ("BP6.8 bp hit forced to 0",               fs_to_ds_bp[33], 1'b0);
        chk1 ("BP6.9 bp taken forced to 0",             fs_to_ds_bp[32], 1'b0);
        chk32("BP6.10 bp next_pc forced to PC+4",       fs_to_ds_bp[31:0], 32'h1c00_6006);
    endtask

    // ============================================================== BP7
    task automatic scen_bp7();
        $display("\n===== BP7: ADEF on the wrong path is cancelled =====");
        clear_forces();
        force u_cpu.ds_allowin = 1'b1;
        reset_to_first_inst();

        // 先制造一个属于错误路径的 ADEF
        @(negedge clk);
        force u_cpu.br_bus = {1'b1, 32'h1c00_6002};
        @(posedge clk); #1;
        chk1 ("BP7.1 ADEF present on wrong path",       fs_to_ds_ex[48], 1'b1);

        // 撤掉纠正（真实 ID 只拉一拍）：此拍 ADEF 应当可以进 ID
        @(negedge clk);
        release u_cpu.br_bus;
        #1;
        chk1 ("BP7.2 ADEF would reach ID",              fs_to_ds_valid, 1'b1);
        chk1 ("BP7.3 ADEF marker still present",        fs_to_ds_ex[48], 1'b1);

        // 同拍再纠正到正确目标：错误路径的 ADEF 必须随指令一起被取消
        force u_cpu.br_bus = {1'b1, 32'h1c00_7000};
        #1;
        chk1 ("BP7.4 wrong-path ADEF no longer sent",   fs_to_ds_valid, 1'b0);
        chk1 ("BP7.5 new request issued",               inst_en,       1'b1);
        chk32("BP7.6 new request goes to correct target", inst_addr,   32'h1c00_7000);

        @(posedge clk); #1;
        chk32("BP7.7 fs_pc follows correct target",     fs_pc,        32'h1c00_7000);
        chk1 ("BP7.8 no ADEF on correct path",          fs_to_ds_ex[48], 1'b0);
        chk1 ("BP7.9 instruction valid again",          fs_valid,     1'b1);

        @(negedge clk);
        release u_cpu.br_bus;
        #1;
        chk1 ("BP7.10 reaches ID once correction drops", fs_to_ds_valid, 1'b1);
    endtask

    // ============================================================== main
    initial begin
        $display("================================================================");
        $display(" C P1: IF prediction query / latch / correction (module level)");
        $display(" Stimulus forced on ds_allowin / br_bus / bp_query_* / wb_ex.");
        $display(" Module stimulus per 05-validation; NOT a claim that the");
        $display(" course program triggers these cases naturally.");
        $display("================================================================");

        scen_bp8();
        scen_bp1();
        scen_bp2();
        scen_bp3();
        scen_bp4();
        scen_bp5();
        scen_bp6();
        scen_bp7();

        clear_forces();
        $display("\n================================================================");
        $display("BP_FETCH_SUMMARY checks=%0d fails=%0d", checks, fails);
        if (fails == 0) $display("BP_FETCH_PASS");
        else            $display("BP_FETCH_FAIL");
        $display("================================================================");
        $finish;
    end

    // 超时保护
    initial begin
        #200000;
        $display("BP_FETCH_FAIL timeout");
        $finish;
    end

endmodule

// ---------------------------------------------------------------- IP stubs
// div_* 是 VHDL 的 IP 模型，命令行无法编译；本测试不涉除法，用占位模块顶上，
// 一旦被请求立即 $fatal，兼作"IF 测试不应触发除法"的护栏。
module div_signed(
    input         aclk,
    input         aresetn,
    input         s_axis_divisor_tvalid,
    input  [31:0] s_axis_divisor_tdata,
    input         s_axis_dividend_tvalid,
    input  [31:0] s_axis_dividend_tdata,
    output        m_axis_dout_tvalid,
    output [63:0] m_axis_dout_tdata
);
    assign m_axis_dout_tvalid = 1'b0;
    assign m_axis_dout_tdata  = 64'b0;
    always @(posedge aclk)
        if (aresetn && (s_axis_divisor_tvalid || s_axis_dividend_tvalid))
            $fatal(1, "div_signed requested in BP fetch test");
endmodule

module div_unsigned(
    input         aclk,
    input         aresetn,
    input         s_axis_divisor_tvalid,
    input  [31:0] s_axis_divisor_tdata,
    input         s_axis_dividend_tvalid,
    input  [31:0] s_axis_dividend_tdata,
    output        m_axis_dout_tvalid,
    output [63:0] m_axis_dout_tdata
);
    assign m_axis_dout_tvalid = 1'b0;
    assign m_axis_dout_tdata  = 64'b0;
    always @(posedge aclk)
        if (aresetn && (s_axis_divisor_tvalid || s_axis_dividend_tvalid))
            $fatal(1, "div_unsigned requested in BP fetch test");
endmodule
