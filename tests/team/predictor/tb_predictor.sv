`timescale 1ns/1ps
module tb_predictor;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1, enable = 1;
    reg [31:0] query_pc = 0;
    reg [67:0] bp_update_bus = 0;
    wire query_hit, predict_taken;
    wire [31:0] predict_target;
    branch_predictor dut(.*);
    integer checks = 0;
    reg sampled_hit;
    reg [31:0] sampled_target;
    always @(posedge clk) begin
        sampled_hit <= query_hit;
        sampled_target <= predict_target;
    end

    task check(input bit condition, input string label_text);
        begin
            checks = checks + 1;
            if (!condition) $fatal(1, "FAIL: %s", label_text);
        end
    endtask
    task update(input bit branch_kind, cond_kind, taken,
                input [31:0] pc, target);
        begin
            @(negedge clk);
            bp_update_bus = {1'b1, branch_kind, cond_kind, taken, pc, target};
            @(posedge clk); #1;
            bp_update_bus = 0;
        end
    endtask
    task query(input [31:0] pc, input bit hit, taken, input [31:0] target);
        begin
            query_pc = pc; #1;
            check({query_hit, predict_taken, predict_target} === {hit, taken, target}, "query");
        end
    endtask
    task state_is(input [1:0] expected);
        check(dut.state[0] === expected, "counter state");
    endtask

    initial begin
        @(posedge clk); #1; reset = 0;
        for (integer n = 0; n < 64; n = n + 1) begin
            query(n * 4, 0, 0, 0);
            check({dut.valid[n], dut.tag[n], dut.target[n], dut.is_cond[n], dut.state[n]} === 60'b0, "reset all fields");
        end
        update(1, 1, 1, 32'h1000, 32'h2000);
        query(32'h1000, 1, 1, 32'h2000); state_is(2);
        update(1, 1, 1, 32'h1000, 32'h2000); state_is(3);
        update(1, 1, 1, 32'h1000, 32'h2000); state_is(3);
        update(1, 1, 0, 32'h1000, 32'h3000); state_is(2);
        update(1, 1, 0, 32'h1000, 32'h3000); state_is(1);
        query(32'h1000, 1, 0, 32'h3000);
        update(1, 1, 0, 32'h1000, 32'h3000); state_is(0);
        update(1, 1, 0, 32'h1000, 32'h3000); state_is(0);
        update(1, 1, 1, 32'h1000, 32'h3000); state_is(1);
        update(1, 1, 1, 32'h1000, 32'h3000); state_is(2);
        // Same index, different tag: replace and initialize, do not inherit state.
        update(1, 1, 0, 32'h1100, 32'h4000); state_is(1);
        query(32'h1000, 0, 0, 0);
        query(32'h1100, 1, 0, 32'h4000);
        update(0, 0, 0, 32'h1000, 0);
        query(32'h1100, 1, 0, 32'h4000);
        update(0, 0, 0, 32'h1100, 0);
        query(32'h1100, 0, 0, 0);
        update(1, 0, 1, 32'h1100, 32'h5000); state_is(3);
        query(32'h1100, 1, 1, 32'h5000);
        update(1, 0, 1, 32'h1100, 32'h6003);
        query(32'h1100, 1, 1, 32'h6003); // Keep unaligned target bits.
        query(32'h1101, 0, 0, 0);
        update(1, 1, 0, 32'h1100, 32'h7000); state_is(1);
        update(1, 0, 1, 32'h1100, 32'h8000); state_is(3);
        enable = 0;
        query(32'h1100, 0, 0, 0);
        update(0, 0, 0, 32'h1100, 0);
        enable = 1;
        query(32'h1100, 1, 1, 32'h8000);
        // Invalid update must not replace the entry.
        @(negedge clk); bp_update_bus = {1'b0, 3'b111, 32'h1100, 32'hdeadbeef};
        @(posedge clk); #1; bp_update_bus = 0;
        query(32'h1100, 1, 1, 32'h8000);
        // IF samples the old query result at the update edge (no bypass).
        update(1, 0, 1, 32'h1100, 32'h9000);
        check(sampled_hit === 1'b1 && sampled_target === 32'h8000, "old value sampled");
        query(32'h1100, 1, 1, 32'h9000);
        @(negedge clk); reset = 1;
        bp_update_bus = {4'b1111, 32'h1100, 32'hdeadbeef};
        #1; check(query_hit === 1'b0, "reset masks query");
        @(posedge clk); #1; reset = 0; bp_update_bus = 0;
        query(32'h1100, 0, 0, 0);
        $display("PREDICTOR_PASS checks=%0d", checks);
        $finish;
    end
    initial begin #10000; $fatal(1, "timeout"); end
endmodule
