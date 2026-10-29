`timescale 1ns/1ps
// Real CPU stages and CSR. Divider placeholders reject any request.
// Synchronous instruction/data memory models; no course-image PASS claim.
module tb_ex8_smoke;
  reg clk=0; always #5 clk=~clk;
  reg resetn=0;
  wire ien,den; wire [3:0] iwe,dwe;
  wire [31:0] ia,iw,da,dw,pc,wd; wire [3:0] we; wire [4:0] rd;
  reg [31:0] ir=0,dr=0;
  reg [31:0] rom[0:255];
  reg expected[0:255],seen[0:255];
  reg [4:0] erd[0:255]; reg [31:0] eval[0:255];
  integer n=0,total=0,checks=0,exceptions=0,returns=0,stores=0;
  reg finished=0;
  mycpu_top dut(.clk(clk),.resetn(resetn),.hw_int_in(8'b0),
    .inst_sram_en(ien),.inst_sram_we(iwe),.inst_sram_addr(ia),
    .inst_sram_wdata(iw),.inst_sram_rdata(ir),
    .data_sram_en(den),.data_sram_we(dwe),.data_sram_addr(da),
    .data_sram_wdata(dw),.data_sram_rdata(dr),
    .debug_wb_pc(pc),.debug_wb_rf_we(we),.debug_wb_rf_wnum(rd),
    .debug_wb_rf_wdata(wd));
  function [31:0] csrinst(input [13:0] num,input [4:0] rj,input [4:0] dest);
    csrinst=32'h04000000 | ({18'b0,num}<<10) | ({27'b0,rj}<<5) | dest;
  endfunction
  function [31:0] addi(input [4:0] dest,input [4:0] src,input [11:0] imm);
    addi=32'h02800000 | ({20'b0,imm}<<10) | ({27'b0,src}<<5) | dest;
  endfunction
  task emit(input [31:0] ins,input bit writes,input [4:0] dest,input [31:0] val);
    rom[n]=ins; expected[n]=writes; erd[n]=dest; eval[n]=val;
    if(writes) total=total+1;
    n=n+1;
  endtask
  initial begin : setup
    integer i;
    for(i=0;i<256;i=i+1) begin
      rom[i]=32'h50000000; expected[i]=0; seen[i]=0;
    end
    emit(addi(5,0,12'h123),1,5,32'h123);
    emit(csrinst(14'h30,1,5),1,5,0);       // WR returns old zero
    emit(csrinst(14'h30,0,6),1,6,32'h123);
    emit(addi(7,6,1),1,7,32'h124);         // immediate dependency
    emit(addi(8,0,12'h0ff),1,8,32'hff);    // XCHG mask
    emit(addi(9,0,12'h055),1,9,32'h55);
    emit(csrinst(14'h30,8,9),1,9,32'h123);
    emit(csrinst(14'h30,0,10),1,10,32'h155);
    emit(csrinst(14'h30,1,0),0,0,0);       // rd=0 still writes CSR
    emit(csrinst(14'h30,0,11),1,11,0);
    emit(csrinst(14'h30,0,0),0,0,0);       // RD to zero has no debug write
    emit(addi(12,0,12'h066),1,12,32'h66);
    emit(csrinst(14'h3fff,1,12),1,12,0);   // unknown CSR returns zero
    emit(csrinst(14'h3fff,0,13),1,13,0);
    emit(32'h1438000e,1,14,32'h1c000000); // lu12i.w r14,0x1c000
    emit(addi(14,14,12'h100),1,14,32'h1c000100);
    emit(csrinst(14'hc,1,14),1,14,0);      // set exception entry
    emit(addi(20,0,0),1,20,0);
    emit(addi(21,0,12'h055),1,21,32'h55);
    emit(32'h002b0000,0,0,0);             // syscall at base+0x4c
    emit(32'h29800295,0,0,0);             // st.w r21,r20,0, after return only
    emit(addi(31,0,12'h777),1,31,32'h777);
    emit(32'h50000000,0,0,0);
    n=64;                                // handler at base+0x100
    emit(csrinst(14'h6,0,23),1,23,32'h1c00004c);
    emit(csrinst(14'h5,0,24),1,24,32'h000b0000);
    emit(addi(23,23,4),1,23,32'h1c000050);
    emit(csrinst(14'h6,1,23),1,23,32'h1c00004c);
    emit(32'h06483800,0,0,0);
    repeat(5) @(negedge clk);
    resetn=1;
  end
  always @(posedge clk) begin : monitor
    integer idx;
    if(ien) begin
      if(ia[31:10]!== (32'h1c000000>>10) || ia[1:0]!==0)
        $fatal(1,"Bad fetch address %h",ia);
      ir<=rom[ia[9:2]];
    end
    if(resetn && !dut.reset) begin
      if(dut.wb_ex) exceptions=exceptions+1;
      if(dut.ertn_flush) returns=returns+1;
      if(den && |dwe) begin
        stores=stores+1;
        if(returns!=1 || da!==0 || dw!==32'h55 || dwe!==4'hf)
          $fatal(1,"Unexpected/premature store addr=%h data=%h returns=%0d",da,dw,returns);
      end
      if(|we) begin
        idx=(pc-32'h1c000000)>>2;
        if(idx<0 || idx>255) $fatal(1,"Unexpected PC %h",pc);
        if(!expected[idx] || seen[idx] || rd!==erd[idx] || wd!==eval[idx] || we!==4'hf)
          $fatal(1,"Write mismatch pc=%h rd=%0d val=%h expected_rd=%0d expected_val=%h duplicate=%b",pc,rd,wd,erd[idx],eval[idx],seen[idx]);
        seen[idx]=1; checks=checks+1;
        $display("CHECK pc=%h r%0d=%h",pc,rd,wd);
        if(rd==31) begin
          if(checks!=total || exceptions!=1 || returns!=1 || stores!=1)
            $fatal(1,"Counts checks=%0d/%0d ex=%0d ertn=%0d stores=%0d",checks,total,exceptions,returns,stores);
          finished=1;
        end
      end
    end
  end
  initial begin
    wait(finished); repeat(20) @(negedge clk);
    if(exceptions!=1 || returns!=1 || stores!=1 || checks!=total)
      $fatal(1,"Repeated event after completion");
    $display("EX8_SMOKE_PASS write_checks=%0d exceptions=%0d returns=%0d stores=%0d",checks,exceptions,returns,stores);
    $finish;
  end
  initial begin #50000; $fatal(1,"TIMEOUT pc=%h",pc); end
endmodule

// Not a divider simulation. Any attempt to use these placeholders FAILS.
module div_signed(input aclk,aresetn,s_axis_divisor_tvalid,
  input [31:0] s_axis_divisor_tdata,input s_axis_dividend_tvalid,
  input [31:0] s_axis_dividend_tdata,output m_axis_dout_tvalid,
  output [63:0] m_axis_dout_tdata);
  assign m_axis_dout_tvalid=0; assign m_axis_dout_tdata=0;
  always @(posedge aclk) if(aresetn && (s_axis_divisor_tvalid || s_axis_dividend_tvalid))
    $fatal(1,"Divider used in non-division smoke test");
endmodule
module div_unsigned(input aclk,aresetn,s_axis_divisor_tvalid,
  input [31:0] s_axis_divisor_tdata,input s_axis_dividend_tvalid,
  input [31:0] s_axis_dividend_tdata,output m_axis_dout_tvalid,
  output [63:0] m_axis_dout_tdata);
  assign m_axis_dout_tvalid=0; assign m_axis_dout_tdata=0;
  always @(posedge aclk) if(aresetn && (s_axis_divisor_tvalid || s_axis_dividend_tvalid))
    $fatal(1,"Divider used in non-division smoke test");
endmodule
