`timescale 1ns/1ps
// =============================================================================
// C01/C02/C03 module-level test: IF stage flush / redirect timing
//
// Level : mycpu_top module-level. Instruction RAM is a synchronous-read model
//         (1-cycle latency), content fixed to addi.w $r0,$r0,0; only fetch
//         timing is observed, instruction semantics are irrelevant.
// Stim  : force on top-level ds_allowin / wb_ex / ex_entry / br_bus.
//         This is the "module stimulus" allowed by document/05-validation.md.
//         This bench does NOT claim the course program triggers these cases
//         naturally.
//
// Checks (see document/05-validation.md C01~C03):
//   C01  pipe_flush while IF blocked by ID (ds_allowin=0):
//        discard old response, latch redirect target, never lose the jump
//   C02  branch and WB event in the same cycle (WB wins);
//        back-to-back redirects (newer target overrides pending one)
//   C03  BRAM old response arrives after flush:
//        must not be paired with the new PC
// =============================================================================
module tb_if_flush;

    // ---------------------------------------------------------------- clock
    reg clk    = 1'b0;
    reg resetn = 1'b0;
    always #10 clk = ~clk;              // 20 ns period, 50 MHz

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

    // ----------------------------- instruction RAM: synchronous, 1-cycle latency
    // Address sampled while en is high, data appears on rdata next cycle.
    // Matches blk_mem_gen behaviour and IF's fetch_req/fs_valid pairing.
    localparam [31:0] NOP = 32'h0280_0000;   // addi.w $r0,$r0,0

    reg [31:0] inst_rdata_r;
    always @(posedge clk) begin
        if (inst_en) inst_rdata_r <= NOP;
    end
    assign inst_rdata = inst_rdata_r;

    // ------------------------------------------------------- internal probes
    wire         fs_valid         = u_cpu.u_if_stage.fs_valid;
    wire         fetch_req        = u_cpu.u_if_stage.fetch_req;
    wire [31:0]  fetch_addr       = u_cpu.u_if_stage.fetch_addr;
    wire         fs_allowin       = u_cpu.u_if_stage.fs_allowin;
    wire         redirect_pending = u_cpu.u_if_stage.redirect_pending;
    wire [31:0]  redirect_pc_r    = u_cpu.u_if_stage.redirect_pc_r;
    wire [31:0]  fs_pc            = u_cpu.u_if_stage.fs_pc;
    wire         fs_to_ds_valid   = u_cpu.u_if_stage.fs_to_ds_valid;
    wire [63:0]  fs_to_ds_bus     = u_cpu.u_if_stage.fs_to_ds_bus;
    wire [48:0]  fs_to_ds_ex      = u_cpu.u_if_stage.fs_to_ds_ex;
    wire [31:0]  fs_inst          = u_cpu.u_if_stage.fs_inst;

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
            $display("  [FAIL] %-46s actual=0x%08x  expected=0x%08x  @%0t",
                     name, actual, exp_v, $time);
        end else begin
            $display("  [PASS] %-46s = 0x%08x", name, actual);
        end
    endtask

    task automatic chk1(input string name, input logic actual, input logic exp_v);
        checks++;
        if (actual !== exp_v) begin
            fails++;
            $display("  [FAIL] %-46s actual=%b  expected=%b  @%0t",
                     name, actual, exp_v, $time);
        end else begin
            $display("  [PASS] %-46s = %b", name, actual);
        end
    endtask

    // ---------------------------------------------------------------- reset
    // Leaves design at: reset deasserted, no fetch request issued yet this cycle
    task automatic do_reset();
        resetn = 1'b0;
        repeat (4) @(posedge clk);
        @(negedge clk);
        resetn = 1'b1;
        @(posedge clk);      // reset flop updates at this edge
        #1;
    endtask

    task automatic wait_fs_valid();
        int n = 0;
        while (fs_valid !== 1'b1 && n < 64) begin
            @(posedge clk); #1; n++;
        end
        if (n >= 64) $display("  [WARN] wait_fs_valid timeout");
    endtask

    task automatic wait_req_inflight();
        int n = 0;
        while (!(inst_en === 1'b1 && fs_valid === 1'b0) && n < 64) begin
            @(posedge clk); #1; n++;
        end
        if (n >= 64) $display("  [WARN] wait_req_inflight timeout");
    endtask

    // ============================================================== C01
    task automatic scen_c01();
        $display("\n===== C01: pipe_flush while IF blocked by ID (ds_allowin=0) =====");
        do_reset();
        wait_fs_valid();

        // Block ID
        @(negedge clk);
        force u_cpu.ds_allowin = 1'b0;

        @(posedge clk); #1;
        $display("  after block: fs_valid=%b fs_allowin=%b fetch_req=%b ds_allowin=%b",
                 fs_valid, fs_allowin, fetch_req, ds_allowin);
        chk1("C01.1 no new request while blocked",  fetch_req,   1'b0);
        chk1("C01.2 fs_valid holds while blocked",  fs_valid,    1'b1);
        chk1("C01.3 ds_allowin really zero",        ds_allowin,  1'b0);

        // Inject WB exception event in the same cycle
        force u_cpu.wb_ex    = 1'b1;
        force u_cpu.ex_entry = 32'h1c00_2000;
        #1;
        chk1("C01.4 pipe_flush active in flush cycle",   pipe_flush,     1'b1);
        chk1("C01.5 stale instr not sent to ID",         fs_to_ds_valid, 1'b0);
        chk1("C01.6 no request issued in flush cycle",   inst_en,        1'b0);
        chk32("C01.7 redirect target is ex_entry",       redirect_pc,    32'h1c00_2000);

        // Next edge: latch takes effect
        @(posedge clk); #1;
        chk1("C01.8 fs_valid cleared after flush",   fs_valid,         1'b0);
        chk1("C01.9 target latched",                 redirect_pending, 1'b1);
        chk32("C01.10 latched target value",         redirect_pc_r,    32'h1c00_2000);

        // Release the event, KEEP ds_allowin=0 -> the jump must not be lost
        @(negedge clk);
        release u_cpu.wb_ex;
        release u_cpu.ex_entry;
        #1;   // sample combinational state of this cycle, before next posedge
        $display("  after release: fs_valid=%b fs_allowin=%b fetch_req=%b ds_allowin=%b",
                 fs_valid, fs_allowin, fetch_req, ds_allowin);
        chk1("C01.11 request issued despite ds_allowin=0", inst_en,   1'b1);
        chk32("C01.12 request address is redirect target",  inst_addr, 32'h1c00_2000);

        // Next edge: request sampled, new instruction arrives one cycle later
        @(posedge clk); #1;
        chk32("C01.13 fs_pc updated to target",      fs_pc,              32'h1c00_2000);
        chk1("C01.14 new instruction valid",         fs_valid,           1'b1);
        chk1("C01.15 new instruction can reach ID",  fs_to_ds_valid,     1'b1);
        chk32("C01.16 PC field on fs_to_ds bus",     fs_to_ds_bus[31:0], 32'h1c00_2000);
        chk1("C01.17 latched target consumed",       redirect_pending,   1'b0);

        @(negedge clk);
        release u_cpu.ds_allowin;
        repeat (2) @(posedge clk);
    endtask

    // ============================================================== C02
    task automatic scen_c02();
        $display("\n===== C02: branch and WB event same cycle / back-to-back redirect =====");
        do_reset();
        wait_fs_valid();

        // (a) branch and flush in the same cycle: WB event must win
        @(negedge clk);
        force u_cpu.br_bus    = {1'b1, 32'h1c00_1000};   // br_taken, br_target
        force u_cpu.wb_ex     = 1'b1;
        force u_cpu.ex_entry  = 32'h1c00_2000;

        @(posedge clk); #1;
        chk1("C02.1 pipe_flush active same cycle",       pipe_flush,     1'b1);
        chk1("C02.2 branch cancelled by flush",          fs_to_ds_valid, 1'b0);
        chk32("C02.3 combinational redirect = ex_entry", redirect_pc,    32'h1c00_2000);

        @(posedge clk); #1;
        chk32("C02.4 WB event wins over branch",         redirect_pc_r,  32'h1c00_2000);

        // (b) back-to-back redirect: newer target overrides pending one
        @(negedge clk);
        release u_cpu.br_bus;
        force u_cpu.ex_entry = 32'h1c00_3000;
        @(posedge clk); #1;
        chk32("C02.5 first redirect latched",            redirect_pc_r,  32'h1c00_3000);

        @(negedge clk);
        force u_cpu.ex_entry = 32'h1c00_4000;
        @(posedge clk); #1;
        chk32("C02.6 second redirect overrides",         redirect_pc_r,  32'h1c00_4000);

        // Release and observe which target is actually fetched
        @(negedge clk);
        release u_cpu.wb_ex;
        release u_cpu.ex_entry;
        #1;
        chk1("C02.7 fetch request after flush ends",     inst_en,        1'b1);
        chk32("C02.8 fetch address = second target",     inst_addr,      32'h1c00_4000);
        chk1("C02.9 first target never fetched",         inst_addr === 32'h1c00_3000, 1'b0);

        @(posedge clk); #1;
        chk32("C02.10 fs_pc = second target",            fs_pc,          32'h1c00_4000);

        repeat (2) @(posedge clk);
    endtask

    // ============================================================== C03
    task automatic scen_c03();
        $display("\n===== C03: BRAM old response arrives after flush =====");
        do_reset();
        wait_req_inflight();       // inst_en=1, response not back yet

        @(negedge clk);
        force u_cpu.wb_ex    = 1'b1;
        force u_cpu.ex_entry = 32'h1c00_5000;

        @(posedge clk); #1;
        // This cycle the old response shows up on inst_rdata while flush is active
        $display("  old response landed: fs_inst=0x%08x fs_valid(old)=%b fs_to_ds_valid=%b",
                 fs_inst, fs_valid, fs_to_ds_valid);
        chk1("C03.1 pipe_flush active",                    pipe_flush,     1'b1);
        chk1("C03.2 old response not sent to ID as valid", fs_to_ds_valid, 1'b0);

        @(posedge clk); #1;
        chk1("C03.3 old response dropped (fs_valid=0)",    fs_valid,       1'b0);
        chk32("C03.4 redirect target latched",             redirect_pc_r,  32'h1c00_5000);

        // Release flush so the new path can actually fetch
        @(negedge clk);
        release u_cpu.wb_ex;
        release u_cpu.ex_entry;
        #1;
        chk1("C03.5 request issued to new target",         inst_en,        1'b1);
        chk32("C03.6 request address = new target",        inst_addr,      32'h1c00_5000);

        @(posedge clk); #1;
        chk32("C03.7 fs_pc = new target",                  fs_pc,          32'h1c00_5000);
        chk1("C03.8 new instruction valid",                fs_valid,       1'b1);

        repeat (2) @(posedge clk);
    endtask

    // ============================================================== C04
    // ERTN flush path.
    // The full syscall -> handler -> ERTN closed loop on the real course image is
    // already covered by ex8 n47_syscall_ex_test (47/47 PASS, see G4 record).
    // What is NOT covered there is the pipeline-level fact that an ERTN flush
    // redirects to ertn_entry (never to ex_entry). ertn_entry is the CSR's ERA
    // output, so feeding a modified value exercises exactly the same path as
    // "modify ERA inside the handler, then ERTN".
    task automatic scen_c04();
        $display("\n===== C04: ERTN flush path (ertn_flush -> ertn_entry) =====");
        do_reset();
        wait_fs_valid();

        @(negedge clk);
        force u_cpu.wb_ex      = 1'b0;
        force u_cpu.ertn_flush = 1'b1;
        force u_cpu.ertn_entry = 32'h1c00_6000;
        force u_cpu.ex_entry   = 32'h1c00_2222;   // must NOT win when only ERTN fires

        #1;
        chk1 ("C04.1 pipe_flush driven by ERTN",       pipe_flush,  1'b1);
        chk32("C04.2 redirect target is ertn_entry",   redirect_pc, 32'h1c00_6000);
        chk1 ("C04.3 ex_entry does not win",           redirect_pc === 32'h1c00_2222, 1'b0);

        @(posedge clk); #1;
        chk1 ("C04.4 fs_valid cleared by ERTN flush",  fs_valid,        1'b0);
        chk32("C04.5 ERTN target latched",             redirect_pc_r,   32'h1c00_6000);

        @(negedge clk);
        release u_cpu.ertn_flush;
        release u_cpu.ertn_entry;
        release u_cpu.ex_entry;
        #1;
        chk1 ("C04.6 fetch issued after ERTN",         inst_en,     1'b1);
        chk32("C04.7 fetch address = ERTN target",     inst_addr,   32'h1c00_6000);

        @(posedge clk); #1;
        chk32("C04.8 fs_pc = ERTN target",             fs_pc,       32'h1c00_6000);
        chk1 ("C04.9 new instruction valid",           fs_valid,    1'b1);

        repeat (2) @(posedge clk);
    endtask

    // ============================================================== C05
    // ex9 ADEF: bad instruction PC (PC[1:0] != 0)
    //   04-ex9-design: IF must NOT issue a RAM request for a bad address, but
    //   must build a valid exception marker {inst=0, pc=bad PC, ADEF} and pass
    //   it to ID normally. ID must keep it instead of decoding inst=0 as INE.
    task automatic scen_c05();
        $display("\n===== C05: ADEF on misaligned instruction PC =====");
        do_reset();
        wait_fs_valid();

        // Redirect to a misaligned target (bit1 set)
        @(negedge clk);
        force u_cpu.wb_ex    = 1'b1;
        force u_cpu.ex_entry = 32'h1c00_7002;
        @(posedge clk); #1;
        chk1 ("C05.1 pipe_flush active",              pipe_flush, 1'b1);

        @(negedge clk);
        release u_cpu.wb_ex;
        release u_cpu.ex_entry;
        #1;
        // This cycle fetch_addr is the bad target
        chk1 ("C05.2 no RAM request for bad PC",      inst_en,    1'b0);
        chk32("C05.3 fetch address is the bad PC",    fetch_addr, 32'h1c00_7002);
        chk1 ("C05.4 next fetch is also misaligned",  inst_addr[1], 1'b1);

        @(posedge clk); #1;
        chk32("C05.5 fs_pc latched the bad PC",       fs_pc,            32'h1c00_7002);
        chk1 ("C05.6 marker is valid",                fs_valid,         1'b1);
        chk1 ("C05.7 marker can reach ID",            fs_to_ds_valid,   1'b1);
        chk1 ("C05.8 exc valid bit",                  fs_to_ds_ex[48],  1'b1);
        chk32("C05.9 ecode is ADEF (0x08)",           fs_to_ds_ex[47:42], 6'h08);
        chk32("C05.10 esubcode is 0",                 fs_to_ds_ex[41:33], 9'b0);
        chk1 ("C05.11 badv_valid",                    fs_to_ds_ex[32],  1'b1);
        chk32("C05.12 badv = bad PC",                 fs_to_ds_ex[31:0], 32'h1c00_7002);
        chk32("C05.13 instruction forced to 0",       fs_to_ds_bus[63:32], 32'b0);
        chk32("C05.14 PC field on bus",               fs_to_ds_bus[31:0], 32'h1c00_7002);
        chk1 ("C05.15 still no RAM request",          inst_en,          1'b0);

        @(posedge clk); #1;
        chk1 ("C05.16 ID keeps IF exception",         u_cpu.u_id_stage.fs_to_ds_ex_r[48], 1'b1);
        chk1 ("C05.17 ID ds_exc keeps ADEF",          u_cpu.u_id_stage.ds_exc[48], 1'b1);
        chk32("C05.18 ID ds_exc ecode",               u_cpu.u_id_stage.ds_exc[47:42], 6'h08);

        repeat (3) @(posedge clk);
    endtask

    // ============================================================== main
    initial begin
        $display("================================================================");
        $display(" C01~C05  IF flush / redirect / ADEF timing (module level)");
        $display(" Stimulus: ds_allowin / wb_ex / ertn_flush / ex_entry /");
        $display("           ertn_entry / br_bus forced.");
        $display(" This is module stimulus allowed by 05-validation, NOT a claim");
        $display(" that the course program triggers these cases naturally.");
        $display("================================================================");

        scen_c01();
        scen_c02();
        scen_c03();
        scen_c04();
        scen_c05();

        $display("\n================================================================");
        $display("IF_FLUSH_SUMMARY checks=%0d fails=%0d", checks, fails);
        if (fails == 0) $display("IF_FLUSH_PASS");
        else            $display("IF_FLUSH_FAIL");
        $display("================================================================");
        $finish;
    end

    initial begin
        #200_000;
        $display("IF_FLUSH_TIMEOUT");
        $finish;
    end

endmodule

// =============================================================================
// Divider placeholders: this bench never divides; a request is a hard error.
// Identical to the placeholders used in tests/team/pipeline/tb_ex8_smoke.sv
// =============================================================================
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
            $fatal(1, "div_signed requested in IF flush test");
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
            $fatal(1, "div_unsigned requested in IF flush test");
endmodule
