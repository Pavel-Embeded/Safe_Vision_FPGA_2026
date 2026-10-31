`timescale 1ns/1ps
module tb_v3_boot_pipeline171;
 reg clk=0,rst=0,start=0,ready=1,valid=0,last=0,done=0,toerr=0,crcerr=0;
 always #5 clk=~clk;
 reg[7:0] data=0,ec=8'h35,ed=8'h77;reg[7:0]sector[0:511];
 reg[31:0]seed=32'h171ac389;integer errors=0,comparisons=0,k,n,q,j,waits;
 wire[295:0]a,b;
fat32_boot_parser dut(.clk(clk),.rst_n(rst),.start(start),.sd_rd_ready(ready),.sd_data(data),.sd_data_valid(valid),.sd_data_last(last),.sd_rd_done(done),.sd_timeout_err(toerr),.sd_crc16_err(crcerr),.sd_err_code(ec),.sd_err_detail(ed),.mount_done(a[0:0]),.mount_error(a[1:1]),.err_code(a[9:2]),.err_detail(a[17:10]),.dbg_state(a[21:18]),.bytes_per_sec(a[37:22]),.sec_per_clus(a[45:38]),.num_fats(a[53:46]),.fat_start_lba(a[85:54]),.root_clus(a[117:86]),.root_dir_lba(a[149:118]),.data_start_lba(a[181:150]),.total_sec(a[213:182]),.total_clus(a[245:214]),.sd_rd_addr(a[277:246]),.sd_rd_len(a[293:278]),.sd_rd_en(a[294:294]),.sd_data_ready(a[295:295]));
v3_boot_reference171 original(.clk(clk),.rst_n(rst),.start(start),.sd_rd_ready(ready),.sd_data(data),.sd_data_valid(valid),.sd_data_last(last),.sd_rd_done(done),.sd_timeout_err(toerr),.sd_crc16_err(crcerr),.sd_err_code(ec),.sd_err_detail(ed),.mount_done(b[0:0]),.mount_error(b[1:1]),.err_code(b[9:2]),.err_detail(b[17:10]),.dbg_state(b[21:18]),.bytes_per_sec(b[37:22]),.sec_per_clus(b[45:38]),.num_fats(b[53:46]),.fat_start_lba(b[85:54]),.root_clus(b[117:86]),.root_dir_lba(b[149:118]),.data_start_lba(b[181:150]),.total_sec(b[213:182]),.total_clus(b[245:214]),.sd_rd_addr(b[277:246]),.sd_rd_len(b[293:278]),.sd_rd_en(b[294:294]),.sd_data_ready(b[295:295]));

 always@(posedge clk)begin #0.01;comparisons = comparisons + 1;
  if(a!==b)begin errors = errors + 1;if(errors<8)$display("[FAIL] boot public edge mismatch sector=%0d byte=%0d a=%h b=%h",k,n,a,b);end
 end
 task word(input integer off,input[31:0] v);begin  for(j=0;j<4;j = j + 1)sector[off+j]=v>>(j*8);  end endtask
 initial begin
 repeat(4)@(negedge clk);rst=1;
 for(k=0;k<2048;k = k + 1)begin
  for(n=0;n<512;n = n + 1)begin seed=seed*1664525+1013904223;sector[n]=seed[7:0];end
  sector[11]=0;sector[12]=2;sector[13]=1<<(k%8);sector[14]=seed[7:0];sector[15]=seed[15:8];
  sector[16]=k[0] ? 1:2;sector[17]=0;sector[18]=0;sector[19]=0;sector[20]=0;sector[22]=0;sector[23]=0;
  seed=seed*1664525+1013904223;word(32,seed);seed=seed*1664525+1013904223;word(36,seed|1);
  seed=seed*1664525+1013904223;word(44,seed|2);sector[510]=8'h55;sector[511]=8'haa;
  case(k%16)
  1:sector[510]=0;2:sector[511]=0;3:sector[12]=4;4:sector[17]=1;
  5:sector[22]=1;6:sector[19]=1;7:word(36,0);8:sector[13]=3;
  9:sector[13]=0;10:sector[16]=3;11:word(44,1);12:begin word(36,32'hffffffff);word(44,32'hffffffff);end
  13:begin word(32,0);word(44,2);sector[13]=128;end
  default:;
  endcase
  @(negedge clk);start=1;@(negedge clk);start=0;
  waits=0;while(!dut.sd_rd_en&&waits<12)begin @(negedge clk);waits = waits + 1;end
  if(!dut.sd_rd_en)begin errors = errors + 1;$display("[FAIL] missing request");end
  @(negedge clk);
  for(n=0;n<512;n = n + 1)begin
   valid=1;data=sector[n];last=n==511;
   @(negedge clk);valid=0;last=0;
   if(n%19==k%19)repeat(k%3+1)@(negedge clk);
  end
  if(k%32==31)begin toerr=1;crcerr=k[5];end
  repeat(6)@(negedge clk);toerr=0;crcerr=0;
  if(k%23==0)begin #2;rst=0;#1;rst=1;repeat(3)@(negedge clk);end
 end

 for(k=0;k<512;k = k + 1)begin
  #2;rst=0;#1;rst=1;repeat(3)@(negedge clk);start=1;@(negedge clk);start=0;
  repeat(3)@(negedge clk);
  for(n=0;n<=k;n = n + 1)begin data=sector[n];valid=1;@(negedge clk);end
  valid=0;#2;rst=0;#1;rst=1;repeat(4)@(negedge clk);
 end
 if(errors==0)$display("[PASS] original parser all public pins/cycles;2048random BPBs,error priorities,overflow,backpressure,remounts and512reset-abort positions");
 $display("PASS tb_v3_boot_pipeline171 comparisons=%0d errors=%0d",comparisons,errors);$finish;
 end
 initial begin #20000000;$display("[FAIL] boot miter watchdog errors=1");$finish;end
endmodule
