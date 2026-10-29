`timescale 1ns/1ps
module tb_v3_wav_pipe724;
 reg clk=0,rst=0,start=0,load=0,enable=0,dv=0,eof=0,ready=0;
 always #5 clk=~clk;
 reg[110:0] ctx=0;reg[31:0] size=0;reg[7:0] din=0;
 reg[33:0] bound_in=0;wire[33:0] bound_out;
 wire[110:0] ac,bc;wire[31:0] asample,bsample;wire ar,br,av,bv,ae,be;
 v3_wav_parser_compact_ctx #(.PIPELINED_BOUNDS(1)) dut(.bound_context_in(bound_in),.bound_context_out(bound_out),.clk(clk),.rst_n(rst),.start(start),.context_load(load),.context_enable(enable),.context_in(ctx),.context_out(ac),.first_clus(32'd2),.file_size(size),.track_id(8'd0),.din(din),.din_valid(dv),.din_eof(eof),.din_ready(ar),.sample(asample),.pcm_valid(av),.pcm_ready(ready),.wav_error(ae));
 v3_wav_bounds_reference reference(.clk(clk),.rst_n(rst),.start(start),.context_load(load),.context_enable(enable),.context_in(ctx),.context_out(bc),.first_clus(32'd2),.file_size(size),.track_id(8'd0),.din(din),.din_valid(dv),.din_eof(eof),.din_ready(br),.sample(bsample),.pcm_valid(bv),.pcm_ready(ready),.wav_error(be));
 integer comparisons=0,errors=0,k;reg[31:0] r=32'h753c4ab1,t=32'h18397455,u=32'h19a92371,a,l;
 reg[63:0] assembled64,limit64;reg want_pad,want_size,want_overflow;


 function[33:0] consistent_bound(input[110:0] f,input[31:0] file_bytes);
  reg[31:0] lim,w;reg[63:0] sum,mask;reg carry,gt;integer st,idx,n;
  begin
   st=f[108:105];idx=f[104:101];w=f[100:69];
   lim=32'h13579bdf;carry=1;gt=0;
   if((st==1||st==2)&&idx>=5&&idx<=7)begin
    n=(idx-4)*8;
    lim=st==1?file_bytes-32'd8:f[68:37]-(8-idx);
    sum={32'd0,w}>>(32-n);mask=(64'd1<<n)-1;
    if(st==2&&sum[0])sum=sum+64'd1;
    carry=(sum>>n)!=0;gt=(sum&mask)>({32'd0,lim}&mask);
   end
   consistent_bound={lim,carry,gt};
  end
 endfunction
 task check(input bit ok,input string message);begin
  comparisons++;if(!ok)begin errors++;if(errors<9)$display("[FAIL] %s k=%0d ctx=%h size=%h din=%h",message,k,ctx,size,din);end
 end endtask
 task compare;begin check({ac,ar,asample,av,ae}==={bc,br,bsample,bv,be},"exact context,ready,PCM,error same edge");end endtask
 reg[31:0] directed_a,directed_limit;integer ai,li,jj;
 task exercise_size(input[31:0] value,input[31:0] payload_limit);begin
  @(negedge clk);load=1;enable=0;start=0;dv=0;eof=0;ready=0;size=0;
  ctx={1'b0,1'b0,4'd2,4'd4,32'h4b4e554a,payload_limit+32'd4,32'd0,2'd0,1'b0,1'b1,1'b1};
  bound_in=consistent_bound(ctx,size);
  @(posedge clk);#1;compare();
  for(jj=0;jj<4;jj++)begin
   @(negedge clk);load=0;enable=1;dv=1;din=value[jj*8+:8];
   #1;compare();@(posedge clk);#1;compare();

   if(jj==1)begin @(negedge clk);enable=0;dv=0;@(posedge clk);#1;compare();end
  end
 end endtask
 initial begin
  #2;compare();#11;rst=1;
  for(ai=0;ai<14;ai++)begin
   case(ai)
    0:directed_a=32'hff;1:directed_a=32'hffff;2:directed_a=32'hffffff;
    3:directed_a=32'h100;4:directed_a=32'h10000;5:directed_a=32'h1000000;
    6:directed_a=0;7:directed_a=1;8:directed_a=15;9:directed_a=16;
    10:directed_a=17;11:directed_a=32'hfffe;12:directed_a=32'hfffffe;default:directed_a=32'h123456;
   endcase
   for(li=0;li<5;li++)begin
    directed_limit=directed_a+li-2;
    if(directed_limit<32'hfffffffb)exercise_size(directed_a,directed_limit);
   end
  end
  for(k=0;k<200000;k++)begin
   r=r*1664525+1013904223;t=t*22695477+1;u=u*1103515245+12345;
   a=r;l=t;
   if(k<65536)begin
    case(k%8)
     0:a={r[31:16],16'hffff};1:a=32'hffffffff;
     2:a=32'hfffffff7;3:a=32'hfffffff8;
     4:a=0;5:a=1;6:a=15;7:a=16;
    endcase
    l=a+(k%17)-8;
   end
   @(negedge clk);load=1;enable=0;start=0;dv=0;eof=0;ready=0;
   size=k%4==0?a+7:(k%4==1?a+8:(k%4==2?a+9:t));din=a[31:24];


   case(k%4)
    0:ctx={1'b0,1'b0,4'd2,4'd7,{a[23:0],8'd0},l,u,2'd2,1'b0,1'b1,1'b1};
    1:ctx={1'b0,1'b0,4'd1,4'd7,{a[23:0],8'd0},l,u,2'd0,1'b0,1'b0,1'b0};
    2:ctx={1'b0,1'b0,4'd2,4'd7,{a[23:0],8'd0},l,u,r[1:0],r[2],r[3],r[4]};
    3:ctx={r[14:0],t,u,r};
   endcase
   bound_in=consistent_bound(ctx,size);
   @(posedge clk);#1;compare();
   check(bound_out===bound_in,"atomic34-bit sideband restored with111-bit core context");
   assembled64={32'd0,din,ctx[100:77]};limit64={32'd0,ctx[68:37]};
   want_pad=(assembled64+64'd1+assembled64[0])>limit64;
   want_size=(assembled64+64'd8)>{32'd0,size};
   want_overflow=(assembled64+64'd8)>64'hffffffff;
   check(dut.padded_overrun===want_pad,"independent64-bit padded bound");
   check(dut.riff_oversize===want_size,"independent64-bit file bound");
   check(dut.riff_overflow===want_overflow,"independent64-bit RIFF overflow");
   @(negedge clk);load=0;enable=1;dv=1;eof=u[0];ready=u[1];start=(k%37==36);
   #1;compare();@(posedge clk);#1;compare();
   @(negedge clk);enable=u[2];dv=u[3];ready=u[4];start=0;
   #1;compare();@(posedge clk);#1;compare();
   if(k%1023==1022)begin #1;rst=0;#1;compare();#1;rst=1;end
  end
  if(errors==0)$display("[PASS] 200000 restored contexts,RIFF/chunk bounds64-bit oracle,odd padding,overflow,eof,backpressure,start,reset,unchanged111-bit context and same-cycle outputs");
  $display("[TB] tb_v3_wav_pipe724 done comparisons=%0d errors=%0d",comparisons,errors);$finish;
 end
 initial begin #10000000;errors++;$display("[FAIL] WAV bounds sweep timeout");$display("[TB] tb_v3_wav_pipe724 done comparisons=%0d errors=%0d",comparisons,errors);$finish;end
endmodule
