`timescale 1ns/1ps
// =============================================================================
// C06 module-level test: external hardware interrupt inputs
//
// Level : mycpu_top. hw_int_in is driven directly by this bench (a top-level
//         input port, so plain reg assignment, no force needed).
//         CSR writes go through the real csr write ports (csr_num/csr_we/
//         csr_wmask/csr_wvalue), forced at the top level, so the write path
//         itself is exercised rather than poking internal registers.
//
// Checks (document/05-validation.md C06):
//   - every bit of hw_int_in lands on the matching ESTAT.IS[9:2] bit
//   - all-zero input clears IS[9:2]
//   - IS[10] and IS[12] stay 0 (not implemented)
//   - has_int requires both CRMD.IE and a matching ECFG.LIE enable
//
// SoC port check (no floating input) is a static check on soc_lite_top.v,
// recorded separately; it cannot be observed from this bench.
// =============================================================================
module tb_int_hw;

    reg clk    = 1'b0;
    reg resetn = 1'b0;
    always #10 clk = ~clk;              // 20 ns

    reg  [7:0] hw_int_in = 8'b0;        // driven by this bench

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
        .hw_int_in       (hw_int_in),
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

    localparam [31:0] NOP = 32'h0280_0000;   // addi.w $r0,$r0,0
    reg [31:0] inst_rdata_r;
    always @(posedge clk) if (inst_en) inst_rdata_r <= NOP;
    assign inst_rdata = inst_rdata_r;

    // ------------------------------------------------------------- probes
    wire [31:0] ESTAT   = u_cpu.u_csr.ESTAT;
    wire [31:0] ECFG    = u_cpu.u_csr.ECFG;
    wire [31:0] CRMD    = u_cpu.u_csr.CRMD;
    wire        has_int = u_cpu.has_int;

    // ------------------------------------------------------------- checkers
    int checks = 0, fails = 0;

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

    // ---------------------------------------------------------------- reset
    task automatic do_reset();
        resetn = 1'b0;
        hw_int_in = 8'b0;
        repeat (4) @(posedge clk);
        @(negedge clk);
        resetn = 1'b1;
        @(posedge clk); #1;
    endtask

    // CSR write through the real write ports (one pulse)
    // NOTE: must be a static task - force cannot reference automatic variables
    task csr_write(input [13:0] num, input [31:0] mask, input [31:0] value);
        @(negedge clk);
        force u_cpu.csr_num    = num;
        force u_cpu.csr_we     = 1'b1;
        force u_cpu.csr_wmask  = mask;
        force u_cpu.csr_wvalue = value;
        @(posedge clk); #1;
        @(negedge clk);
        release u_cpu.csr_num;
        release u_cpu.csr_we;
        release u_cpu.csr_wmask;
        release u_cpu.csr_wvalue;
        #1;
    endtask

    // =====================================================================
    initial begin
        $display("================================================================");
        $display(" C06  external hardware interrupt inputs (module level)");
        $display(" hw_int_in driven by bench; CSR writes via real write ports.");
        $display("================================================================");

        do_reset();
        repeat (2) @(posedge clk); #1;

        // ---- all-zero after reset
        $display("\n----- all zero -----");
        chk32("C06.1  IS[9:2] cleared with hw_int_in=0", ESTAT[9:2], 8'h00);
        chk1 ("C06.2  no interrupt pending",              has_int,    1'b0);

        // ---- one bit at a time: the whole byte must match exactly
        $display("\n----- one bit at a time -----");
        for (int i = 0; i < 8; i++) begin
            hw_int_in = (8'b1 << i);
            @(posedge clk); #1;
            chk32($sformatf("C06.%0d  hw_int_in[%0d] -> IS[%0d]", i + 3, i, i + 2),
                  ESTAT[9:2], (8'h01 << i));
        end

        // ---- all ones
        $display("\n----- all ones -----");
        hw_int_in = 8'hFF;
        @(posedge clk); #1;
        chk32("C06.11 IS[9:2] = 0xFF with hw_int_in=0xFF", ESTAT[9:2], 8'hFF);
        chk1 ("C06.12 IS[10] stays 0",                     ESTAT[10], 1'b0);
        chk1 ("C06.13 IS[12] stays 0",                     ESTAT[12], 1'b0);

        // ---- enable chain: has_int needs CRMD.IE && (ESTAT & ECFG)
        $display("\n----- enable chain -----");
        chk1 ("C06.14 LIE=0, IE=0 -> has_int=0",           has_int, 1'b0);

        // CRMD.IE = bit2
        csr_write(14'h000, 32'h0000_0004, 32'h0000_0004);
        chk1 ("C06.15 IE=1 but LIE=0 -> has_int=0",        has_int, 1'b0);

        // ECFG.LIE[9:2] enable (mask 0x000003fc covers LIE[9:0])
        csr_write(14'h004, 32'h0000_03fc, 32'h0000_03fc);
        chk1 ("C06.16 IE=1 and LIE enabled -> has_int=1",  has_int, 1'b1);
        $display("        (CRMD=0x%08x ECFG=0x%08x ESTAT=0x%08x)", CRMD, ECFG, ESTAT);

        // ---- dropping the request clears it
        $display("\n----- request dropped -----");
        hw_int_in = 8'b0;
        @(posedge clk); #1;
        chk32("C06.17 IS[9:2] back to 0",                  ESTAT[9:2], 8'h00);
        chk1 ("C06.18 has_int back to 0",                  has_int,    1'b0);

        $display("\n================================================================");
        $display("INT_HW_SUMMARY checks=%0d fails=%0d", checks, fails);
        if (fails == 0) $display("INT_HW_PASS");
        else            $display("INT_HW_FAIL");
        $display("================================================================");
        $finish;
    end

    initial begin
        #200_000;
        $display("INT_HW_TIMEOUT");
        $finish;
    end

endmodule

// Divider placeholders (same as tests/team/pipeline/tb_ex8_smoke.sv)
module div_signed(
    input aclk, input aresetn,
    input s_axis_divisor_tvalid, input [31:0] s_axis_divisor_tdata,
    input s_axis_dividend_tvalid, input [31:0] s_axis_dividend_tdata,
    output m_axis_dout_tvalid, output [63:0] m_axis_dout_tdata
);
    assign m_axis_dout_tvalid = 1'b0;
    assign m_axis_dout_tdata  = 64'b0;
    always @(posedge aclk)
        if (aresetn && (s_axis_divisor_tvalid || s_axis_dividend_tvalid))
            $fatal(1, "div_signed requested in interrupt test");
endmodule

module div_unsigned(
    input aclk, input aresetn,
    input s_axis_divisor_tvalid, input [31:0] s_axis_divisor_tdata,
    input s_axis_dividend_tvalid, input [31:0] s_axis_dividend_tdata,
    output m_axis_dout_tvalid, output [63:0] m_axis_dout_tdata
);
    assign m_axis_dout_tvalid = 1'b0;
    assign m_axis_dout_tdata  = 64'b0;
    always @(posedge aclk)
        if (aresetn && (s_axis_divisor_tvalid || s_axis_dividend_tvalid))
            $fatal(1, "div_unsigned requested in interrupt test");
endmodule
