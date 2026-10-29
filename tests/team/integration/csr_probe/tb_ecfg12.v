// A13 最小复现：验证 ECFG.LIE[12] 是否可读写
// 由 C 提供，用于向 A 说明问题。模块级测试，直接驱动 csr 的 20 个端口。
// 依据：document/09-errata.md 与 c8a5b33 —— LIE[12:11] 均可读写，掩码 0x00001bff

module tb_ecfg12;

    reg         clk = 1'b0;
    reg         reset = 1'b1;

    reg  [13:0] csr_num = 14'h0;
    reg         csr_we = 1'b0;
    reg  [31:0] csr_wmask = 32'h0;
    reg  [31:0] csr_wvalue = 32'h0;

    reg         wb_ex = 1'b0;
    reg  [ 5:0] wb_ecode = 6'h0;
    reg  [ 8:0] wb_esubcode = 9'h0;
    reg  [31:0] wb_pc = 32'h0;
    reg         wb_badv_valid = 1'b0;
    reg  [31:0] wb_badv = 32'h0;
    reg         ertn_flush = 1'b0;
    reg  [ 7:0] hw_int_in = 8'h0;

    wire [31:0] csr_rvalue;
    wire [31:0] ex_entry;
    wire [31:0] ertn_entry;
    wire        has_int;
    wire [63:0] counter_value;
    wire [31:0] tid_value;

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

    always #5 clk = ~clk;

    integer fail = 0;

    task csr_write(input [13:0] num, input [31:0] mask, input [31:0] val);
        begin
            @(negedge clk);
            csr_num = num; csr_wmask = mask; csr_wvalue = val; csr_we = 1'b1;
            @(negedge clk);
            csr_we = 1'b0;
            @(negedge clk);
        end
    endtask

    reg [31:0] v;

    initial begin
        $display("==============================================");
        $display("A13 最小复现：ECFG.LIE[12] 读写检查");
        $display("依据 c8a5b33：LIE[12:11] 可读写，bit10 恒 0，掩码 0x00001bff");
        $display("==============================================");

        reset = 1'b1;
        repeat (4) @(posedge clk);
        @(negedge clk) reset = 1'b0;
        repeat (2) @(posedge clk);

        // 复位值
        csr_num = 14'h004; #1;
        $display("[复位] ECFG = 0x%08h", csr_rvalue);

        // 用例1：只写 bit12（LIE[12]）
        csr_write(14'h004, 32'h0000_1000, 32'h0000_1000);
        csr_num = 14'h004; #1; v = csr_rvalue;
        $display("[写bit12] ECFG = 0x%08h  (期望 0x00001000)", v);
        if (v[12] !== 1'b1) begin
            $display("  FAIL: LIE[12] 写不进去，读回 bit12 = %b", v[12]);
            fail = fail + 1;
        end
        else $display("  PASS: LIE[12] 可读写");

        // 用例2：全 1 写入，检查掩码边界
        csr_write(14'h004, 32'hFFFF_FFFF, 32'hFFFF_FFFF);
        csr_num = 14'h004; #1; v = csr_rvalue;
        $display("[全1写入] ECFG = 0x%08h  (期望 0x00001bff)", v);
        if (v[10] !== 1'b0) begin
            $display("  FAIL: bit10 应恒 0，实际 %b", v[10]);
            fail = fail + 1;
        end
        else $display("  PASS: bit10 恒 0");
        if (v[31:13] !== 19'b0) begin
            $display("  FAIL: [31:13] 应恒 0，实际 0x%07h", v[31:13]);
            fail = fail + 1;
        end
        else $display("  PASS: [31:13] 恒 0");
        if (v[11] !== 1'b1) begin
            $display("  FAIL: LIE[11] 应可写，实际 %b", v[11]);
            fail = fail + 1;
        end
        else $display("  PASS: LIE[11] 可读写");

        // 用例3：ISt[12] 应固定 0，且 LIE[12]=1 不应触发中断
        csr_num = 14'h005; #1; v = csr_rvalue;
        $display("[ESTAT]  = 0x%08h  (IS[12] 应恒 0)", v);
        if (v[12] !== 1'b0) begin
            $display("  FAIL: ESTAT.IS[12] 应恒 0");
            fail = fail + 1;
        end
        else $display("  PASS: ESTAT.IS[12] 恒 0");
        $display("[has_int] = %b  (CRMD.IE 复位为 0，应为 0)", has_int);

        $display("==============================================");
        if (fail == 0) $display("结果：全部 PASS");
        else           $display("结果：%0d 项 FAIL", fail);
        $display("==============================================");
        $finish;
    end

endmodule
