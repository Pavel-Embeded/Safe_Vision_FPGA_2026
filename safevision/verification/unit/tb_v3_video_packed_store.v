`timescale 1ns/1ps
module v3_packed_store_test #(parameter integer WRITE_PHASE=5)(output reg done);
 initial begin done = 0; end

 reg mem=0,wr=0,pix=0,rst=0;always #10 mem=~mem;always #6.734 pix=~pix;
 initial begin #(WRITE_PHASE);forever #5 wr=~wr;end
 reg valid=0;reg[2:0] bank=0;reg[8:0] column=0;reg[31:0] data=0;
 reg cv=0,prepare=0;reg[9:0] sx=0,sy=0,prepared=0;
 wire row_done,serializer_fault,pixel_fault;
 wire[15:0] a00,a10,a01,a11,b00,b10,b01,b11;
 v3_packed_row_store dut(.mem_clk(mem),.mem_rst_n(rst),.write_clk(wr),.write_rst_n(rst),
  .pixel_clk(pix),.pixel_rst_n(rst),.word_valid(valid),.word_bank(bank),.word_column(column),.word_data(data),
  .row_done(row_done),.serializer_fault(serializer_fault),.coord_valid(cv),.sx(sx),.sy(sy),
  .prepare_valid(prepare),.prepare_sy(prepared),.a00(a00),.a10(a10),.a01(a01),.a11(a11),
  .b00(b00),.b10(b10),.b01(b01),.b11(b11),.pixel_fault(pixel_fault));
 integer errors=0,comparisons=0,completed_rows=0,generation=1,b,c,n;
 function[15:0] pixel_at(input integer stream,row,col);
  begin begin pixel_at=v_cast_s16((generation*25173)^(stream*31973)^(row*9257)^(col*193));end
  end endfunction
 always @(posedge mem)if(rst&&row_done)completed_rows=completed_rows+1;
 task fill;integer old_completed,t;begin begin
  for(b=0;b<8;b=b+1)begin
   old_completed=completed_rows;
   for(c=0;c<320;c=c+1)begin @(negedge mem);valid=1;bank=b;column=c;
    data={pixel_at(b/4,b%4,c*2+1),pixel_at(b/4,b%4,c*2)};end
   @(negedge mem);valid=0;t=0;
   while(completed_rows==old_completed&&t<30)begin @(negedge mem);t=t+1;end
   if(completed_rows!=old_completed+1)begin $display("[FAIL] missing/duplicate stored-row ACK bank=%0d",b);errors=errors+1;end
   if(serializer_fault)begin $display("[FAIL] continuous 32-bit ingress lost related-clock phase");errors=errors+1;end
  end
 end  end endtask
 task line(input integer row,width);integer col,next_col,next_row;reg[127:0] expected,observed;begin begin
  @(negedge pix);cv=0;prepare=1;prepared=row;
  @(negedge pix);prepare=0;repeat(8)@(negedge pix);
  for(col=0;col<width;col=col+1)begin
   sx=(col*640)/width;sy=row;cv=1;
   @(posedge pix);#1;next_col=sx==639 ? 639:sx+1;next_row=row==479 ? 479:row+1;
   expected={pixel_at(0,row%4,sx),pixel_at(0,row%4,next_col),pixel_at(0,next_row%4,sx),pixel_at(0,next_row%4,next_col),
    pixel_at(1,row%4,sx),pixel_at(1,row%4,next_col),pixel_at(1,next_row%4,sx),pixel_at(1,next_row%4,next_col)};
   observed={a00,a10,a01,a11,b00,b10,b01,b11};
   if(observed!==expected||pixel_fault)begin
    if(errors<6)$display("[FAIL] phase=%0d sy=%0d sx=%0d expected=%h actual=%h fault=%b",WRITE_PHASE,row,sx,expected,observed,pixel_fault);
    errors=errors+1;end
   comparisons=comparisons+8;@(negedge pix);
  end
  cv=0;repeat(4)@(negedge pix);
 end  end endtask
 initial begin
  #100;rst=1;fill();
  for(n=0;n<4;n=n+1)begin line(n,640);line(n,960);end
  line(479,960);
  $display("[PASS] continuous two-SYS/one-MEM serialization, 511/512 tile crossings and HD repeats");
  @(negedge pix);prepare=1;prepared=0;@(negedge pix);prepare=0;repeat(8)@(negedge pix);
  cv=1;sx=0;sy=0;@(negedge pix);sx=5;@(negedge pix);
  if(!pixel_fault)begin $display("[FAIL] invalid source jump accepted");errors=errors+1;end
  cv=0;rst=0;repeat(8)@(negedge mem);generation=2;rst=1;fill();line(0,640);line(3,960);line(479,960);
  if(serializer_fault||pixel_fault)begin $display("[FAIL] reset epoch did not recover");errors=errors+1;end
  $display("[PASS] invalid-jump rejection and complete media-epoch rewrite");
  $display("[TB] packed phase=%0d comparisons=%0d errors=%0d",WRITE_PHASE,comparisons,errors);done=1;
 end
 initial begin #2000000;$display("[FAIL] packed store timeout errors=1");$finish;end

function signed [15:0] v_cast_s16; input signed [15:0] value; begin begin v_cast_s16=value; end  end endfunction
endmodule
module tb_v3_video_packed_aligned;
 wire done;v3_packed_store_test #(.WRITE_PHASE(5)) t(done);
 initial begin wait(done);$display("[TB] tb_v3_video_packed_aligned done comparisons=%0d errors=%0d",t.comparisons,t.errors);$finish;end
endmodule
module tb_v3_video_packed_offset;
 wire done;v3_packed_store_test #(.WRITE_PHASE(0)) t(done);
 initial begin wait(done);$display("[TB] tb_v3_video_packed_offset done comparisons=%0d errors=%0d",t.comparisons,t.errors);$finish;end
endmodule
