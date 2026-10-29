`timescale 1ns/1ps
module tb_v3_audio_negative_container;
 integer negative_errors=0;
reg clk=0;always #10 clk=~clk;
reg rst_n=0,start=0,iv=0,eof=0;reg[7:0] data=0;reg[31:0] fsize=0;
wire ir,pv,error;wire[31:0] pcm;wire[110:0] saved_context;
reg[31:0] rng=32'h3d07aaee;always@(posedge clk)rng<={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
wire ready=rng[3:0]!=0;
v3_wav_parser_compact_ctx d(.clk(clk),.rst_n(rst_n),.start(start),.context_load(1'b0),.context_in(111'd0),
 .context_out(saved_context),.context_enable(1'b1),.first_clus(32'd2),.file_size(fsize),.track_id(8'd0),
 .din(data),.din_valid(iv),.din_eof(eof),.din_ready(ir),.sample(pcm),.pcm_valid(pv),.pcm_ready(ready),.wav_error(error));
reg[7:0] disk[0:200000];reg[31:0] gold[0:30000],desc[0:2000];
integer case_id=0,begin_byte=0,gold_base=0,expected=0,seen=0,checks=0,errors=0;
reg held=0;reg[31:0] held_pcm;
always@(posedge clk)begin
 if(!rst_n)begin seen<=0;held<=0;end
 else begin
  if(held&&(!pv||pcm!==held_pcm))begin $display("[FAIL] pending PCM changed during backpressure"); $finish; end 
  held<=pv&&!ready;held_pcm<=pcm;
  if(pv&&ready)begin
   if(seen>=expected||pcm!==gold[gold_base+seen])begin negative_errors=negative_errors+1;if(negative_errors<=3)$display("[FAIL AUDIO_CONTAINER_PCM] case=%0d pair=%0d got=%08x",case_id,seen,pcm);end
   seen<=seen+1;checks=checks+1;
  end
 end
end
integer i,base,guard,valid_cases=0,invalid_cases=0;
initial begin
 $readmemh("compact_disk.mem",disk);$readmemh("compact_pcm.mem",gold);$readmemh("compact_desc.mem",desc);
 for(case_id=0;case_id<desc[0];case_id=case_id+1)begin
  base=1+case_id*5;
  @(negedge clk);rst_n=0;iv=0;eof=0;start=0;
  begin_byte=desc[base];fsize=desc[base+1];gold_base=desc[base+2];expected=desc[base+3];
  repeat(4)@(negedge clk);rst_n=1;start=1;
  @(negedge clk);start=0;
  for(i=0;i<fsize&&!error;i=i+1)begin
   if(rng[5:4]==0)begin iv=0;repeat(2)@(negedge clk);end
   data=disk[begin_byte+i];iv=1;eof=i==fsize-1;
   guard=0;while(!ir&&!error&&guard<100)begin @(negedge clk);guard=guard+1;end
   if(!ir&&!error)begin $display("[FAIL] compact parser stalled case=%0d index=%0d",case_id,i); $finish; end 
   if(!error)@(negedge clk);
  end
  iv=0;eof=0;repeat(20)@(negedge clk);
  if(error!==desc[base+4][0]||seen!=expected)begin negative_errors=negative_errors+1;if(negative_errors<=3)$display("[FAIL AUDIO_CONTAINER_END] case=%0d error=%0d want=%0d pairs=%0d want=%0d",case_id,error,desc[base+4],seen,expected);end
  if(!error&&d.state!=d.W_END)begin $display("[FAIL] valid RIFF not fully drained"); $finish; end 
  if(error)invalid_cases=invalid_cases+1;else valid_cases=valid_cases+1;
  checks=checks+1;
 end
 $display("[PASS] independent struct/wave oracle, extension/padding, chunks after data, physical trailing, overflow/invalid/truncation, random backpressure");
 $display("PASS tb_v3_audio_negative_container errors=%0d comparisons=%0d valid=%0d invalid=%0d",negative_errors,checks,valid_cases,invalid_cases);$finish;
end
initial begin #30000000;begin $display("[FAIL] compact oracle watchdog"); $finish; end end
endmodule
