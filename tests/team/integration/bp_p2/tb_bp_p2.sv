`timescale 1ns/1ps
// =============================================================================
// P2 定向程序测试台：行为级指令 / 数据 RAM + 结果断言
//
// 目的：本机没有交叉工具链，无法把 .S 编成课程镜像。这里用 asm.py 直接生成
//       32 位机器字（编码已对照课程反汇编自检），由本 TB 装入行为级指令 RAM，
//       因此可以任意造分支序列、验证"错误路径不产生架构副作用"。
//
// 结构：
//   指令 RAM：1024×32，同步读 1 拍（与 blk_mem_gen READ_LATENCY=1 一致）
//   数据 RAM：1024×32，同步读 1 拍，按字节使能写入
//   结束标志：程序向 0x1c100ffc 写入任意值；此后等 40 拍再核对结果
//   期望文件：expect.txt，每行 "reg <编号> <十六进制>" 或 "mem <字号> <十六进制>"
//
// 说明：本 TB 不例化 A 的预测器，顶层预测输入为 tie-off（等价 BP_ENABLE=0），
//       因此它验证的是"预测关闭时的架构行为"，可作为 BP=1 的对照基线。
// =============================================================================
module tb_bp_p2;

    localparam [31:0] MAGIC = 32'h1c10_0100;

    // 编译加 -d BP_ON 即开启预测；默认关闭作为对照基线
`ifdef BP_ON
    localparam BP_EN = 1'b1;
