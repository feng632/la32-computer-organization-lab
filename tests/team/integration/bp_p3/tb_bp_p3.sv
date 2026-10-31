`timescale 1ns/1ps
// =============================================================================
// P3 分支预测性能统计测试台
//
// 与 P2 的关系：
//   P2 判"对不对"（架构写回是否与期望一致），P3 判"快了多少、准到什么程度"。
//   两者共用同一套行为级指令/数据 RAM 与 asm.py 汇编器，但 TB 独立，
//   P2 的通过结论不因 P3 的改动而变化。
//
// 统计窗口：
//   resetn 释放后开始，程序向 0x1c100100 写入结束标志为止（与 P2 一致）。
//
// 每项指标都取自 DUT 内部的真实信号，不做事后估计：
//   u_id_stage.normal_fire         ID 实际发射（已排除异常 / ertn）
//   u_id_stage.is_branch/is_cond   分支分类
//   u_id_stage.actual_taken        分支实际是否跳
//   u_id_stage.br_target           分支实际目标
//   u_id_stage.fs_to_ds_bp_r       {hit, taken, next_pc}：该指令被取指时预测器给出的后继
//   u_id_stage.bp_redirect_valid   RTL 自己认定的"预测失败"
//
// 口径（写进报告时必须一致）：
//   预测正确 ok  <=> 预测后继 == 实际后继
//                  （含"BTB 无条目且实际不跳"这种默认直行猜对的情况，
//                    这类单独计入 hit=0 的 ok，用 miss_ok 区分）
//   预测失败按原因四分类：
//     cold  BTB 无条目（或 tag 冲突被挤掉）而实际跳转
//     dir   命中且预测跳，实际不跳（过度预测）
//     tgt   命中且预测跳，实际跳，但目标地址不同
//     miss  命中但预测不跳（2-bit 状态 < 2），实际跳
//   一致性自检：redirect 必须等于 cold+dir+tgt+miss 之和。
//
// 编译开关：
//   默认 BP_ENABLE=0（预测器旁路的对照基线）
//   xvlog -d BP_ON  打开预测器
// =============================================================================
module tb_bp_p3;

    localparam [31:0] MAGIC = 32'h1c10_0100;

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

    // =========================================================================
    //                          P3 统计观察点
    // =========================================================================
    wire        st_id_fire   = u_cpu.u_id_stage.normal_fire;
    wire        st_is_branch = u_cpu.u_id_stage.is_branch;
    wire        st_is_cond   = u_cpu.u_id_stage.is_cond;
    wire        st_a_taken   = u_cpu.u_id_stage.actual_taken;
    wire [31:0] st_br_tgt   = u_cpu.u_id_stage.br_target;
    wire [31:0] st_ds_pc    = u_cpu.u_id_stage.ds_pc;
    wire [33:0] st_bp_meta  = u_cpu.u_id_stage.fs_to_ds_bp_r;
    wire        st_redir_ev = u_cpu.u_id_stage.bp_redirect_valid;   // 单拍纠正事件
    wire        st_fs_valid  = u_cpu.fs_to_ds_valid;
    wire        st_ds_allow  = u_cpu.ds_allowin;
    wire        st_wb_valid  = u_cpu.u_wb_stage.ws_valid;          // WB 级有效指令 = 已提交

    wire        st_bp_hit   = st_bp_meta[33];
    wire        st_bp_taken = st_bp_meta[32];
    wire [31:0] st_actual_next = st_a_taken ? st_br_tgt : st_ds_pc + 32'd4;
    wire        st_pred_ok     = (st_bp_meta[31:0] == st_actual_next);

    longint st_cyc;        // 统计窗口内的时钟拍数
    longint st_inst;       // 提交到 ID 的指令数
    longint st_br;         // 实际发射的分支/跳转指令数
    longint st_cond;
    longint st_uncond;
    longint st_taken;
    longint st_hit;        // 分支中 BTB 命中的次数
    longint st_ok;         // 预测后继 == 实际后继
    longint st_redir;      // RTL 认定的预测失败次数
    longint st_fcold;
    longint st_fdir;
    longint st_ftgt;
    longint st_fmiss;
    longint st_fs_drop;    // 失败时被丢弃的已取指令数（fs 级有效拍）
    longint st_wb;         // 写回级有效指令数（提交数，CPI 分母）
    longint st_nb_redir;   // 非分支指令的纠正数（应恒为 0，为 0 即无错误表项误跳）
    reg     st_on;

    always @(posedge clk) begin
        if (!resetn) begin
            st_cyc     <= 0;
            st_inst    <= 0;
            st_br      <= 0;
            st_cond    <= 0;
            st_uncond  <= 0;
            st_taken   <= 0;
            st_hit     <= 0;
            st_ok      <= 0;
            st_redir   <= 0;
            st_fcold   <= 0;
            st_fdir    <= 0;
            st_ftgt    <= 0;
            st_fmiss   <= 0;
            st_fs_drop <= 0;
            st_wb      <= 0;
            st_nb_redir<= 0;
            st_on      <= 1'b0;
        end else begin
            st_on <= 1'b1;
            if (st_on && !magic_seen) begin
                st_cyc <= st_cyc + 1;

                if (st_fs_valid && st_ds_allow)
                    st_inst <= st_inst + 1;

                if (st_wb_valid)
                    st_wb <= st_wb + 1;

                // 非分支指令不应产生纠正；非 0 说明表项错误把普通指令带偏
                if (st_redir_ev && !st_is_branch)
                    st_nb_redir <= st_nb_redir + 1;

                if (st_id_fire && st_is_branch) begin
                    st_br <= st_br + 1;
                    if (st_is_cond) st_cond   <= st_cond + 1;
                    else            st_uncond <= st_uncond + 1;
                    if (st_a_taken) st_taken  <= st_taken + 1;
                    if (st_bp_hit)  st_hit    <= st_hit   + 1;

                    if (st_pred_ok) begin
                        st_ok <= st_ok + 1;
                    end else if (!st_bp_hit) begin
                        st_fcold <= st_fcold + 1;
                    end else if (st_bp_taken && !st_a_taken) begin
                        st_fdir <= st_fdir + 1;
                    end else if (st_bp_taken && st_a_taken) begin
                        st_ftgt <= st_ftgt + 1;
                    end else begin
                        st_fmiss <= st_fmiss + 1;
                    end
                end

                if (st_redir_ev) begin
                    st_redir <= st_redir + 1;
                    if (u_cpu.u_if_stage.fs_valid) st_fs_drop <= st_fs_drop + 1;
                end
            end
        end
    end

    // ------------------------------------------------------------- 期望结果
    reg [31:0] exp_reg [0:31];
    reg        has_reg [0:31];
    reg [31:0] exp_mem [0:1023];
    reg        has_mem [0:1023];

    reg [8*32-1:0] prog_name = "unknown";   // 由 name.txt 读入，仅用于打标签

    integer k;
    initial begin
        for (k = 0; k < 32; k = k + 1)   has_reg[k] = 1'b0;
        for (k = 0; k < 1024; k = k + 1) has_mem[k] = 1'b0;
        for (k = 0; k < 1024; k = k + 1) begin
            dmem[k] = 32'h0;
            imem[k] = 32'h0280_0000;   // NOP：addi.w r0, r0, 0
        end
        $readmemh("prog.hex", imem);
        load_expect("expect.txt");
        load_name("name.txt");
    end

    task load_name(input string path);
        integer fd;
        fd = $fopen(path, "r");
        if (fd != 0) begin
            void'($fscanf(fd, "%s", prog_name));
            $fclose(fd);
        end
    endtask

    task load_expect(input string path);
        integer fd, rc, idx;
        reg [23:0] kind;
        reg [31:0] val;
        fd = $fopen(path, "r");
        if (fd == 0) begin
            $display("  [FAIL] cannot open expect file %s", path);
            $finish;
        end
        rc = $fscanf(fd, "%s %d %h\n", kind, idx, val);
        while (rc == 3) begin
            if (kind == "reg") begin
                exp_reg[idx] = val; has_reg[idx] = 1'b1;
            end else if (kind == "mem") begin
                exp_mem[idx] = val; has_mem[idx] = 1'b1;
            end else begin
                $display("  [WARN] unknown expect kind %s", kind);
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
            $display("  [FAIL] %s actual=0x%08x expected=0x%08x", name, actual, exp_v);
        end else begin
            $display("  [PASS] %s = 0x%08x", name, actual);
        end
    endtask

    // -------------------------------------------------------------- 统计打印
    real acc, hit_rate, ipc, cpi;
    longint fail_sum;

    task print_stats(input integer cyc_ext);
        integer fd;
        fail_sum = st_fcold + st_fdir + st_ftgt + st_fmiss;
        acc      = (st_br   != 0) ? (1.0 * st_ok  / st_br)   : 0.0;
        hit_rate = (st_br   != 0) ? (1.0 * st_hit / st_br)   : 0.0;
        ipc      = (cyc_ext  != 0) ? (1.0 * st_inst / cyc_ext) : 0.0;
        cpi      = (st_wb    != 0) ? (1.0 * cyc_ext / st_wb)   : 0.0;

        $display("----------------------------------------------------------------");
        $display(" P3 statistics : %0s  (BP_ENABLE=%0d)", prog_name, BP_EN);
        $display("----------------------------------------------------------------");
        $display("  cycles           %0d   (window counter %0d)", cyc_ext, st_cyc);
        $display("  inst (to ID)     %0d", st_inst);
        $display("  committed (WBs)  %0d", st_wb);
        $display("  ipc              %0.4f   (inst/cycles)", ipc);
        $display("  cpi              %0.4f   (cycles/committed)", cpi);
        $display("  branch           %0d   (cond %0d / uncond %0d)",
                 st_br, st_cond, st_uncond);
        $display("  branch taken     %0d", st_taken);
        $display("  btb hit          %0d   (%0.2f%% of branch)", st_hit, hit_rate * 100.0);
        $display("  predict ok       %0d   (accuracy %0.2f%%)", st_ok, acc * 100.0);
        $display("  redirect         %0d   (branch %0d / non-branch %0d)",
                 st_redir, st_redir - st_nb_redir, st_nb_redir);
        $display("  fail cold        %0d   (BTB miss, actually taken)", st_fcold);
        $display("  fail dir         %0d   (predicted taken, not taken)", st_fdir);
        $display("  fail tgt         %0d   (target mismatch)", st_ftgt);
        $display("  fail miss        %0d   (hit but predicted not taken)", st_fmiss);
        $display("  fs drop          %0d   (fetched instr discarded)", st_fs_drop);

        if (fail_sum + st_nb_redir != st_redir) begin
            $display("  [WARN] consistency check FAILED: fail_sum=%0d nb=%0d redirect=%0d",
                     fail_sum, st_nb_redir, st_redir);
        end else begin
            $display("  [INFO] consistency OK: branch_fail + non_branch == redirect == %0d", st_redir);
        end

        // 供脚本汇总的机器可读行
        $display("BP_CSV,%0s,%0d,%0d,%0d,%0.4f,%0d,%0d,%0d,%0d,%0d,%0d,%0.4f,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0.4f,%0d",
                 prog_name, BP_EN, cyc_ext, st_inst, ipc,
                 st_br, st_cond, st_uncond, st_taken, st_hit, st_ok, acc,
                 st_redir, st_fcold, st_fdir, st_ftgt, st_fmiss, st_fs_drop,
                 st_wb, cpi, st_nb_redir);

        fd = $fopen("stat.csv", "w");
        if (fd != 0) begin
            $fdisplay(fd, "program,bp_enable,cycles,inst,ipc,branch,cond,uncond,taken,btb_hit,predict_ok,accuracy,redirect,fail_cold,fail_dir,fail_tgt,fail_miss,fs_drop,committed,cpi,non_branch_redirect");
            $fdisplay(fd, "%0s,%0d,%0d,%0d,%0.4f,%0d,%0d,%0d,%0d,%0d,%0d,%0.4f,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0.4f,%0d",
                      prog_name, BP_EN, cyc_ext, st_inst, ipc,
                      st_br, st_cond, st_uncond, st_taken, st_hit, st_ok, acc,
                      st_redir, st_fcold, st_fdir, st_ftgt, st_fmiss, st_fs_drop,
                      st_wb, cpi, st_nb_redir);
            $fclose(fd);
        end
    endtask

    // ---------------------------------------------------------------- 主流程
    integer cyc;
    initial begin
        $display("================================================================");
        $display(" P3 performance statistics (BP_ENABLE=%0d)", BP_EN);
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
            $display("  [FAIL] no end marker within %0d cycles, last wb_pc=0x%08x", cyc, dbg_pc);
            $display("P3_FAIL timeout");
            $finish;
        end
        $display("  [INFO] end marker reached in %0d cycles, last wb_pc=0x%08x", cyc, dbg_pc);

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

        print_stats(cyc);

        $display("----------------------------------------------------------------");
        $display("P3_SUMMARY checks=%0d fails=%0d cycles=%0d", checks, fails, cyc);
        if (fails == 0) $display("P3_PASS");
        else            $display("P3_FAIL");
        $finish;
    end

    initial begin
        #400000;
        $display("P3_FAIL hard timeout");
        $finish;
    end

endmodule

// div_* 是 VHDL IP，命令行无法编译；P3 程序不涉除法，用占位模块顶上。
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
            $fatal(1, "div_signed requested in P3 test");
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
            $fatal(1, "div_unsigned requested in P3 test");
endmodule
