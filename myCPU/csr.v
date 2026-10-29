module csr(
    // 状态在上升沿更新；组合读不需要等待一拍。
    input wire          clk,          // 顶层时钟，所有 CSR 状态使用 posedge clk
    input wire          reset,        // 同步高有效复位：上升沿看到 1 才复位

    // 普通 CSR 指令：ID 生成编号/掩码/写值，随指令传至 WB，由 WB 驱动这些端口。
    input wire [13:0]   csr_num,      // 选中的 CSR 编号，如 ERA=14'h006；不是 GRF 寄存器号

    input wire          csr_we,       // WB 普通写提交：为 1 时在本次上升沿写入；读指令为 0
    input wire [31:0]   csr_wmask,    // 逐位写使能：1 修改、0 保留；CSRWR 全 1，CSRXCHG 取 GRF[rj]
    input wire [31:0]   csr_wvalue,   // 待写数据：CSRWR/CSRXCHG 的原 GRF[rd] 值，不是 CSR 旧值

    // 异常由流水线检测并送至 WB 提交；以下专用通路不使用 csr_num/wmask/wvalue。
    input wire          wb_ex,        // WB 异常提交脉冲；上升沿保存 ERA/PRMD/ESTAT 并清 CRMD.PLV/IE
    input wire [5:0]    wb_ecode,      // wb_ex 有效时的异常主编码，写 ESTAT[21:16]，如 SYS=6'h0b
    input wire [8:0]    wb_esubcode,   // wb_ex 有效时的异常子编码，写 ESTAT[30:22]；本实验所列异常为 0
    input wire [31:0]   wb_pc,         // 当前 WB 异常指令的 PC，保存到 ERA；不是 PC+4 或错误数据地址
    input wire          wb_badv_valid, // EX9：与 wb_ex 同为 1 才更新 BADV；不是整条异常的有效位
    input wire [31:0]   wb_badv,       // EX9：ADEF 为错误取指 PC，ALE 为错误访存地址；EX8 暂不使用
    input wire          ertn_flush,   // WB 的 ERTN 提交脉冲；上升沿将 PRMD 的 PPLV/PIE 恢复到 CRMD
    input wire [7:0]    hw_int_in,     // EX9：顶层送入的已同步硬中断，采样到 ESTAT.IS[9:2]；EX8 接 0

    // 下列输出为接口约定，当前骨架尚未实现驱动逻辑。
    output reg  [31:0]  csr_rvalue,    // csr_num 选中 CSR 的组合读值，未知编号读 0；WB 在写入沿采样旧值给 rd
    output wire [31:0]  ex_entry,      // 组合输出 EENTRY：异常处理入口；顶层在 wb_ex 时让 IF 跳到这里
    output wire [31:0]  ertn_entry,    // 组合输出 ERA：返回地址；顶层在 ertn_flush 时让 IF 跳转，不自动加 4
    output wire         has_int,      // EX9：IE && 存在(IS & LIE)有效位，送 ID 判断中断；不等同 wb_ex，EX8 输出 0
    output wire [63:0]  counter_value, // EX9：每拍自增的稳定计数器，送 EXE 采样；不是 TVAL 倒计时，EX8 输出 0
    output wire [31:0]  tid_value     // EX9：TID 寄存器值，供 WB 执行 RDCNTID 写回；EX8 输出 0

);
    // 同一字段的更新优先级：reset > wb_ex > ertn_flush > 普通 CSR 写入。
    // 普通写的有效掩码 = csr_wmask & 本 CSR 的可写位掩码；只读/保留位不能任意写入。
    // 异常可在同一上升沿更新多个 CSR；软件一次只写 csr_num 选中的一个。
    reg [31:0] CRMD;    // 0x000 当前模式：PLV[1:0]、IE[2]可写；本方案 DA[3]=1，其余0，复位为8
    reg [31:0] PRMD;    // 0x001 异常前模式：PPLV[1:0]、PIE[2]保存旧 PLV/IE，供 ERTN 恢复
    reg [31:0] ECFG;    // 0x004
    reg [31:0] ESTAT;   // 0x005 异常状态：软件可写 IS[1:0]；异常硬件更新 Ecode[21:16]/EsubCode[30:22]
    reg [31:0] ERA;     // 0x006 异常返回地址：异常时保存 wb_pc；软件可改，如跳过 syscall 时加4
    reg [31:0] BADV;    // 0x007
    reg [31:0] EENTRY;  // 0x00c 软件设置的异常入口：仅[31:6]可写，低6位固定0，异常本身不改它
    reg [31:0] SAVE0;   // 0x030 软件临时保存数据，全32位可读写；硬件不自动向这里保存 GRF
    reg [31:0] SAVE1;   // 0x031 同 SAVE0，各自独立存储
    reg [31:0] SAVE2;   // 0x032 同 SAVE0，各自独立存储
    reg [31:0] SAVE3;   // 0x033 同 SAVE0，各自独立存储
    reg [31:0] TID;     // 0x040
    reg [31:0] TCFG;    // 0x041
    reg [31:0] TVAL;    // 0x042
    reg [31:0] TICLR;   // 0x044

    reg [63:0] _STABLE_COUNTER;
    reg        _COUNTER_RUNNING;

    wire        _w_tcfg;
    wire [31:0] _new_tcfg;
    wire        _counter_expired;

    always @(posedge clk) begin
        if (reset) begin
            CRMD    <= 32'h00000008;
            PRMD    <= 32'h00000000;
            ECFG    <= 32'h00000000;
            ESTAT   <= 32'h00000000;
            ERA     <= 32'h00000000;
            BADV    <= 32'h00000000;
            EENTRY  <= 32'h00000000;
            SAVE0   <= 32'h00000000;
            SAVE1   <= 32'h00000000;
            SAVE2   <= 32'h00000000;
            SAVE3   <= 32'h00000000;
            TID     <= 32'h00000000;
            TCFG    <= 32'h00000000;
            TICLR   <= 32'h00000000;
        end
        else begin
            // hardware interruption
            ESTAT[9:2] <= hw_int_in;
            // timer interruption
            if (_counter_expired) begin
                ESTAT[11] <= 1'b1;
            end
            else if (!wb_ex && !ertn_flush && csr_we && csr_num == 14'h044 && csr_wmask[0] && csr_wvalue[0]) begin
                    ESTAT[11] <= 1'b0;
            end
            // exception handler
            if (wb_ex) begin
                PRMD[2:0]    <= CRMD[2:0];
                CRMD[2:0]    <= 3'b000;
                ERA          <= wb_pc;
                ESTAT[30:16] <= {wb_esubcode, wb_ecode};
                if (wb_badv_valid) begin
                    BADV <= wb_badv;
                end
            end
            // exception return
            else if (ertn_flush) begin
                CRMD[2:0] <= PRMD[2:0];
            end
            else if (csr_we) begin
                case(csr_num)
                    14'h000:   CRMD[2:0]     <= (~csr_wmask[2:0] & CRMD[2:0]) | (csr_wmask[2:0] & csr_wvalue[2:0]);
                    14'h001:   PRMD[2:0]     <= (~csr_wmask[2:0] & PRMD[2:0]) | (csr_wmask[2:0] & csr_wvalue[2:0]);
                    14'h004:   ECFG[12:0]    <= {(~csr_wmask[12:11] & ECFG[12:11]) | (csr_wmask[12:11] & csr_wvalue[12:11]), 1'b0, (~csr_wmask[9:0] & ECFG[9:0]) | (csr_wmask[9:0] & csr_wvalue[9:0])};
                    14'h005:   ESTAT[1:0]    <= (~csr_wmask[1:0] & ESTAT[1:0]) | (csr_wmask[1:0] & csr_wvalue[1:0]);
                    14'h006:   ERA           <= (~csr_wmask & ERA) | (csr_wmask & csr_wvalue);
                    14'h007:   BADV          <= (~csr_wmask & BADV) | (csr_wmask & csr_wvalue);
                    14'h00c:   EENTRY        <= {(~csr_wmask[31:6] & EENTRY[31:6]) | (csr_wmask[31:6] & csr_wvalue[31:6]), 6'b0};
                    14'h030:   SAVE0         <= (~csr_wmask & SAVE0) | (csr_wmask & csr_wvalue);
                    14'h031:   SAVE1         <= (~csr_wmask & SAVE1) | (csr_wmask & csr_wvalue);
                    14'h032:   SAVE2         <= (~csr_wmask & SAVE2) | (csr_wmask & csr_wvalue);
                    14'h033:   SAVE3         <= (~csr_wmask & SAVE3) | (csr_wmask & csr_wvalue);
                    14'h040:   TID           <= (~csr_wmask & TID) | (csr_wmask & csr_wvalue);
                    14'h041:   TCFG          <= (~csr_wmask & TCFG) | (csr_wmask & csr_wvalue);
                endcase
            end
        end
    end
    // countdown timer
    assign _w_tcfg           = !ertn_flush && !wb_ex && csr_we && (csr_num == 14'h41);
    assign _new_tcfg         = (TCFG & ~csr_wmask) | (csr_wvalue & csr_wmask);
    assign _counter_expired = _COUNTER_RUNNING && (TVAL == 32'b0);

    always @(posedge clk) begin
        if (reset) begin
            TVAL    <= 32'hffffffff;
            _COUNTER_RUNNING <= 1'b0;
        end
        else if (_w_tcfg) begin
            _COUNTER_RUNNING <= _new_tcfg[0];
            if(_new_tcfg[0]) begin
                TVAL <= {_new_tcfg[31:2], 2'b0};
            end
        end
        else if (_COUNTER_RUNNING) begin
            if (TVAL != 32'h0) begin
                TVAL <= TVAL - 32'h1;
            end
            else if (TCFG[1]) begin
                TVAL <= {TCFG[31:2], 2'b0};
            end
            else begin
                TVAL             <= 32'hffffffff;
                _COUNTER_RUNNING <= 1'b0;
            end
        end

    end
    // normal timer
    always @(posedge clk) begin
        if (reset) begin
            _STABLE_COUNTER <= 64'h0;
        end
        else begin
            _STABLE_COUNTER <= _STABLE_COUNTER + 64'h1;
        end
    end
    assign ex_entry     = EENTRY;
    assign ertn_entry   = ERA;
    assign tid_value    = TID;
    assign has_int      = CRMD[2] & (|(ESTAT[11:0] & ECFG[11:0]));
    assign counter_value= _STABLE_COUNTER;

    // CSR read selector
    always @(*) begin
        case (csr_num)
            14'h000: csr_rvalue = CRMD;
            14'h001: csr_rvalue = PRMD;
            14'h004: csr_rvalue = ECFG;
            14'h005: csr_rvalue = ESTAT;
            14'h006: csr_rvalue = ERA;
            14'h007: csr_rvalue = BADV;
            14'h00c: csr_rvalue = EENTRY;
            14'h030: csr_rvalue = SAVE0;
            14'h031: csr_rvalue = SAVE1;
            14'h032: csr_rvalue = SAVE2;
            14'h033: csr_rvalue = SAVE3;
            14'h040: csr_rvalue = TID;
            14'h041: csr_rvalue = TCFG;
            14'h042: csr_rvalue = TVAL;
            14'h044: csr_rvalue = TICLR;
            default: csr_rvalue = 32'h0;
        endcase
    end

endmodule
