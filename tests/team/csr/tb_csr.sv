`timescale 1ns / 1ps

module tb_csr;
    reg clk = 0;
    reg reset = 0;
    reg [13:0] csr_num = 0;
    reg csr_we = 0;
    reg [31:0] csr_wmask = 0, csr_wvalue = 0;
    reg wb_ex = 0, ertn_flush = 0, wb_badv_valid = 0;
    reg [5:0] wb_ecode = 0;
    reg [8:0] wb_esubcode = 0;
    reg [31:0] wb_pc = 0, wb_badv = 0;
    reg [7:0] hw_int_in = 0;
    wire [31:0] csr_rvalue, ex_entry, ertn_entry, tid_value;
    wire [63:0] counter_value;
    wire has_int;

    csr dut(.*);

    integer checks = 0, failures = 0, passed_groups = 0;
    integer group_failures = 0, i, j;
    string group_id;
    reg [63:0] saved_counter;

    task check(input string label, input [63:0] actual, input [63:0] expected);
        checks = checks + 1;
        if (actual !== expected) begin
            failures = failures + 1;
            $display("FAIL %s %s time=%0t expected=%016h actual=%016h",
                     group_id, label, $time, expected, actual);
        end
    endtask

    // Inputs change with clk low; check one ns after NBA updates.
    // Clock is explicitly stepped so combinational reads cannot add hidden cycles.
    task tick;
        reg [63:0] previous;
        previous = counter_value;
        #5; clk = 1;
        #1;
        check("stable counter each edge", counter_value,
              reset ? 64'b0 : previous + 64'd1);
        clk = 0;
    endtask

    task idle_inputs;
        csr_we = 0; csr_wmask = 0; csr_wvalue = 0;
        wb_ex = 0; ertn_flush = 0; wb_badv_valid = 0;
        wb_ecode = 0; wb_esubcode = 0; wb_pc = 0; wb_badv = 0;
        hw_int_in = 0;
    endtask

    task reset_dut;
        idle_inputs();
        reset = 1;
        tick(); tick();
        reset = 0;
    endtask

    task begin_group(input string id);
        group_id = id;
        group_failures = failures;
        reset_dut();
    endtask

    task end_group;
        if (failures == group_failures) begin
            passed_groups = passed_groups + 1;
            $display("PASS %s", group_id);
        end else
            $display("FAIL %s assertions_failed=%0d", group_id, failures-group_failures);
    endtask

    task read_check(input [13:0] num, input [31:0] expected, input string label);
        csr_num = num;
        #1;
        check(label, csr_rvalue, expected);
    endtask

    task write_csr(input [13:0] num, input [31:0] mask, input [31:0] value);
        csr_num = num; csr_wmask = mask; csr_wvalue = value; csr_we = 1;
        tick();
        csr_we = 0;
    endtask

    task irq_check(input bit expected, input string label);
        csr_num = 14'h005;
        #1;
        check(label, csr_rvalue[11], expected);
    endtask

    // Initial count is four. Return in the cycle where TVAL is target (0 or 1).
    task prepare_boundary(input integer target);
        reset_dut();
        write_csr(14'h041, 32'hffffffff, 32'h5);
        repeat (4-target) tick();
        read_check(14'h042, target, "boundary setup count");
        irq_check(0, "no early interrupt");
    endtask

    initial begin
        #100000;
        $display("FAIL TIMEOUT current_group=%s", group_id);
        $fatal(1, "CSR test exceeded 100 us");
    end

    initial begin
        begin_group("A01");
        read_check(14'h000, 8, "CRMD reset");
        read_check(14'h001, 0, "PRMD reset");
        read_check(14'h004, 0, "ECFG reset");
        read_check(14'h005, 0, "ESTAT reset");
        read_check(14'h006, 0, "ERA reset");
        read_check(14'h007, 0, "BADV reset");
        read_check(14'h00c, 0, "EENTRY reset");
        for (i=0; i<4; i=i+1) read_check(14'h030+i, 0, "SAVE reset");
        read_check(14'h040, 0, "TID reset");
        read_check(14'h041, 0, "TCFG reset");
        read_check(14'h042, 32'hffffffff, "TVAL reset");
        read_check(14'h044, 0, "TICLR reset");
        check("entry reset", ex_entry, 0);
        check("return reset", ertn_entry, 0);
        check("TID output reset", tid_value, 0);
        check("interrupt reset", has_int, 0);
        end_group();

        begin_group("A02");
        write_csr(14'h030, 32'hffffffff, 32'h12345678);
        csr_num = 14'h030; csr_we = 1;
        csr_wmask = 32'h00ff00ff; csr_wvalue = 32'haabbccdd;
        #1; check("masked write reads old value before edge", csr_rvalue, 32'h12345678);
        tick(); csr_we = 0;
        read_check(14'h030, 32'h12bb56dd, "masked write after edge");
        write_csr(14'h030, 0, 32'hffffffff);
        read_check(14'h030, 32'h12bb56dd, "zero mask holds");
        for (i=1; i<4; i=i+1) write_csr(14'h030+i, 32'hffffffff, 32'h12340000+i);
        for (i=1; i<4; i=i+1) read_check(14'h030+i, 32'h12340000+i, "SAVE independent storage");
        read_check(14'h030, 32'h12bb56dd, "SAVE0 not aliased");
        write_csr(14'h040, 32'hffffffff, 32'h89abcdef);
        check("TID output", tid_value, 32'h89abcdef);
        end_group();

        begin_group("A03");
        write_csr(14'h3fff, 32'hffffffff, 32'hffffffff);
        read_check(14'h3fff, 0, "unknown CSR read/write");
        read_check(14'h030, 0, "unknown write no SAVE side effect");
        write_csr(14'h000, 32'hffffffff, 32'hffffffff);
        read_check(14'h000, 15, "CRMD fixed address mode and reserved bits");
        write_csr(14'h001, 32'hffffffff, 32'hffffffff);
        read_check(14'h001, 7, "PRMD writable bits");
        write_csr(14'h004, 32'hffffffff, 32'hffffffff);
        // Corrected permission spec: integration branch document/09-errata.md.
        read_check(14'h004, 32'h00001bff, "ECFG LIE[12] RW, bit10/reserved zero");
        write_csr(14'h00c, 32'hffffffff, 32'h123456ff);
        read_check(14'h00c, 32'h123456c0, "EENTRY alignment");
        check("exception entry output", ex_entry, 32'h123456c0);
        write_csr(14'h00c, 32'h3f, 32'hffffffff);
        read_check(14'h00c, 32'h123456c0, "EENTRY low-only write ignored");
        write_csr(14'h005, 32'hffffffff, 32'hffffffff);
        read_check(14'h005, 3, "ESTAT software may only write bits1:0");
        write_csr(14'h042, 32'hffffffff, 0);
        read_check(14'h042, 32'hffffffff, "TVAL readonly");
        write_csr(14'h044, 32'hffffffff, 32'hffffffff);
        read_check(14'h044, 0, "TICLR reads zero");
        write_csr(14'h007, 32'hffffffff, 32'h12345678);
        write_csr(14'h007, 32'h00ff00ff, 32'haabbccdd);
        read_check(14'h007, 32'h12bb56dd, "BADV software RW per corrected spec");
        end_group();

        begin_group("A04");
        write_csr(14'h000, 7, 7);
        write_csr(14'h00c, 32'hffffffff, 32'h1c001000);
        csr_we = 1; csr_num = 14'h006; csr_wmask = 32'hffffffff; csr_wvalue = 32'hdeadbeef;
        wb_ex = 1; ertn_flush = 1; wb_pc = 32'h1c000124;
        wb_ecode = 6'h09; wb_esubcode = 9'h155;
        wb_badv_valid = 1; wb_badv = 32'h12340003;
        tick(); idle_inputs();
        read_check(14'h000, 8, "exception beats return and write");
        read_check(14'h001, 7, "PRMD captures pre-exception mode");
        read_check(14'h006, 32'h1c000124, "ERA hardware wins software");
        check("return entry output", ertn_entry, 32'h1c000124);
        read_check(14'h005, (32'h155<<22)|(32'h09<<16), "full exception code fields");
        read_check(14'h007, 32'h12340003, "valid BADV update");
        check("exception does not alter entry", ex_entry, 32'h1c001000);
        ertn_flush = 1; csr_we = 1; csr_num = 0; csr_wmask = 7; csr_wvalue = 0;
        tick(); idle_inputs();
        read_check(14'h000, 15, "ERTN restores and beats software write");
        read_check(14'h006, 32'h1c000124, "ERTN does not increment ERA");
        wb_ex = 1; wb_badv_valid = 0; wb_badv = 32'hffffffff;
        tick(); idle_inputs();
        read_check(14'h007, 32'h12340003, "invalid BADV holds");
        write_csr(14'h041, 32'hffffffff, 1); // expiry pending at next edge
        reset = 1; wb_ex = 1; ertn_flush = 1; hw_int_in = 8'hff;
        csr_we = 1; csr_num = 14'h000; csr_wmask = 32'hffffffff; csr_wvalue = 32'hffffffff;
        tick(); tick(); reset = 0; idle_inputs();
        read_check(14'h000, 8, "reset beats all events");
        read_check(14'h005, 0, "reset beats timer expiry and hardware sampling");
        read_check(14'h006, 0, "repeated reset ERA");
        read_check(14'h042, 32'hffffffff, "repeated reset timer");
        end_group();

        begin_group("A05");
        write_csr(14'h000, 7, 7);
        write_csr(14'h030, 32'hffffffff, 32'hcafe1234);
        wb_ex = 1; wb_ecode = 6'h0b; wb_esubcode = 0; wb_pc = 32'h1c000044;
        tick(); idle_inputs();
        read_check(14'h005, 32'h000b0000, "SYS code and subcode");
        read_check(14'h006, 32'h1c000044, "SYS ERA is original PC");
        read_check(14'h001, 7, "SYS PRMD");
        read_check(14'h000, 8, "SYS clears PLV and IE");
        read_check(14'h030, 32'hcafe1234, "exception does not auto-save GRF");
        end_group();

        begin_group("A06");
        write_csr(14'h005, 3, 1);
        check("software pending masked globally/locally", has_int, 0);
        write_csr(14'h004, 32'hffffffff, 1);
        check("IE off masks enabled source", has_int, 0);
        write_csr(14'h000, 4, 4);
        check("software pending and both enables", has_int, 1);
        write_csr(14'h004, 32'hffffffff, 2);
        check("wrong LIE source does not trigger", has_int, 0);
        write_csr(14'h005, 3, 2);
        check("second software source", has_int, 1);
        write_csr(14'h005, 3, 0);
        check("no pending source", has_int, 0);
        write_csr(14'h004, 32'hffffffff, 32'h1000);
        check("no IPI source even if LIE12 enabled", has_int, 0);
        write_csr(14'h041, 32'hffffffff, 1); tick();
        irq_check(1, "timer records pending despite mask");
        check("timer masked by LIE", has_int, 0);
        write_csr(14'h004, 32'hffffffff, 32'h800);
        check("timer enabled", has_int, 1);
        write_csr(14'h000, 4, 0);
        check("IE off masks timer without clearing pending", has_int, 0);
        irq_check(1, "pending retained with IE off");
        end_group();

        begin_group("A07");
        write_csr(14'h000, 4, 4);
        for (i=0; i<8; i=i+1) begin
            write_csr(14'h004, 32'hffffffff, 32'h4<<i);
            hw_int_in = 8'h1<<i; tick();
            read_check(14'h005, 32'h4<<i, "hardware interrupt bit mapping");
            check("hardware enabled source", has_int, 1);
            hw_int_in = 0; tick();
            read_check(14'h005, 0, "hardware input deassertion sampled");
            check("hardware source gone", has_int, 0);
        end
        write_csr(14'h041, 32'hffffffff, 1);
        hw_int_in = 8'ha5;
        write_csr(14'h005, 32'hffffffff, 3); // expiry, HW sample and SW write together
        read_check(14'h005, 32'h800|(32'ha5<<2)|3, "independent ESTAT fields in same edge");
        write_csr(14'h041, 32'hffffffff, 1);
        wb_ex = 1; wb_ecode = 6'h09; wb_esubcode = 1; wb_pc = 32'h1c000088;
        hw_int_in = 8'h5a; tick(); idle_inputs();
        read_check(14'h005, (32'h1<<22)|(32'h09<<16)|32'h800|(32'h5a<<2)|3,
                   "exception code, HW and expiry update together");
        ertn_flush = 1; tick(); idle_inputs();
        irq_check(1, "ERTN never clears timer pending");
        end_group();

        begin_group("A08");
        write_csr(14'h041, 32'hffffffff, 5);
        for (i=4; i>=0; i=i-1) begin
            read_check(14'h042, i, "single-shot 4 to 0");
            irq_check(0, "single-shot not early");
            tick();
        end
        irq_check(1, "single-shot expiry");
        read_check(14'h042, 32'hffffffff, "single-shot terminal TVAL");
        read_check(14'h041, 5, "single-shot preserves En config");
        repeat (3) tick();
        read_check(14'h042, 32'hffffffff, "single-shot remains stopped");
        write_csr(14'h041, 32'hffffffff, 5);
        read_check(14'h042, 4, "restart single-shot");
        irq_check(1, "restart does not clear pending");
        reset_dut();
        write_csr(14'h041, 32'hffffffff, 7);
        for (j=0; j<2; j=j+1) begin
            for (i=4; i>=0; i=i-1) begin
                read_check(14'h042, i, "periodic countdown");
                tick();
            end
            read_check(14'h042, 4, "periodic reload");
            irq_check(1, "periodic pending");
        end
        reset_dut();
        write_csr(14'h041, 32'hffffffff, 1);
        read_check(14'h042, 0, "zero initial count"); irq_check(0, "zero waits one edge");
        tick(); irq_check(1, "zero count expiry");
        reset_dut();
        write_csr(14'h041, 32'hffffffff, 3);
        repeat (3) begin tick(); read_check(14'h042, 0, "zero periodic reload"); irq_check(1, "zero periodic expiry"); end
        reset_dut();
        write_csr(14'h041, 32'hffffffff, 8); // configure while disabled
        write_csr(14'h041, 1, 1); // masked write must load old InitVal + new En
        read_check(14'h041, 9, "TCFG merge");
        read_check(14'h042, 8, "masked En start uses merged InitVal");
        tick(); tick();
        write_csr(14'h041, 1, 0);
        read_check(14'h042, 6, "disable holds count on write edge");
        repeat (3) tick();
        read_check(14'h042, 6, "disabled holds count");
        write_csr(14'h041, 1, 1);
        read_check(14'h042, 8, "re-enable reloads");
        tick();
        write_csr(14'h041, 32'hfffffffc, 12);
        read_check(14'h041, 13, "InitVal-only write preserves En");
        read_check(14'h042, 12, "InitVal-only write reloads merged config");
        tick(); write_csr(14'h041, 0, 0);
        read_check(14'h042, 12, "accepted zero-mask write still reloads enabled config");
        // Reconfiguration at 0 and 1: reconfigure wins count, expiry is independent.
        for (i=0; i<=1; i=i+1) begin
            prepare_boundary(i);
            write_csr(14'h041, 1, 0);
            read_check(14'h042, i, "disable exactly at boundary holds");
            irq_check(i==0, "disable at boundary preserves old expiry event");
            tick(); read_check(14'h042, i, "disabled boundary remains stopped");
            prepare_boundary(i);
            write_csr(14'h041, 32'hffffffff, 9);
            read_check(14'h042, 8, "reconfigure beats old countdown");
            irq_check(i==0, "reconfigure at boundary retains old expiry");
        end
        prepare_boundary(1);
        wb_ex = 1; csr_we = 1; csr_num = 14'h041; csr_wmask = 32'hffffffff; csr_wvalue = 9;
        tick(); idle_inputs();
        read_check(14'h041, 5, "exception rejects TCFG write");
        read_check(14'h042, 0, "exception does not stall countdown");
        ertn_flush = 1; csr_we = 1; csr_num = 14'h041; csr_wmask = 32'hffffffff; csr_wvalue = 9;
        tick(); idle_inputs();
        read_check(14'h041, 5, "ERTN rejects TCFG write");
        irq_check(1, "expiry still happens during ERTN");
        end_group();

        begin_group("A09");
        write_csr(14'h041, 32'hffffffff, 1); tick();
        write_csr(14'h044, 0, 1); irq_check(1, "TICLR mask zero does not clear");
        write_csr(14'h044, 1, 0); irq_check(1, "TICLR value zero does not clear");
        write_csr(14'h044, 32'hfffffffe, 32'hffffffff); irq_check(1, "TICLR other bits ignored");
        wb_ex = 1;
        write_csr(14'h044, 1, 1); irq_check(1, "exception blocks software clear");
        wb_ex = 0; ertn_flush = 1;
        write_csr(14'h044, 1, 1); irq_check(1, "ERTN blocks software clear");
        ertn_flush = 0;
        write_csr(14'h044, 1, 1); irq_check(0, "valid TICLR clears pending");
        read_check(14'h044, 0, "TICLR never retains write value");
        for (i=0; i<=1; i=i+1) begin
            prepare_boundary(i);
            write_csr(14'h044, 1, 1);
            irq_check(i==0, "expiry beats same-edge clear only at old count zero");
            if (i==1) begin tick(); irq_check(1, "expiry after clear at count one"); end
            write_csr(14'h044, 1, 1); irq_check(0, "clear on next eligible edge");
        end
        end_group();

        begin_group("A10");
        saved_counter = counter_value;
        repeat (5) tick(); // no commits: module-level proxy for pipeline idle/stall
        check("no commits still count", counter_value, saved_counter+5);
        wb_ex = 1; tick(); idle_inputs();
        ertn_flush = 1; tick(); idle_inputs();
        write_csr(14'h041, 32'hffffffff, 5);
        tick(); tick();
        // Deliberate test-only deposit: no 2^32-cycle wait, no RTL modification.
        dut._STABLE_COUNTER = 64'h00000000ffffffff;
        #1; tick(); check("low32 carry", counter_value, 64'h0000000100000000);
        dut._STABLE_COUNTER = 64'hffffffffffffffff;
        #1; tick(); check("64-bit natural wrap", counter_value, 0);
        reset_dut(); check("reset after injection", counter_value, 0);
        end_group();

        $display("CSR_SUMMARY groups_passed=%0d groups_total=10 checks=%0d failures=%0d",
                 passed_groups, checks, failures);
        if (failures != 0) $fatal(1, "CSR self-test failed");
        $display("CSR_TEST_PASS");
        $finish;
    end
endmodule
