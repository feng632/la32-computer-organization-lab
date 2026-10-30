`timescale 1ns/1ps
// Real CPU + CSR; synchronous test memories. Divider guard definitions are
// compiled from tb_ex8_smoke.sv, but that test's top is NOT elaborated.
module tb_ex9_program;
  reg clk=0; always #5 clk=~clk;
  reg resetn=0; reg [7:0] hw=0;
  wire ien,den; wire [3:0] iwe,dwe,we;
  wire [31:0] ia,iw,da,dw,pc,wd; wire [4:0] rd;
  reg [31:0] ir=0,dr=32'haabbccdd;
  reg [31:0] rom[0:255],want[0:255];
  integer kind[0:255]; reg [4:0] dest[0:255];
  bit seen[0:255],sampled[0:255];
  reg [31:0] trap_pc[0:15],trap_addr[0:15];
  reg [5:0] trap_code[0:15]; bit trap_badv[0:15];
  integer mode=0,n=0,ntraps=0,ex_count=0,ret_count=0,checks=0;
  integer main_total=0,main_seen=0,stores=0,loads=0,mem_expected=0;
  bit finished=0;
  mycpu_top dut(.clk(clk),.resetn(resetn),.hw_int_in(hw),
    .inst_sram_en(ien),.inst_sram_we(iwe),.inst_sram_addr(ia),
    .inst_sram_wdata(iw),.inst_sram_rdata(ir),
    .data_sram_en(den),.data_sram_we(dwe),.data_sram_addr(da),
    .data_sram_wdata(dw),.data_sram_rdata(dr),
    .debug_wb_pc(pc),.debug_wb_rf_we(we),.debug_wb_rf_wnum(rd),
    .debug_wb_rf_wdata(wd));
  function [31:0] csrins(input [13:0] num,input [4:0] rj,d);
    csrins=32'h04000000 | ({18'b0,num}<<10) | ({27'b0,rj}<<5) | d;
  endfunction
  function [31:0] addi(input [4:0] d,s,input [11:0] imm);
    addi=32'h02800000 | ({20'b0,imm}<<10) | ({27'b0,s}<<5) | d;
  endfunction
  function [31:0] ori0(input [4:0] d,input [11:0] imm);
    ori0=32'h03800000 | ({20'b0,imm}<<10) | d;
  endfunction
  function [31:0] memins(input [31:0] opcode,input [4:0] d,s,input [11:0] off);
    memins=opcode | ({20'b0,off}<<10) | ({27'b0,s}<<5) | d;
  endfunction
  task emit(input [31:0] ins,input integer k,input [4:0] d,input [31:0] val);
    rom[n]=ins; kind[n]=k; dest[n]=d; want[n]=val;
    if(n<128 && k!=0) main_total=main_total+1;
    n=n+1;
  endtask
  task trapins(input [31:0] ins,input [5:0] code,input bit bad,input [31:0] address);
    trap_pc[ntraps]=32'h1c000000+4*n;
    trap_code[ntraps]=code; trap_badv[ntraps]=bad; trap_addr[ntraps]=address;
    ntraps=ntraps+1; emit(ins,0,0,0);
  endtask
  initial begin : setup
    integer i,cfg_fd,cfg_items; reg [11:0] mask;
    // A per-run file avoids Windows batch argument handling of '='.
    cfg_fd=$fopen("case.txt","r");
    if(!cfg_fd) $fatal(1,"Missing case.txt configuration");
    cfg_items=$fscanf(cfg_fd,"%d",mode); $fclose(cfg_fd);
    if(cfg_items!=1 || mode<0 || mode>11) $fatal(1,"Bad case.txt configuration");
    for(i=0;i<256;i=i+1) begin
      rom[i]=32'h50000000; kind[i]=0; seen[i]=0; sampled[i]=0;
      want[i]=0; dest[i]=0;
    end
    emit(32'h1438000e,1,14,32'h1c000000);
    emit(addi(14,14,12'h200),1,14,32'h1c000200);
    emit(csrins(14'hc,1,14),1,14,0); // EENTRY
    emit(addi(20,0,0),1,20,0);
    emit(addi(21,0,12'h055),1,21,32'h55);
    emit(addi(27,0,1),1,27,1); // TICLR value in handler
    if(mode==0) begin
      emit(addi(7,0,12'h345),1,7,32'h345);
      emit(csrins(14'h40,1,7),1,7,0);
      emit(32'h00006140,1,10,32'h345); // RDCNTID destination rj=r10
      emit(addi(15,10,1),1,15,32'h346);
      emit(32'h0000600b,2,11,0); // LOW; expected captured independently
      emit(addi(13,11,1),8,13,0); // immediate dependency on LOW
      emit(32'h0000640c,2,12,0); // HIGH
      emit(32'h00006000,0,0,0);  // overlapping r0 alias, no write
      trapins(32'h002a0001,6'h0c,0,0); // BREAK nonzero code
      trapins(32'hffffffff,6'h0d,0,0); // unsupported encoding
      trapins(32'h00000000,6'h0d,0,0); // unsupported zero
      trapins(memins(32'h28800000,5,20,1),9,1,1); // LD.W
      trapins(memins(32'h28400000,5,20,1),9,1,1); // LD.H
      trapins(memins(32'h2a400000,5,20,1),9,1,1); // LD.HU
      trapins(memins(32'h29800000,21,20,2),9,1,2); // ST.W
      trapins(memins(32'h29400000,21,20,1),9,1,1); // ST.H
      emit(memins(32'h2a000000,16,20,1),1,16,32'hcc); // legal byte
      emit(memins(32'h28400000,17,20,2),1,17,32'hffffaabb); // legal half
      emit(memins(32'h2a400000,18,20,2),1,18,32'haabb);
      emit(memins(32'h28800000,19,20,0),1,19,32'haabbccdd);
      mem_expected=4;
    end else begin
      // mode 1: software, 2..9: eight hardware lines, 10: timer,
      // mode 11: interrupt cancels CSRWR then re-executes it after ERTN.
      mask=(mode==1 || mode==11) ? 12'h001 :
           (mode==10) ? 12'h800 : (12'h004 << (mode-2));
      emit(ori0(7,mask),1,7,{20'b0,mask});
      emit(csrins(14'h4,1,7),1,7,0);
      if(mode==1 || mode==11) begin
        emit(addi(7,0,1),1,7,1);
        emit(csrins(14'h5,1,7),1,7,0);
      end else if(mode==10) begin
        emit(addi(7,0,5),1,7,5); // one-shot timer initial count4
        emit(csrins(14'h41,1,7),1,7,0);
      end else hw=8'b1 << (mode-2);
      if(mode==11) emit(addi(5,0,12'h123),1,5,32'h123);
      emit(addi(7,0,4),1,7,4);
      emit(csrins(14'h0,1,7),1,7,8); // enable IE, DA stays 1
      trap_pc[0]=32'h1c000000+4*n;
      trap_code[0]=0; trap_badv[0]=0; trap_addr[0]=0; ntraps=1;
      if(mode==11) begin
        emit(csrins(14'h30,1,5),1,5,0);
        emit(csrins(14'h30,0,6),1,6,32'h123);
      end
    end
    emit(memins(32'h29800000,21,20,0),0,0,0);
    emit(addi(31,0,12'h777),1,31,32'h777);
    emit(32'h50000000,0,0,0);
    n=128;
    emit(csrins(14'h6,0,25),3,25,0);
    emit(csrins(14'h5,0,26),4,26,0);
    emit(csrins(14'h7,0,24),7,24,0);
    if(mode==0) begin
      emit(addi(25,25,4),5,25,0);
      emit(csrins(14'h6,1,25),6,25,0);
    end
    emit(csrins(14'h5,1,0),0,0,0);  // clear software interrupt
    emit(csrins(14'h41,1,0),0,0,0); // disable timer
    emit(csrins(14'h44,1,27),1,27,0); // clear timer pending, read returns0
    emit(32'h06483800,0,0,0);
    repeat(6) @(negedge clk); resetn=1;
  end

  always @(posedge clk) begin : monitor
    integer idx,t; reg [31:0] value,status; reg sample;
    reg [31:0] sample_value; integer sample_idx;
    sample=0;
    if(ien) begin
      if(ia[31:10]!== (32'h1c000000>>10) || ia[1:0]!==0)
        $fatal(1,"unexpected fetch %h",ia);
      ir<=rom[ia[9:2]];
    end
    if(den && dwe==0) dr<=32'haabbccdd;
    if(resetn && !dut.reset) begin
      // Independent reference: value BEFORE the actual transfer edge.
      if(dut.es_to_ms_valid && dut.ms_allowin && !dut.pipe_flush &&
         dut.u_exe_stage.es_cnt_op!=0 && !dut.u_exe_stage.es_exc_valid) begin
        sample_idx=(dut.u_exe_stage.es_pc-32'h1c000000)>>2;
        if(dut.u_exe_stage.es_cnt_op==1 || dut.u_exe_stage.es_cnt_op==2) begin
          sample_value=(dut.u_exe_stage.es_cnt_op==1) ? dut.counter_value[31:0] : dut.counter_value[63:32];
          want[sample_idx]=sample_value; sampled[sample_idx]=1; sample=1;
        end
      end
      if(dut.wb_ex) begin
        t=ex_count;
        if(t>=ntraps || dut.wb_pc!==trap_pc[t] || dut.wb_ecode!==trap_code[t] ||
           dut.wb_esubcode!==0 || dut.wb_badv_valid!==trap_badv[t] ||
           dut.wb_badv!==(trap_badv[t] ? trap_addr[t] : 32'b0) || |we || dut.csr_we)
          $fatal(1,"trap mismatch CASE=%0d index=%0d pc=%h expected=%h ecode=%h expected=%h badv=%h",mode,t,dut.wb_pc,trap_pc[t],dut.wb_ecode,trap_code[t],dut.wb_badv);
        ex_count=ex_count+1;
        if(mode>=2 && mode<=9) hw<=0;
        $display("PASS trap CASE=%0d pc=%h ecode=%h badv=%h",mode,dut.wb_pc,dut.wb_ecode,dut.wb_badv);
      end
      if(dut.ertn_flush) ret_count=ret_count+1;
      if(dut.u_id_stage.ds_valid && dut.u_id_stage.ds_exc[48] && dut.u_id_stage.br_taken)
        $fatal(1,"exception instruction redirected as branch");
      if(den) begin
        if(|dwe) begin
          stores=stores+1;
          if(ret_count!=ntraps || da!==0 || dw!==32'h55 || dwe!==4'hf)
            $fatal(1,"premature/bad store CASE=%0d addr=%h data=%h returns=%0d",mode,da,dw,ret_count);
        end else begin
          loads=loads+1;
          if(mode!=0 || ex_count!=ntraps || da>3) $fatal(1,"exception memory request escaped addr=%h",da);
        end
      end
      if(|we) begin
        idx=(pc-32'h1c000000)>>2;
        if(idx<0 || idx>255 || kind[idx]==0 || rd!==dest[idx] || we!==4'hf)
          $fatal(1,"unexpected write CASE=%0d pc=%h rd=%0d value=%h",mode,pc,rd,wd);
        value=want[idx];
        case(kind[idx])
          2: if(!sampled[idx]) $fatal(1,"counter write has no prior sample");
          3: value=trap_pc[ex_count-1];
          4: begin
            status=(mode==1 || mode==11) ? 1 : (mode==10 ? 32'h800 : 0);
            value=({26'b0,trap_code[ex_count-1]}<<16) | status;
          end
          5: value=trap_pc[ex_count-1]+4;
          6: value=trap_pc[ex_count-1];
          7: value=(mode==0 && ex_count>3) ? trap_addr[ex_count-1] : 0;
          8: value=want[idx-1]+1;
        endcase
        if(wd!==value) $fatal(1,"write mismatch CASE=%0d pc=%h r%0d got=%h expected=%h",mode,pc,rd,wd,value);
        if(idx<128) begin
          if(seen[idx]) $fatal(1,"duplicate main instruction %h",pc);
          seen[idx]=1; main_seen=main_seen+1;
        end
        checks=checks+1;
        if(rd==31) finished=1;
      end
    end
    #1;
    if(sample && dut.u_mem_stage.es_to_ms_meta_r[31:0]!==sample_value)
      $fatal(1,"counter not sampled at EXE->MEM transfer");
  end
  initial begin
    wait(finished); repeat(25) @(negedge clk);
    if(ex_count!=ntraps || ret_count!=ntraps || stores!=1 || loads!=mem_expected || main_seen!=main_total)
      $fatal(1,"counts CASE=%0d traps=%0d/%0d returns=%0d stores=%0d loads=%0d/%0d main=%0d/%0d",mode,ex_count,ntraps,ret_count,stores,loads,mem_expected,main_seen,main_total);
    $display("EX9_PROGRAM_PASS CASE=%0d writes=%0d traps=%0d returns=%0d loads=%0d stores=%0d",mode,checks,ex_count,ret_count,loads,stores);
    $finish;
  end
  initial begin #100000; $fatal(1,"TIMEOUT CASE=%0d pc=%h ds=%h has_int=%b",mode,pc,dut.u_id_stage.ds_pc,dut.has_int); end
endmodule
