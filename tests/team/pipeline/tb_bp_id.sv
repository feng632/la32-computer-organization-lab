`timescale 1ns/1ps
// Real ID + regfile + decoders. Port stimuli only: no force, no CPU edits.
module tb_bp_id;
  reg clk=0; always #5 clk=~clk;
  reg reset=1,flush=0,has_int=0,allow=0,older=0,serial=0;
  reg fv=0;
  reg [63:0] fbus=0;
  reg [48:0] fexc=0;
  reg [33:0] prediction=0;
  reg [37:0] rfwrite=0;
  reg [40:0] efb=0;
  reg [38:0] mfb=0,wfb=0;
  wire da,dv;
  wire [159:0] dbus;
  wire [163:0] meta;
  wire [32:0] redirect;
  wire [67:0] update_bus;
  integer checks=0,cases=0,updates=0,redirects=0;
  ID_stage dut(.clk(clk),.reset(reset),.pipe_flush(flush),.has_int(has_int),
    .es_valid_for_ctrl(older),.ms_valid_for_ctrl(1'b0),.ws_valid_for_ctrl(1'b0),
    .es_serializing(serial),.ms_serializing(1'b0),.ws_serializing(1'b0),
    .es_allowin(allow),.ds_allowin(da),.fs_to_ds_valid(fv),
    .fs_to_ds_bus(fbus),.fs_to_ds_ex(fexc),.fs_to_ds_bp(prediction),
    .ds_to_es_valid(dv),.ds_to_es_bus(dbus),.ds_to_es_meta(meta),
    .br_bus(redirect),.bp_update_bus(update_bus),.ws_to_rf_bus(rfwrite),
    .es_to_ds_bus(efb),.ms_to_ds_bus(mfb),.ws_to_ds_bus(wfb));

  always @(posedge clk) begin
    if(update_bus[67]===1'b1) updates=updates+1;
    if(redirect[32]===1'b1) redirects=redirects+1;
  end
  task ck(input bit ok,input string msg);
    if(!ok) $fatal(1,"BP_ID_FAIL case=%0d t=%0t %s",cases,$time,msg);
    checks=checks+1;
  endtask
  function [31:0] cb(input [5:0] op,input [4:0] rj,input [4:0] rd,input [15:0] off);
    cb={op,off,rj,rd};
  endfunction
  function [31:0] jump(input [5:0] op,input [25:0] off);
    jump={op,off[15:0],off[25:16]};
  endfunction
  task wr(input [4:0] regno,input [31:0] value);
    @(negedge clk); rfwrite={1'b1,regno,value};
    @(posedge clk); #1;
    @(negedge clk); rfwrite=0;
  endtask
  // Load ID while EXE refuses acceptance. Do not act on raw comparison yet.
  task issue(input [31:0] inst,input [31:0] pc,input [31:0] pred,
             input [1:0] flags,input [48:0] exc);
    @(negedge clk); allow=0;
    ck(da===1'b1,"ID must be empty before issue");
    fbus={inst,pc}; prediction={flags,pred}; fexc=exc; fv=1;
    @(posedge clk); #1;
    @(negedge clk); fv=0;
    #1;
    ck(update_bus===68'b0 && redirect===33'b0,"no events before actual acceptance");
  endtask
  task quiet(input integer clocks);
    integer u,r;
    u=updates; r=redirects;
    repeat(clocks) begin
      #1; ck(update_bus===0 && redirect===0,"events while stalled/canceled");
      @(negedge clk);
    end
    ck(updates==u && redirects==r,"event count changed while stalled/canceled");
  endtask
  // Expected packed packet is supplied from test scenario, never from DUT wires.
  task finish_case(input bit normal,input bit branch,input bit cond,input bit taken,
                   input [31:0] pc,input [31:0] target,input bit fix,
                   input [31:0] correct_next);
    reg [67:0] expected_update;
    reg [32:0] expected_redirect;
    integer u,r;
    expected_update=normal ? {1'b1,branch,cond,taken,pc,target} : 68'b0;
    expected_redirect=fix ? {1'b1,correct_next} : 33'b0;
    u=updates; r=redirects; allow=1; #1;
    ck(dv===1'b1,"instruction should be ready to transfer");
    ck(update_bus===expected_update,$sformatf("update got=%h expected=%h",update_bus,expected_update));
    ck(redirect===expected_redirect,$sformatf("redirect got=%h expected=%h",redirect,expected_redirect));
    @(posedge clk); #1;
    ck(updates==u+normal && redirects==r+fix,"event missing or repeated at transfer edge");
    ck(update_bus===0 && redirect===0,"stale events after instruction left ID");
    @(negedge clk); allow=0; cases=cases+1;
  endtask

  initial begin : suite
    integer op,values,p,mode;
    reg [31:0] lhs,rhs,pc,target,nextpc,pred,inst;
    reg taken;
    repeat(4) @(negedge clk); reset=0;
    quiet(2);
    // Six conditional branches: equal and signed/unsigned opposite ordering.
    for(values=0;values<3;values=values+1) begin
      case(values)
        0: begin lhs=5; rhs=5; end
        1: begin lhs=32'hffffffff; rhs=1; end
        2: begin lhs=1; rhs=32'hffffffff; end
      endcase
      wr(10,lhs); wr(11,rhs);
      for(op=6'h16;op<=6'h1b;op=op+1) begin
        case(op)
          'h16: taken=(lhs==rhs);
          'h17: taken=(lhs!=rhs);
          'h18: taken=($signed(lhs)<$signed(rhs));
          'h19: taken=($signed(lhs)>=$signed(rhs));
          'h1a: taken=(lhs<rhs);
          'h1b: taken=(lhs>=rhs);
        endcase
        pc=32'h1c001000; target=pc+32'h20; nextpc=taken?target:pc+4;
        for(p=0;p<3;p=p+1) begin
          pred=(p==0)?nextpc:(p==1)?(taken?pc+4:target):32'h1c002000;
          issue(cb(op,10,11,16'd8),pc,pred,(pred==pc+4)?2'b00:2'b11,0);
          finish_case(1,1,1,taken,pc,target,p!=0,nextpc);
        end
      end
    end
    $display("PASS conditional branches cases=%0d",cases);

    // B and BL: negative PC-relative offset and mismatched target.
    for(op=6'h14;op<=6'h15;op=op+1) begin
      for(p=0;p<3;p=p+1) begin
        pc=32'h1c003000; target=pc-16;
        pred=(p==0)?target:(p==1)?pc+4:target+4;
        issue(jump(op,26'h3fffffc),pc,pred,(pred==pc+4)?2'b00:2'b11,0);
        if(op=='h15) begin
          ck(dbus[147]===1 && dbus[143:139]===5'd1,"BL destination must remain r1");
          ck(dbus[138:107]===pc && dbus[106:75]===32'd4,"BL link operands PC+4");
        end
        finish_case(1,1,0,1,pc,target,p!=0,target);
      end
    end
    // JIRL: changing register target, plus deliberately unaligned real target.
    for(mode=0;mode<3;mode=mode+1) begin
      target=(mode==2)?32'h1003:32'h1000+mode*32'h100;
      wr(5,target+4);
      for(p=0;p<3;p=p+1) begin
        pc=32'h1c004000; pred=(p==0)?target:(p==1)?pc+4:target+8;
        issue(cb(6'h13,5,7,16'hffff),pc,pred,(pred==pc+4)?2'b00:2'b11,0);
        ck(dbus[147]===1 && dbus[143:139]===5'd7,"JIRL destination must remain rd");
        ck(dbus[138:107]===pc && dbus[106:75]===32'd4,"JIRL link operands PC+4");
        finish_case(1,1,0,1,pc,target,p!=0,target);
      end
    end
    // Ordinary instructions must correct false branch predictions too.
    for(p=0;p<2;p=p+1) begin
      pc=32'h1c005000; pred=p?32'h12345678:pc+4;
      issue(32'h02800406,pc,pred,2'b11,0); // ADDI r6,r0,1
      finish_case(1,0,0,0,pc,0,p!=0,pc+4);
    end
    pc=32'hfffffffc;
    issue(32'h02800406,pc,0,0,0);
    finish_case(1,0,0,0,pc,0,0,0); // 32-bit sequential wrap
    issue(jump(6'h14,0),pc,0,0,0);
    finish_case(1,1,0,1,pc,pc,1,pc); // B self-loop
    $display("PASS jumps, links, ordinary false predictions and wrap");

    // Freeze an instruction and present different valid IF contents: no capture.
    pc=32'h1c006000; target=pc+32'h20;
    issue(jump(6'h14,8),pc,pc+4,2'b00,0);
    fbus={32'h02800406,32'hdeadbeec}; prediction={2'b11,32'hdeadbef0}; fv=1;
    quiet(4);
    fv=0;
    finish_case(1,1,0,1,pc,target,1,target);

    // Load-use hold; after release use actual MEM forwarded value (r10=0).
    pc=32'h1c007000; target=pc+32'h20;
    efb={1'b1,1'b1,1'b1,5'd10,32'b0,1'b1};
    issue(cb(6'h16,10,0,8),pc,pc+4,0,0);
    allow=1; #1; ck(dv===0,"load-use must prevent transfer"); quiet(3);
    efb=0; mfb={1'b1,1'b1,5'd10,32'b0};
    finish_case(1,1,1,1,pc,target,1,target); mfb=0;

    // EXE multi-cycle dependency (such as division), then ready forwarding.
    efb={1'b1,1'b0,1'b1,5'd10,32'b0,1'b0};
    issue(cb(6'h16,10,0,8),pc,pc+4,0,0);
    allow=1; #1; ck(dv===0,"unready EXE result must block"); quiet(3);
    efb={1'b1,1'b0,1'b1,5'd10,32'b0,1'b1};
    finish_case(1,1,1,1,pc,target,1,target); efb=0;

    // Older serializing operation blocks a younger branch until release.
    serial=1; issue(jump(6'h14,8),pc,pc+4,0,0); allow=1;
    #1; ck(dv===0,"serialization must prevent branch transfer"); quiet(3);
    serial=0; finish_case(1,1,0,1,pc,target,1,target);
    $display("PASS backpressure, metadata hold, load-use, EXE wait, serialization");

    // ID exceptions and ERTN do not train or redirect even with a bad prediction.
    for(mode=0;mode<5;mode=mode+1) begin
      case(mode)
        0: inst=32'h002b0000; // SYSCALL
        1: inst=32'h002a0000; // BREAK
        2: inst=32'hffffffff; // unsupported
        3: inst=32'h06483800; // ERTN
        4: inst=jump(6'h14,8); // incoming IF ADEF
      endcase
      issue(inst,mode==4?pc+3:pc,32'hbad00000,2'b11,
        mode==4?{1'b1,6'h08,9'b0,1'b1,pc+32'd3}:49'b0);
      ck(mode==3 ? meta[34]===1 : meta[83]===1,"exception/ERTN decoded");
      finish_case(0,0,0,0,pc,0,0,0);
    end
    // Interrupt overrides branch, drains older instruction, then takes exception.
    has_int=1; older=1;
    issue(jump(6'h14,8),pc,pc+4,0,0); allow=1;
    #1; ck(dv===0 && meta[83]===1,"INT must wait for older instruction"); quiet(3);
    older=0; finish_case(0,0,0,0,pc,0,0,0); has_int=0;
    // Interrupt on CSRWR/ERTN must discard the original special task too.
    for(mode=0;mode<2;mode=mode+1) begin
      has_int=1;
      issue(mode==0?32'h0400c025:32'h06483800,pc,32'hbad00000,2'b11,0);
      ck(meta[83]===1 && meta[82:77]===0 && meta[163:84]===0 && meta[34:0]===0,
        "INT must cancel original CSR/ERTN task and all prediction events");
      finish_case(0,0,0,0,pc,0,0,0); has_int=0;
    end
    // Interrupt may disappear before acceptance: original branch then executes.
    issue(jump(6'h14,8),pc,pc+4,0,0);
    has_int=1; quiet(2); has_int=0;
    finish_case(1,1,0,1,pc,target,1,target);

    // CSR remains serialized; normal nonbranch update only on actual transfer.
    older=1; issue(32'h0400c025,pc,pc+4,0,0); allow=1;
    #1; ck(dv===0,"CSR must drain older instructions"); quiet(2);
    older=0; finish_case(1,0,0,0,pc,0,0,pc+4);

    // WB flush wins even on the exact cycle ID could otherwise correct.
    issue(jump(6'h14,8),pc,pc+4,0,0);
    allow=1; flush=1; #1;
    ck(dv===0,"WB flush must suppress ID transfer"); quiet(2);
    flush=0; quiet(2); allow=0; cases=cases+1;

    // Reset also suppresses a ready correction and clears the valid instruction.
    issue(jump(6'h14,8),pc,pc+4,0,0);
    allow=1; reset=1; quiet(2); reset=0; quiet(2); cases=cases+1;
    $display("PASS exceptions, interrupts, ERTN, CSR, flush and reset");
    ck(cases==89,"suite case count must match coverage manifest");
    $display("BP_ID_PASS cases=%0d checks=%0d updates=%0d redirects=%0d",cases,checks,updates,redirects);
    $finish;
  end
  initial begin #100000; $fatal(1,"BP_ID_TIMEOUT"); end
endmodule
