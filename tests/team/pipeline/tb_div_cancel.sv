`timescale 1ns/1ps
`include "mycpu_head.v"
// EXE module stimuli with REAL generated div_signed/div_unsigned IP models.
// This file contains no replacement divider module.
module tb_div_cancel;
  reg clk=0; always #5 clk=~clk;
  reg reset=1,flush=0,pending=0,ms_allowin=1,valid=0;
  reg [159:0] bus_in=0; reg [163:0] meta_in=0;
  wire allowin,out_valid,mem_en,ctrl_valid,serializing;
  wire [106:0] bus_out; wire [163:0] meta_out;
  wire [40:0] feedback; wire [3:0] mem_we; wire [31:0] addr,data;
  integer sreq=0,ureq=0,retired=0,checks=0,low_edges=0,high_edges=0;
  bit saw_low=0;
  EXE_stage dut(.clk(clk),.reset(reset),.pipe_flush(flush),
    .ms_ex_pending(pending),.counter_value(64'b0),.ms_allowin(ms_allowin),
    .es_allowin(allowin),.ds_to_es_valid(valid),.ds_to_es_bus(bus_in),
    .ds_to_es_meta(meta_in),.es_to_ms_valid(out_valid),.es_to_ms_bus(bus_out),
    .es_to_ms_meta(meta_out),.es_to_ds_bus(feedback),
    .es_valid_for_ctrl(ctrl_valid),.es_serializing(serializing),
    .data_sram_en(mem_en),.data_sram_we(mem_we),
    .data_sram_addr(addr),.data_sram_wdata(data));

  function [159:0] packet(input integer op,input [31:0] a,b,input bit store);
    packet={12'h001,1'b1,store,1'b0,1'b0,5'd5,
      a,b,32'h12345678,32'h1c000100,
      1'b0,1'b0,1'b0,1'b0,
      1'b0,1'b0,1'b0,
      (op==1),(op==2),(op==3),(op==4)};
  endfunction
  task issue(input integer op,input [31:0] a,b,input bit store,input bit exception);
    integer t;
    @(negedge clk); t=0;
    while(!allowin) begin
      @(negedge clk); t=t+1;
      if(t>120) $fatal(1,"issue timeout");
    end
    bus_in=packet(op,a,b,store); meta_in=0;
    if(exception) meta_in[83:35]={1'b1,6'h0b,9'b0,1'b0,32'b0};
    valid=1;
    @(posedge clk); #1;
    @(negedge clk); valid=0;
  endtask
  task wait_request(input bit unsigned_op,input integer expected_count);
    integer t; t=0;
    while((unsigned_op ? ureq : sreq)<expected_count) begin
      @(negedge clk); t=t+1;
      if(t>120) $fatal(1,"request timeout");
    end
  endtask
  task expect_result(input [31:0] value,input integer retired_before);
    integer t; t=0;
    while(!out_valid) begin
      @(negedge clk); t=t+1;
      if(t>120) $fatal(1,"result timeout");
    end
    if(dut.es_result!==value) $fatal(1,"result got=%h expected=%h",dut.es_result,value);
    @(posedge clk); #1;
    if(retired!=retired_before+1) $fatal(1,"missing/duplicate retirement");
    checks=checks+1;
    $display("PASS result %h",value);
  endtask
  task cancel;
    @(negedge clk); flush=1; #1;
    if(dut.div_ip_aresetn!==0 || dut.div_signed_req!==0 || dut.div_unsigned_req!==0 || mem_en!==0 || mem_we!==0 || out_valid!==0)
      $fatal(1,"flush did not immediately suppress requests");
    @(posedge clk); #1;
    if(ctrl_valid!==0 || dut.div_signed_sent!==0 || dut.div_unsigned_sent!==0 || dut.div_signed_done!==0 || dut.div_unsigned_done!==0)
      $fatal(1,"flush did not clear state while stalled");
    @(negedge clk); flush=0;
    checks=checks+1;
  endtask
  task quiet(input integer cycles);
    integer oldret,olds,oldu,i;
    oldret=retired; olds=sreq; oldu=ureq;
    for(i=0;i<cycles;i=i+1) begin
      @(negedge clk);
      if(out_valid || dut.div_signed_done || dut.div_unsigned_done)
        $fatal(1,"stale result after cancellation/completion");
    end
    if(retired!=oldret || sreq!=olds || ureq!=oldu) $fatal(1,"duplicate output/request");
    checks=checks+1;
  endtask

  always @(posedge clk) begin
    if(dut.div_ip_aresetn===0) begin
      low_edges=low_edges+1; high_edges=0; saw_low=1;
    end else if(dut.div_ip_aresetn===1) begin
      if(saw_low) begin
        if(low_edges<2) $fatal(1,"IP reset shorter than two edges");
        saw_low=0; low_edges=0;
      end
      if((dut.div_signed_req || dut.div_unsigned_req) && high_edges<1)
        $fatal(1,"request without full recovery cycle");
      high_edges=high_edges+1;
    end
    if(!reset) begin
      if(dut.div_signed_req) sreq=sreq+1;
      if(dut.div_unsigned_req) ureq=ureq+1;
      if(out_valid && ms_allowin) retired=retired+1;
      if((reset || flush || pending || dut.es_exc_valid) && (mem_en || |mem_we))
        $fatal(1,"illegal memory side effect");
      if(dut.div_state!=2 && (dut.div_signed_req || dut.div_unsigned_req))
        $fatal(1,"request outside RUN");
    end
  end

  initial begin : cases
    integer sr,ur,r,i;
    repeat(5) @(negedge clk); reset=0;
    repeat(5) @(negedge clk);

    // Baseline REAL signed quotient/remainder and unsigned quotient/remainder.
    sr=sreq; r=retired; issue(1,-32'd100,7,0,0);
    wait_request(0,sr+1); expect_result(-32'd14,r); quiet(40);
    sr=sreq; r=retired; issue(2,-32'd100,7,0,0);
    wait_request(0,sr+1); expect_result(-32'd2,r); quiet(40);
    ur=ureq; r=retired; issue(3,32'hfffffff0,16,0,0);
    wait_request(1,ur+1); expect_result(32'h0fffffff,r); quiet(40);
    ur=ureq; r=retired; issue(4,32'hfffffff3,16,0,0);
    wait_request(1,ur+1); expect_result(3,r); quiet(40);

    // B07: signed task accepted, then cancelled; immediately queue unsigned.
    sr=sreq; issue(1,1234567,13,0,0); wait_request(0,sr+1);
    repeat(3) @(negedge clk); r=retired; cancel;
    ur=ureq; issue(3,1000,7,0,0); wait_request(1,ur+1);
    expect_result(142,r); quiet(45);
    if(sreq!=sr+1 || ureq!=ur+1) $fatal(1,"B07 duplicate request");

    // Reverse types: unsigned task cancelled, signed remainder follows.
    ur=ureq; issue(3,32'hfffffff0,3,0,0); wait_request(1,ur+1);
    repeat(2) @(negedge clk); r=retired; cancel;
    sr=sreq; issue(2,-32'd101,9,0,0); wait_request(0,sr+1);
    expect_result(-32'd2,r); quiet(45);
    if(sreq!=sr+1 || ureq!=ur+1) $fatal(1,"reverse duplicate request");

    // B08: restart during HOLD and again during RECOVER; queued division flushed.
    sr=sreq; issue(1,77777,11,0,0); wait_request(0,sr+1); cancel;
    cancel;
    wait(dut.div_state==1); cancel;
    r=retired; ur=ureq; issue(4,1001,9,0,0);
    wait_request(1,ur+1); expect_result(2,r); quiet(45);

    // Recovery must not block an ordinary ALU instruction.
    cancel; r=retired; issue(0,20,22,0,0); expect_result(42,r); quiet(5);

    // B06: result held under MEM backpressure, then flush has priority.
    ms_allowin=0; sr=sreq; issue(1,100,4,0,0); wait_request(0,sr+1);
    wait(dut.div_signed_done); @(negedge clk);
    for(i=0;i<3;i=i+1) begin
      if(!out_valid || dut.es_result!==25) $fatal(1,"result not held under backpressure");
      @(negedge clk);
    end
    cancel; ms_allowin=1; quiet(45);

    // Already marked exception: no division request, no waiting for done.
    sr=sreq; ur=ureq; r=retired;
    issue(1,100,3,0,1);
    if(!out_valid || !meta_out[83]) $fatal(1,"exception division stuck/lost metadata");
    @(posedge clk); #1;
    if(sreq!=sr || ureq!=ur || retired!=r+1) $fatal(1,"exception started divider");
    quiet(40);

    // B05: older MEM exception suppresses younger store BEFORE WB flush.
    pending=1; issue(0,32'h1000,0,1,0);
    if(mem_en || |mem_we) $fatal(1,"younger store escaped older exception");
    @(posedge clk); @(negedge clk); pending=0;
    checks=checks+1;

    $display("REAL_DIV_CANCEL_PASS checks=%0d signed_requests=%0d unsigned_requests=%0d",checks,sreq,ureq);
    $finish;
  end
  initial begin #50000; $fatal(1,"TIMEOUT state=%0d sent=%b%b done=%b%b",dut.div_state,dut.div_signed_sent,dut.div_unsigned_sent,dut.div_signed_done,dut.div_unsigned_done); end
endmodule
