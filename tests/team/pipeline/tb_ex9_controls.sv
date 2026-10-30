`timescale 1ns/1ps
// Direct module stimuli for B11/B12 and exception priority. Divider guards from
// tb_ex8_smoke reject every divider request. No CPU-source modification/force.
module tb_ex9_controls;
  reg clk=0; always #5 clk=~clk;
  reg reset=1,flush=0,has_int=0,id_allow=0,older=0;
  reg fsvalid=0; reg [63:0] fsbus=0; reg [48:0] fsex=0;
  wire dsallow,dsvalid; wire [159:0] dsbus; wire [163:0] dsmeta; wire [32:0] br;
  ID_stage iddut(.clk(clk),.reset(reset),.pipe_flush(flush),.has_int(has_int),
    .es_valid_for_ctrl(older),.ms_valid_for_ctrl(1'b0),.ws_valid_for_ctrl(1'b0),
    .es_serializing(1'b0),.ms_serializing(1'b0),.ws_serializing(1'b0),
    .es_allowin(id_allow),.ds_allowin(dsallow),.fs_to_ds_valid(fsvalid),
    .fs_to_ds_bus(fsbus),.fs_to_ds_ex(fsex),.ds_to_es_valid(dsvalid),
    .ds_to_es_bus(dsbus),.ds_to_es_meta(dsmeta),.br_bus(br),
    .ws_to_rf_bus(38'b0),.es_to_ds_bus(41'b0),.ms_to_ds_bus(39'b0),.ws_to_ds_bus(39'b0));

  reg ev=0,wsallow=0; reg [159:0] ebus=0; reg [163:0] emeta=0;
  reg [63:0] counter=64'h12345678fffffffc;
  wire ea,mallow,mvalid,mem_en,evalid; wire [3:0] mem_we; wire [31:0] addr,data;
  wire [106:0] eout; wire [163:0] eoutmeta,moutmeta;
  wire [69:0] mout; wire [40:0] efb; wire [38:0] mfb;
  wire ectrl,eserial,mctrl,mserial,mpending;
  EXE_stage edut(.clk(clk),.reset(reset),.pipe_flush(flush),
    .ms_ex_pending(1'b0),.counter_value(counter),.ms_allowin(mallow),
    .es_allowin(ea),.ds_to_es_valid(ev),.ds_to_es_bus(ebus),.ds_to_es_meta(emeta),
    .es_to_ms_valid(evalid),.es_to_ms_bus(eout),.es_to_ms_meta(eoutmeta),
    .es_to_ds_bus(efb),.es_valid_for_ctrl(ectrl),.es_serializing(eserial),
    .data_sram_en(mem_en),.data_sram_we(mem_we),.data_sram_addr(addr),.data_sram_wdata(data));
  MEM_stage mdut(.clk(clk),.reset(reset),.pipe_flush(flush),.ws_allowin(wsallow),
    .ms_allowin(mallow),.es_to_ms_valid(evalid),.es_to_ms_bus(eout),
    .es_to_ms_meta(eoutmeta),.ms_to_ws_valid(mvalid),.ms_to_ws_bus(mout),
    .ms_to_ws_meta(moutmeta),.ms_to_ds_bus(mfb),.data_sram_rdata(32'hdeadbeef),
    .ms_valid_for_ctrl(mctrl),.ms_serializing(mserial),.ms_ex_pending(mpending));
  always @(posedge clk) if(reset) counter<=64'h12345678fffffffc; else counter<=counter+1;
  integer checks=0,id_transfers=0;
  always @(posedge clk) if(!reset && !flush && dsvalid && id_allow) id_transfers=id_transfers+1;

  task id_issue(input [31:0] ins,input [48:0] exc);
    @(negedge clk);
    if(!dsallow) $fatal(1,"ID not ready");
    fsbus={ins,32'h1c001000}; fsex=exc; fsvalid=1;
    @(posedge clk); #1; @(negedge clk); fsvalid=0;
  endtask
  task id_clear;
    @(negedge clk); flush=1;
    @(negedge clk); flush=0; id_allow=0; older=0; has_int=0;
  endtask
  function [159:0] packet(input bit load,input [31:0] pc);
    packet={12'h001,1'b1,1'b0,1'b0,1'b0,5'd5,
      32'h00001001,32'b0,32'b0,pc,
      load,1'b0,1'b0,1'b0,7'b0};
  endfunction
  task exe_issue(input [1:0] cnt,input bit load,input [48:0] exc);
    @(negedge clk); if(!ea) $fatal(1,"EXE not ready");
    ebus=packet(load,32'h1c002000); emeta=0;
    emeta[33:32]=cnt; emeta[83:35]=exc; ev=1;
    @(posedge clk); #1; @(negedge clk); ev=0;
  endtask
  task count_case(input [1:0] cnt);
    reg [31:0] sampled_value; reg [163:0] saved;
    integer i;
    if(cnt==1) begin
      @(negedge clk); counter=64'h12345678fffffffc;
    end
    // Fill MEM with an older ordinary instruction while downstream blocked.
    wsallow=0; exe_issue(0,0,0);
    @(posedge clk); #1;
    if(!mvalid) $fatal(1,"MEM filler missing");
    exe_issue(cnt,0,0);
    repeat(4) @(negedge clk);
    if(mallow || !evalid || eoutmeta[33:32]!==cnt) $fatal(1,"expected EXE backpressure");
    if(efb[38]!==0) $fatal(1,"counter ALU placeholder forwarded from EXE");
    wsallow=1;
    @(posedge clk);
    sampled_value=(cnt==1) ? counter[31:0] : counter[63:32];
    #1;
    if(moutmeta[31:0]!==sampled_value || moutmeta[33:32]!==cnt)
      $fatal(1,"counter sampling mismatch got=%h expected=%h",moutmeta[31:0],sampled_value);
    saved=moutmeta;
    @(negedge clk); wsallow=0;
    for(i=0;i<4;i=i+1) begin
      @(negedge clk);
      if(moutmeta!==saved) $fatal(1,"MEM counter value changed while blocked");
      if(mfb[37]!==0) $fatal(1,"counter ALU placeholder forwarded from MEM");
    end
    wsallow=1; @(posedge clk); #1;
    checks=checks+1;
    $display("PASS counter stall cnt_op=%0d sampled=%h",cnt,sampled_value);
  endtask

  initial begin
    integer before_count;
    repeat(5) @(negedge clk); reset=0;
    // B11: interrupt appears then disappears while EXE refuses acceptance.
    id_issue(32'h02800405,0); // addi r5,r0,1
    before_count=id_transfers; has_int=1; #1;
    if(dsmeta[83]!==1 || dsmeta[82:77]!==0 || dsbus[147]!==0)
      $fatal(1,"INT candidate did not cancel ADD write");
    repeat(3) @(negedge clk);
    if(id_transfers!=before_count) $fatal(1,"interrupt accepted while blocked");
    has_int=0; #1;
    if(dsmeta[83]!==0 || dsbus[147]!==1) $fatal(1,"stale interrupt before acceptance");
    id_allow=1; @(posedge clk); #1;
    if(id_transfers!=before_count+1) $fatal(1,"normal instruction not released");
    checks=checks+1; id_clear;

    // INT candidate drains older instructions; latch it at actual acceptance.
    older=1; has_int=1; id_allow=1;
    id_issue(32'h29800295,0); // store
    before_count=id_transfers; #1;
    if(dsvalid!==0 || dsbus[146]!==0 || dsmeta[163:84]!==0 || dsmeta[34:0]!==0)
      $fatal(1,"INT did not drain/cancel store");
    repeat(3) @(negedge clk);
    if(id_transfers!=before_count) $fatal(1,"passed older instruction");
    older=0; #1;
    if(!dsvalid) $fatal(1,"INT drain deadlock");
    // Capture the exact transfer metadata into a real EXE separately.
    emeta=dsmeta; ebus=dsbus; ev=1;
    @(posedge clk); #1;
    @(negedge clk); has_int=0; ev=0;
    if(edut.ds_to_es_meta_r[83]!==1 || eoutmeta[82:77]!==0 || mem_en || |mem_we)
      $fatal(1,"accepted INT was lost when has_int fell");
    checks=checks+1; id_clear;

    // Existing ADEF must survive placeholder zero decoding as INE.
    id_issue(0,{1'b1,6'h08,9'b0,1'b1,32'h1c000003}); #1;
    if(dsmeta[83:35]!=={1'b1,6'h08,9'b0,1'b1,32'h1c000003})
      $fatal(1,"INE overwrote existing IF exception");
    has_int=1; #1;
    if(dsmeta[82:77]!==0 || dsmeta[67]!==0) $fatal(1,"INT priority incorrect");
    checks=checks+1; id_clear;

    // Interrupt on branch, CSR write, ERTN: no original task survives.
    has_int=1; id_issue(32'h50000400,0); id_allow=1; #1;
    if(br[32] || dsbus[147] || dsbus[146]) $fatal(1,"INT branch side effect");
    checks=checks+1; id_clear;
    has_int=1; id_issue(32'h0400c025,0); #1; // CSRWR SAVE0,r5
    if(dsmeta[163:84]!==0) $fatal(1,"INT retained CSR task");
    checks=checks+1; id_clear;
    has_int=1; id_issue(32'h06483800,0); #1;
    if(dsmeta[34]!==0 || dsmeta[83]!==1) $fatal(1,"INT retained ERTN task");
    checks=checks+1; id_clear;

    // B12: low and NONZERO high halves, backpressure and rollover stimulus.
    count_case(1); count_case(2);
    // Incoming INT has priority over an unaligned load's locally detected ALE.
    wsallow=1; exe_issue(0,1,{1'b1,6'h00,9'b0,1'b0,32'b0}); #1;
    if(eoutmeta[83:35]!=={1'b1,6'h00,9'b0,1'b0,32'b0} || mem_en || |mem_we)
      $fatal(1,"ALE overwrote incoming INT or accessed memory");
    checks=checks+1;
    $display("EX9_CONTROLS_PASS checks=%0d",checks);
    $finish;
  end
  initial begin #20000; $fatal(1,"TIMEOUT controls"); end
endmodule
