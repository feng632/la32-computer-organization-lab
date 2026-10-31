module branch_predictor (
    input wire          clk,
    input wire          reset,

    input wire          enable,
    input wire [31:0]   query_pc,
    input wire [67:0]   bp_update_bus,

    output wire         query_hit,
    output wire         predict_taken,
    output wire [31:0]  predict_target

);
    // 64 entries in total
    reg        valid    [0:63]; // entry validity
    reg [23:0] tag      [0:63]; // PC[31:8]; index is PC[7:2]
    reg [31:0] target   [0:63]; // recorded branch/jump target
    reg        is_cond  [0:63]; // conditional branch/jump
    reg [1:0]  state    [0:63]; // 2-bit preference

    wire [5:0] query_index = query_pc[7:2];

    assign query_hit = enable && !reset && (query_pc[1:0] == 2'b0)
                    && valid[query_index] && (tag[query_index] == query_pc[31:8]);
    assign predict_taken = query_hit && (!is_cond[query_index] || state[query_index][1]);
    assign predict_target = query_hit ? target[query_index] : 32'b0;

    wire        update_valid;
    wire        update_is_branch;
    wire        update_is_cond;
    wire        update_taken;
    wire [31:0] update_pc;
    wire [31:0] update_target;
    wire [5:0]  update_index = update_pc[7:2];

    assign {update_valid, update_is_branch, update_is_cond, update_taken,
            update_pc, update_target} = bp_update_bus;

    integer i;
    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < 64; i = i + 1) begin
                valid[i]    <= 1'b0;
                tag[i]      <= 24'b0;
                target[i]   <= 32'b0;
                is_cond[i]  <= 1'b0;
                state[i]    <= 2'b0;
            end
        end
        else if (enable && update_valid) begin
            if (update_is_branch) begin
                valid[update_index]   <= 1'b1;
                tag[update_index]     <= update_pc[31:8];
                target[update_index]  <= update_target;
                is_cond[update_index] <= update_is_cond;

                if (!update_is_cond)
                    state[update_index] <= 2'b11;
                else if (!valid[update_index] || tag[update_index] != update_pc[31:8]
                         || !is_cond[update_index])
                    state[update_index] <= update_taken ? 2'b10 : 2'b01;
                else if (update_taken)
                    state[update_index] <= state[update_index] == 2'b11
                                        ? 2'b11 : state[update_index] + 2'b01;
                else
                    state[update_index] <= state[update_index] == 2'b00
                                        ? 2'b00 : state[update_index] - 2'b01;
            end
            else if (valid[update_index] && tag[update_index] == update_pc[31:8]) begin
                valid[update_index] <= 1'b0;
            end
        end
    end
endmodule
