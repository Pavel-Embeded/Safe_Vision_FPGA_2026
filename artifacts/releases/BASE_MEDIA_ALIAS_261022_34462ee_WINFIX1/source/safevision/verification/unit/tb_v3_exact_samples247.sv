`timescale 1ns/1ps
module exact_sample_case247 #(parameter CASE_ID=0)(output reg done=0,output integer errors=0,comparisons=0);
 reg clk=0,rst=0,start=0,valid=0,wr_ready=0;always #5 clk=~clk;reg[15:0]din=0;
 wire ar,br,aq,bq,ad,bd,ac,bc,ae,be;wire[31:0]aa,ba,aw,bw;wire[15:0]al,bl,av,bv;
 wire[3:0]aslot,bslot;wire[18:0]ap,bp;wire[7:0]aec,bed,aed,bec;
 frame_writer #(.FRAME_WIDTH(4),.FRAME_HEIGHT(4),.PIX_PER_FRAME(16),.SAMPLE_STRIDE(1),.GAP_TIMEOUT(1000),.EXACT_SAMPLE_COMPARE(1)) dut(
 .clk(clk),.rst_n(rst),.start(start),.slot_sel(2'd0),.slot_base(32'd0),.din(din),.din_valid(valid),.din_ready(ar),.wr_req(aq),.wr_addr(aa),.wr_data(aw),.wr_len(al),.wr_ready(wr_ready),.wr_done(ad),.slot_valid(aslot),.crc_ok(ac),.crc_value(av),.px_cnt(ap),.wr_error(ae),.err_code(aec),.err_detail(aed));
 frame_writer #(.FRAME_WIDTH(4),.FRAME_HEIGHT(4),.PIX_PER_FRAME(16),.SAMPLE_STRIDE(1),.GAP_TIMEOUT(1000),.EXACT_SAMPLE_COMPARE(0)) legacy(
 .clk(clk),.rst_n(rst),.start(start),.slot_sel(2'd0),.slot_base(32'd0),.din(din),.din_valid(valid),.din_ready(br),.wr_req(bq),.wr_addr(ba),.wr_data(bw),.wr_len(bl),.wr_ready(wr_ready),.wr_done(bd),.slot_valid(bslot),.crc_ok(bc),.crc_value(bv),.px_cnt(bp),.wr_error(be),.err_code(bec),.err_detail(bed));
 integer cycles=0,sent=0;reg first=0,released=0;reg[31:0]corrupted;
 always@(negedge clk)begin
  cycles++;
  if(rst)begin
   if(aq&&!first)begin
    first=1;wr_ready=1;
    if(CASE_ID!=0)begin
     corrupted=aw^(CASE_ID==1?32'd1:32'h00011021);
     force dut.wr_data_r=corrupted;force legacy.wr_data_r=corrupted;
    end
   end else if(first&&!released)begin
    released=1;release dut.wr_data_r;release legacy.wr_data_r;
    wr_ready=cycles%7!=3;
   end else if(first)wr_ready=cycles%7!=3;
  end
 end
 always@(posedge clk)begin #1;if(rst&&!done)begin
  comparisons++;
  if({ar,aq,aa,aw,al,ap}!=={br,bq,ba,bw,bl,bp})begin errors++;if(errors<6)$display("[FAIL] exact sample stream/edge differs case=%0d",CASE_ID);end
  if(CASE_ID!=2&&{ad,aslot,ac,av,ae,aec,aed}!=={bd,bslot,bc,bv,be,bec,bed})begin errors++;if(errors<6)$display("[FAIL] normal/single-bit public metadata differs case=%0d",CASE_ID);end
 end end
 initial begin
  #100;@(negedge clk);rst=1;start=1;@(negedge clk);start=0;
  while(sent<16)begin
   @(negedge clk);valid=1;din=16'h1234+sent*17;
   do @(posedge clk);while(!ar);sent++;
   @(negedge clk);valid=0;
  end
  wait(ad||ae||bd||be);#2;comparisons++;
  case(CASE_ID)
   0:if(!ad||!bd||!ac||!bc||aslot!=1||bslot!=1)begin errors++;$display("[FAIL] healthy exact sample frame not accepted");end
   1:if(!ae||!be||ac||bc||aslot||bslot||aec!=4||bec!=4)begin errors++;$display("[FAIL] sampled single-bit corruption not rejected");end
   2:begin
    if(!bd||!bc||bslot!=1)begin errors++;$display("[FAIL] known CRC16 collision baseline was not reproduced");end
    if(!ae||ac||aslot||aec!=4||aed!=8'h42)begin errors++;$display("[FAIL] exact comparison accepted different words with equal CRC16");end
   end
  endcase
  if(!errors)$display("[PASS] exact source/bus sampled words:normal and single-bit behavior preserved;CRC16-collision rejection strengthened case=%0d",CASE_ID);
  done=1;
 end
endmodule
module tb_v3_exact_samples247;
 wire a,b,c;wire integer ea,eb,ec,ca,cb,cc;
 exact_sample_case247 #(.CASE_ID(0)) x(a,ea,ca);exact_sample_case247 #(.CASE_ID(1)) y(b,eb,cb);exact_sample_case247 #(.CASE_ID(2)) z(c,ec,cc);
 initial begin wait(a&&b&&c);$display("[TB] tb_v3_exact_samples247 done errors=%0d comparisons=%0d",ea+eb+ec,ca+cb+cc);$finish;end
 initial begin #100000;$display("[FAIL] exact sample watchdog");$display("[TB] tb_v3_exact_samples247 done errors=1 comparisons=0");$finish;end
endmodule
