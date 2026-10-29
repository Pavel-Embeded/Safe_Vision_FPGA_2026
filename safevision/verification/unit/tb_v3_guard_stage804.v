`timescale 1ns/1ps
module tb_v3_guard_stage804;
 reg clk=0;always #10 clk=~clk;reg rst=0;
 safevision_v3_top #(.HD(0)) dut(.clk(clk),.rst_n(rst),.btn_next(1'b1),.btn_auto(1'b1),.btn_emergency(1'b1),.uart_rxd(1'b1),.sd_miso(1'b1));
 defparam dut.memory_ip.OUTPUT_VALID_DELAY=1;
 defparam dut.uart.g_catalog.parser.CATALOG_FILE="v3_command_catalog.mem";
 defparam dut.video.FONT_FILE="font8x16.mem";
 defparam dut.video.COMPACT_FONT_FILE="font8x16_compact.mem";
 defparam dut.video.STATUS_TEXT_FILE="v3_handbook_status_text.mem";
 reg tbegin=0,taccept=0,tverify=0,trvalid=0,ttop=1;reg[1:0] tslot=0;
 reg[31:0] taddr=0,tdata=0,trdata=0;
 reg qbegin=0,qaccept=0,qverify=0,qrvalid=0,qtop=0;reg[1:0] qslot=0;reg[31:0] qaddr=0,qdata=0,qrdata=0;
 reg model_build=0,model_fault=0;integer words=0;reg[31:0] model_crc=32'hffffffff,signature=0,bad_address=0;
 integer errors=0,comparisons=0,k;reg check_signature=0;
 task check(input  ok,input [4095:0] msg);begin begin ok = (ok === 1'b1); comparisons = comparisons + 1;if(!ok)begin errors = errors + 1;if(errors<10)$display("[FAIL] %s",msg);end end  end endtask
 function[31:0] crc_word(input[31:0] old,input[31:0] data);reg[31:0] c;integer n;begin begin c=old^data;for(n=0;n<32;n = n + 1)c=c[0] ? (c>>1)^32'hedb88320:c>>1;crc_word=c;end  end endfunction
 always @(negedge dut.mem_media_rst_n)begin qbegin=0;qaccept=0;qverify=0;qrvalid=0;model_build=0;model_fault=0;words=0;model_crc=32'hffffffff;check_signature=0;end
 always @(posedge dut.mem_clk)begin
  if(dut.mem_media_rst_n)begin
   if(qbegin&&!model_fault)begin model_build=1;words=0;model_crc=32'hffffffff;end
   else if(qaccept&&model_build&&!model_fault)begin
    if(qaddr!=words*4)begin model_fault=1;model_build=0;bad_address=qaddr;end
    else begin
     model_crc=crc_word(model_crc,qdata);words = words + 1;
     if(words%320==0)begin signature=~model_crc;model_crc=32'hffffffff;check_signature=1;end
    end
   end
   qbegin=tbegin;qaccept=taccept;qverify=tverify;qrvalid=trvalid;qslot=tslot;qtop=ttop;qaddr=taddr;qdata=tdata;qrdata=trdata;
   #1;
   check({dut.guard_begin_q,dut.guard_accept_q,dut.guard_verify_q,dut.guard_valid_q}==={qbegin,qaccept,qverify,qrvalid},"all valid/frame/verify controls share one MEM edge");
   check({dut.guard_slot_q,dut.guard_top_q,dut.guard_write_addr_q,dut.guard_write_data_q,dut.guard_read_data_q}==={qslot,qtop,qaddr,qdata,qrdata},"all source metadata/write/read payloads retain the exact sampled token");
   check(dut.row_guard.source_words===words && dut.row_guard.fault===model_fault,"independent delayed accepted-word and sticky-fault oracle");
   check(dut.row_guard.source_crc===model_crc,"independent complete CRC32 word oracle");
   if(check_signature)check(dut.row_guard.signatures[0]===signature,"complete320-word row signature published without a lost final beat");
   if(model_fault)check(dut.row_guard.bad_addr===bad_address && dut.row_guard.bad_actual===bad_address,"invalid-address diagnostic retains the delayed failing word");
  end
 end
 initial begin
  force dut.source_begin=tbegin;force dut.source_slot=tslot;force dut.source_top_down=ttop;
  force dut.writer_accepted=taccept;force dut.mem_addr=taddr;force dut.mem_wdata=tdata;
  force dut.verify_start=tverify;force dut.verify_valid=trvalid;force dut.verify_data=trdata;
  repeat(10)@(negedge clk);rst=1;wait(dut.mem_media_rst_n);repeat(4)@(negedge dut.mem_clk);
  tbegin=1;@(negedge dut.mem_clk);tbegin=0;
  for(k=0;k<320;k = k + 1)begin
   taccept=1;taddr=k*4;tdata=32'h1d872b43^(k*32'h009b371d);trvalid=k[0];trdata=~tdata;
   @(negedge dut.mem_clk);taccept=0;if(k%3==0)@(negedge dut.mem_clk);
  end
  repeat(4)@(negedge dut.mem_clk);
  check(words==320 && !model_fault,"one full source row completed before fault injection");
  taccept=1;taddr=32'h12345678;tdata=32'h87654321;@(negedge dut.mem_clk);taccept=0;
  repeat(5)@(negedge dut.mem_clk);check(model_fault && words==320,"one bad accepted address detected after the same observation delay");
  rst=0;#1;check({dut.guard_begin_q,dut.guard_accept_q,dut.guard_verify_q,dut.guard_valid_q}===4'b0,"global reset immediately invalidates all pipeline controls");
  repeat(6)@(negedge clk);rst=1;wait(dut.mem_media_rst_n);repeat(5)@(negedge dut.mem_clk);check(dut.row_guard.source_words==0 && !dut.row_guard.fault,"fresh epoch cannot replay a pre-reset token");
  if(errors==0)$display("[PASS] board observer atomic tokens,complete row CRC,invalid address and asynchronous reset epoch");
  $display("[TB] tb_v3_guard_stage804 done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #1000000;$display("[FAIL] guard stage watchdog errors=1");$display("[TB] tb_v3_guard_stage804 done errors=1 comparisons=0");$finish;end
endmodule