`else
    localparam BP_EN = 1'b0;
`endif

    reg clk    = 1'b0;
    reg resetn = 1'b0;
    always #10 clk = ~clk;

    // ---------------------------------------------------------------- DUT
    wire        inst_en;
    wire [ 3:0] inst_we;
    wire [31:0] inst_addr, inst_wdata, inst_rdata;
    wire        data_en;
    wire [ 3:0] data_we;
    wire [31:0] data_addr, data_wdata, data_rdata;
    wire [31:0] dbg_pc, dbg_wdata;
    wire [ 3:0] dbg_rf_we;
    wire [ 4:0] dbg_wnum;

    mycpu_top #(
        .BP_ENABLE       (BP_EN)
    ) u_cpu (
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
        .data_sram_rdata (data_rdata),
        .debug_wb_pc     (dbg_pc),
        .debug_wb_rf_we  (dbg_rf_we),
        .debug_wb_rf_wnum(dbg_wnum),
        .debug_wb_rf_wdata(dbg_wdata)
    );

    // ------------------------------------------------------- 行为级指令 RAM
    reg [31:0] imem [0:1023];
    reg [31:0] inst_rdata_r;

    always @(posedge clk) begin
        if (inst_en) inst_rdata_r <= imem[inst_addr[11:2]];
    end
    assign inst_rdata = inst_rdata_r;

    // ------------------------------------------------------- 行为级数据 RAM
    reg [31:0] dmem [0:1023];
    reg [31:0] data_rdata_r;

    integer di;
    always @(posedge clk) begin
        if (data_en) begin
            di = data_addr[11:2];
            if (data_we != 4'b0000) begin
                if (data_we[0]) dmem[di][ 7: 0] <= data_wdata[ 7: 0];
                if (data_we[1]) dmem[di][15: 8] <= data_wdata[15: 8];
                if (data_we[2]) dmem[di][23:16] <= data_wdata[23:16];
                if (data_we[3]) dmem[di][31:24] <= data_wdata[31:24];
            end else begin
                data_rdata_r <= dmem[di];
            end
        end
    end
    assign data_rdata = data_rdata_r;

    // ------------------------------------------------------------ 结束标志
    reg magic_seen = 1'b0;
    always @(posedge clk) begin
        if (data_en && (data_we != 4'b0000) && (data_addr == MAGIC))
            magic_seen <= 1'b1;
    end

    // ------------------------------------------------------------- 期望结果
    reg [31:0] exp_reg [0:31];
    reg        has_reg [0:31];
    reg [31:0] exp_mem [0:1023];
    reg        has_mem [0:1023];

    integer k;
    initial begin
        for (k = 0; k < 32; k = k + 1)  has_reg[k] = 1'b0;
        for (k = 0; k < 1024; k = k + 1) has_mem[k] = 1'b0;
        // 存储器预置为确定值：数据 RAM 全 0，指令 RAM 全 NOP。
        // 这样"没被写"的地址读出 0（而不是 X），"被写"才可能非 0，
        // 错误路径的写操作才有一个确定的判据。
        for (k = 0; k < 1024; k = k + 1) begin
            dmem[k] = 32'h0;
            imem[k] = 32'h0280_0000;
        end
        $readmemh("prog.hex", imem);
        load_expect("expect.txt");
    end

    task load_expect(input string path);
        integer fd, rc, idx;
        reg [23:0] kind;
        reg [31:0] val;
        fd = $fopen(path, "r");
        if (fd == 0) begin
            $display("  [FAIL] 打不开期望文件 %s", path);
            $finish;
        end
        rc = $fscanf(fd, "%s %d %h\n", kind, idx, val);
        while (rc == 3) begin
            if (kind == "reg") begin
                exp_reg[idx] = val; has_reg[idx] = 1'b1;
            end else if (kind == "mem") begin
                exp_mem[idx] = val; has_mem[idx] = 1'b1;
            end else begin
                $display("  [WARN] 未知期望类型 %s", kind);
            end
            rc = $fscanf(fd, "%s %d %h\n", kind, idx, val);
        end
        $fclose(fd);
    endtask

    // --------------------------------------------------------------- 检查器
    int checks = 0;
    int fails  = 0;

    task chk32(input string name, input [31:0] actual, input [31:0] exp_v);
        checks++;
        if (actual !== exp_v) begin
            fails++;
            $display("  [FAIL] %-34s actual=0x%08x expected=0x%08x", name, actual, exp_v);
        end else begin
            $display("  [PASS] %-34s = 0x%08x", name, actual);
        end
    endtask

    // ---------------------------------------------------------------- 主流程
    integer cyc;
    initial begin
        $display("================================================================");
        $display(" P2 directed program test (BP disabled: predictor inputs tied 0)");
        $display("================================================================");

        resetn = 1'b0;
        repeat (8) @(posedge clk);
        @(negedge clk);
        resetn = 1'b1;

        cyc = 0;
        while (magic_seen !== 1'b1 && cyc < 40000) begin
            @(posedge clk);
            cyc = cyc + 1;
        end
        if (magic_seen !== 1'b1) begin
            $display("  [FAIL] 程序未在 %0d 拍内到达结束标志，最后 wb_pc=0x%08x", cyc, dbg_pc);
            $display("P2_FAIL timeout");
            $finish;
        end
        $display("  [INFO] 到达结束标志，用时 %0d 拍，最后 wb_pc=0x%08x", cyc, dbg_pc);

        repeat (40) @(posedge clk);

        for (k = 1; k < 32; k = k + 1) begin
            if (has_reg[k]) begin
                chk32($sformatf("reg r%0d", k), u_cpu.u_id_stage.u_regfile.rf[k], exp_reg[k]);
            end
        end
        for (k = 0; k < 1024; k = k + 1) begin
            if (has_mem[k]) begin
                chk32($sformatf("mem[%0d]", k), dmem[k], exp_mem[k]);
            end
        end

        $display("----------------------------------------------------------------");
        $display("P2_SUMMARY checks=%0d fails=%0d cycles=%0d", checks, fails, cyc);
        if (fails == 0) $display("P2_PASS");
        else            $display("P2_FAIL");
        $finish;
    end

    initial begin
        #400000;
        $display("P2_FAIL hard timeout");
        $finish;
    end

endmodule

// div_* 是 VHDL IP，命令行无法编译；P2 程序不涉除法，用占位模块顶上。
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
            $fatal(1, "div_signed requested in P2 test");
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
            $fatal(1, "div_unsigned requested in P2 test");
endmodule
