`timescale 1ns/1ps
module tb_v3_wav_fallback_equivalence55;
 reg clk=0,rst=0;always #5 clk=~clk;
 reg[3:0]st=0,found_in=0;reg[1:0]slot=0;reg seen=0,done=0,capture=0,bad=0,we=0,fe=0;reg[7:0]code=0;
 wire[3:0]a,b;integer expected=0,errors=0,comparisons=0,k,j,mask;reg[31:0]rng=32'h113820;reg[15:0]coverage=0;
 v3_wav_source #(.EXTERNAL_SERVICE(1)) d(.clk(clk),.rst_n(rst),.mounted(1'b0),.cache_ready(1'b0),.cache_keys(64'd0),.sec_per_clus(8'd1),.fat_start_lba(32'd1),.data_start_lba(32'd16),.root_dir_lba(32'd16),.root_clus(32'd2),.total_clus(32'd120),.slot_fill(4'd0),.sector_room(4'd0),.pcm_ready(4'd0),.rd_ready(1'b0),.data(8'd0),.data_valid(1'b0),.data_last(1'b0),.rd_done(1'b0),.timeout_err(1'b0),.crc16_err(1'b0),.err_code(8'd0),.err_detail(8'd0),.external_service_ready(1'b0),.core_rsp(837'd0),.fallback(a));
 v3_wav_fallback_reference55 #(.EXTERNAL_SERVICE(1)) reference(.clk(clk),.rst_n(rst),.mounted(1'b0),.cache_ready(1'b0),.cache_keys(64'd0),.sec_per_clus(8'd1),.fat_start_lba(32'd1),.data_start_lba(32'd16),.root_dir_lba(32'd16),.root_clus(32'd2),.total_clus(32'd120),.slot_fill(4'd0),.sector_room(4'd0),.pcm_ready(4'd0),.rd_ready(1'b0),.data(8'd0),.data_valid(1'b0),.data_last(1'b0),.rd_done(1'b0),.timeout_err(1'b0),.crc16_err(1'b0),.err_code(8'd0),.err_detail(8'd0),.external_service_ready(1'b0),.core_rsp(837'd0),.fallback(b));
 initial begin
  force d.state=st;force reference.state=st;force d.active=slot;force reference.active=slot;
  force d.found=found_in;force reference.found=found_in;force d.scan_seen=seen;force reference.scan_seen=seen;
  force d.scan_done=done;force reference.scan_done=done;force d.descriptor_pending=4'd0;force reference.descriptor_pending=4'd0;
  force d.descriptor_capture=capture;force reference.descriptor_capture=capture;force d.dir_bad=bad;force reference.dir_bad=bad;
  force d.scan_code=code;force reference.scan_code=code;force d.waverr=we;force reference.waverr=we;force d.ferr=fe;force reference.ferr=fe;
 end
 always@(posedge clk or negedge rst)begin
  if(!rst)expected=0;
  else if(st==0&&seen&&done&&!capture)expected=bad||code!=0 ? 15:(15^found_in);
  else if(st==4&&(we||fe))expected=expected|(1<<slot);
  #1;comparisons = comparisons + 1;if(a!==b||a!==v_cast_s4(expected))begin errors = errors + 1;if(errors<8)$display("[FAIL] full original plus independent fallback update state=%0d a=%h b=%h expected=%h",st,a,b,v_cast_s4(expected));end
  coverage[a]=1;
 end
 initial begin
  #23;rst=1;
  for(mask=0;mask<16;mask = mask + 1)for(k=0;k<4;k = k + 1)for(j=0;j<4;j = j + 1)begin
   @(negedge clk);st=0;seen=1;done=1;capture=0;bad=0;code=0;found_in=15^mask;
   @(negedge clk);st=4;slot=k;we=j[0];fe=j[1];
  end
  for(k=0;k<100000;k = k + 1)begin
   @(negedge clk);rng=rng*1664525+1013904223;st=rng%12;slot=rng[15:14];found_in=rng[19:16];seen=rng[0];done=rng[1];capture=rng[2];bad=rng[3];code=rng[4] ? 0:rng[15:8];we=rng[6];fe=rng[7];
   if(k%1009==0)begin #1;rst=0;#2;rst=1;end
  end
  @(negedge clk);if(coverage!=16'hffff)begin errors = errors + 1;$display("[FAIL] missing fallback mask coverage");end
  if(errors==0)$display("[PASS] original frozen WAV controller plus independent mask equation,all masks/slots,error combinations,back-to-back commits,100000 random transitions andasync resets");
  $display("[TB] tb_v3_wav_fallback_equivalence55 done errors=%0d comparisons=%0d masks=%h",errors,comparisons,coverage);$finish;
 end

function signed [3:0] v_cast_s4; input signed [3:0] value; begin begin v_cast_s4=value; end  end endfunction
endmodule
