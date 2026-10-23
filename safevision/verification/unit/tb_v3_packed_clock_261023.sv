`timescale 1ns/1ps
// Independent public-data oracle. BASE control SYS is deliberately 50 MHz;
// only the dedicated packed-cache writer runs at 100 MHz. WRONG_WRITE is a
// native negative control, completed by $finish after observing real errors.
module packed_clock_case_261023 #(parameter integer WRONG_WRITE=0,PHASE=0)(
 output reg done=0,output integer errors=0,comparisons=0,detections=0);
 reg mem=0,sys=0,wr=0,pix=0,rst=0;
 always #10 mem=~mem;always #10 sys=~sys;always #19.853 pix=~pix;
 initial begin #(PHASE);forever #(WRONG_WRITE?10:5)wr=~wr;end
 reg valid=0,coord=0,prepare=0;reg[2:0] bank=0;
 reg[8:0] column=0;reg[31:0] data=0;reg[9:0] sx=0,sy=0,prepared=0;
 wire ack,sf,pf;wire[15:0] a00,a10,a01,a11,b00,b10,b01,b11;
 v3_packed_row_store d(.mem_clk(mem),.mem_rst_n(rst),.write_clk(wr),.write_rst_n(rst),
  .pixel_clk(pix),.pixel_rst_n(rst),.word_valid(valid),.word_bank(bank),
  .word_column(column),.word_data(data),.row_done(ack),.serializer_fault(sf),
  .coord_valid(coord),.sx(sx),.sy(sy),.scale_select(2'd0),
  .prepare_valid(prepare),.prepare_sy(prepared),.a00(a00),.a10(a10),.a01(a01),.a11(a11),
  .b00(b00),.b10(b10),.b01(b01),.b11(b11),.pixel_fault(pf));
 integer epoch=1,acks=0,mem_edges=0,write_edges=0,sys_edges=0,mismatches=0;
 always @(posedge mem)if(rst)begin mem_edges++;if(ack)acks++;end
 always @(posedge wr)if(rst)write_edges++;
 always @(posedge sys)if(rst)sys_edges++;
 function[15:0] p(input integer stream,row,x);
  begin p=16'((epoch*25173)^(stream*31973)^(row*9257)^(x*193));end
 endfunction
 task require(input bit ok,input string message);begin
  comparisons++;if(!ok)begin errors++;$display("[FAIL] phase=%0d bad=%0d %s",PHASE,WRONG_WRITE,message);end
 end endtask
 task fill;integer b,c,old,t;begin
  for(b=0;b<8;b++)begin
   old=acks;
   for(c=0;c<320;c++)begin @(negedge mem);valid=1;bank=b;column=c;
    data={p(b/4,b%4,c*2+1),p(b/4,b%4,c*2)};end
   @(negedge mem);valid=0;t=0;
   while(acks==old&&t<30)begin @(negedge mem);t++;end
   if(!WRONG_WRITE)require(acks==old+1&&!sf,"320 consecutive words produce exactly one complete row ACK");
  end
 end endtask
 task line(input integer row);integer x,nx,nr;reg[127:0] want,got;begin
  @(negedge pix);coord=0;prepare=1;prepared=row;
  @(negedge pix);prepare=0;repeat(8)@(negedge pix);
  for(x=0;x<640;x++)begin
   coord=1;sx=x;sy=row;@(posedge pix);#1;nx=x==639?639:x+1;nr=row==479?479:row+1;
   want={p(0,row%4,x),p(0,row%4,nx),p(0,nr%4,x),p(0,nr%4,nx),
         p(1,row%4,x),p(1,row%4,nx),p(1,nr%4,x),p(1,nr%4,nx)};
   got={a00,a10,a01,a11,b00,b10,b01,b11};comparisons+=8;
   if(got!==want)begin mismatches++;if(!WRONG_WRITE)begin errors++;
    if(errors<5)$display("[FAIL] row=%0d x=%0d want=%h got=%h",row,x,want,got);end end
   @(negedge pix);
  end
  coord=0;repeat(4)@(negedge pix);
 end endtask
 integer n;
 initial begin
  #100;rst=1;fill();for(n=0;n<4;n++)line(n);line(479);
  require(sys_edges>=mem_edges-1&&sys_edges<=mem_edges+1,"BASE SYS50 and MEM50 are both measured, not relabeled SYS100");
  if(WRONG_WRITE)begin
   require(write_edges>=mem_edges-2&&write_edges<=mem_edges+2,"negative control really uses WRITE50/MEM50");
   require(sf===1'b1,"real sticky serializer fault detects the former 1:1 wiring");
   require(mismatches>100,"independent eight-neighbor pixel oracle detects real 1:1 corruption");
   detections=mismatches+(sf?1:0);
   if(!errors)$display("[PASS] intentional WRITE50 miswiring normally rejected detections=%0d",detections);
  end else begin
   require(write_edges>=2*mem_edges-3&&write_edges<=2*mem_edges+3,"positive control really uses WRITE100/MEM50");
   require(!sf&&!pf,"dedicated WRITE100 has no serializer or raster fault");
   // Abort between LOW/HIGH writes; no pending HIGH may leak into the new epoch.
   @(negedge mem);valid=1;bank=7;column=319;data=32'hdeadbeef;
   wait(d.high_pending);#1;require(d.high_pending,"reset injection truly lands while HIGH is pending");
   rst=0;valid=0;coord=0;repeat(8)@(negedge mem);epoch=2;rst=1;
   fill();for(n=0;n<4;n++)line(n);line(479);
   require(!sf&&!pf,"complete global/media epoch reset clears faults and rewrites all old cache pixels");
   if(!errors)$display("[PASS] SYS50 MEM50 WRITE100 phase=%0d full two-stream neighbor data and reset rewrite",PHASE);
  end
  done=1;
 end
 initial begin #5000000;$display("[FAIL] packed clock watchdog errors=1");$finish;end
endmodule
module tb_v3_packed_clock_positive_261023;
 wire d0,d1;wire integer e0,e1,c0,c1,n0,n1;
 packed_clock_case_261023 #(.PHASE(0)) a(d0,e0,c0,n0);
 packed_clock_case_261023 #(.PHASE(5)) b(d1,e1,c1,n1);
 initial begin wait(d0&&d1);$display("[TB] tb_v3_packed_clock_positive_261023 done errors=%0d comparisons=%0d",e0+e1,c0+c1);$finish;end
endmodule
module tb_v3_packed_clock_negative_261023;
 wire d;wire integer e,c,n;
 packed_clock_case_261023 #(.WRONG_WRITE(1)) a(d,e,c,n);
 initial begin wait(d);$display("[TB] tb_v3_packed_clock_negative_261023 done errors=%0d comparisons=%0d detections=%0d",e,c,n);$finish;end
endmodule
