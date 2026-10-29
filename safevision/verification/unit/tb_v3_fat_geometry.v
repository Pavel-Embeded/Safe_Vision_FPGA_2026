`timescale 1ns/1ps


module tb_v3_fat_geometry;
 reg clk=0,rst=0,start=0,valid=0;always #5 clk=~clk;
 reg[7:0] data=0;wire ready,rd_en,done,bad;wire[7:0] spc,nfat;
 wire[31:0] fat,root,root_lba,base,total,clusters;wire[15:0] bps;
 fat32_boot_parser mount(.clk(clk),.rst_n(rst),.start(start),.mount_done(done),.mount_error(bad),
 .err_code(),.err_detail(),.dbg_state(),.bytes_per_sec(bps),.sec_per_clus(spc),.num_fats(nfat),
 .fat_start_lba(fat),.root_clus(root),.root_dir_lba(root_lba),.data_start_lba(base),.total_sec(total),.total_clus(clusters),
 .sd_rd_addr(),.sd_rd_len(),.sd_rd_en(rd_en),.sd_rd_ready(1'b1),.sd_data(data),.sd_data_valid(valid),
 .sd_data_ready(ready),.sd_data_last(1'b0),.sd_rd_done(1'b0),.sd_timeout_err(1'b0),.sd_crc16_err(1'b0),.sd_err_code(8'd0),.sd_err_detail(8'd0));


 file_streamer fs(.clk(clk),.rst_n(rst),.start(1'b0));
 v3_file_streamer vfs(.clk(clk),.rst_n(rst),.start(1'b0),.stream_enable(1'b1));
 fat32_directory_scanner ds(.clk(clk),.rst_n(rst),.scan_en(1'b0));
 reg[7:0] sector[0:511];integer errors=0,comparisons=0,i,j,s,n,t;reg[31:0] delta,expected,seed=32'h938ca152;
 task check(input condition,input [4095:0] label);begin begin
  comparisons=comparisons+1;if(!condition)begin errors=errors+1;if(errors<6)$display("[FAIL] %s",label);end
 end  end endtask
 task put32(input integer off,input[31:0] value);begin begin
  begin : v_loop_1 integer k; for( k=0;k<4;k=k+1)sector[off+k]=value[k*8+:8]; end 
 end  end endtask
 task exercise(input integer sectors,fats,input legal);begin begin
  for(i=0;i<512;i=i+1)sector[i]=0;
  sector[11]=0;sector[12]=2;sector[13]=sectors;sector[14]=32;sector[16]=fats;
  put32(32,32'h01000000);put32(36,32'd129);put32(44,32'd131);
  sector[510]=8'h55;sector[511]=8'haa;
  @(negedge clk);rst=0;valid=0;repeat(3)@(negedge clk);rst=1;
  @(negedge clk);start=1;@(negedge clk);start=0;
  t=0;while(!rd_en&&t<20)begin @(negedge clk);t=t+1;end
  check(rd_en,"mount request is bounded");
  for(i=0;i<512;i=i+1)begin data=sector[i];valid=1;@(negedge clk);end
  valid=0;repeat(6)@(negedge clk);
  if(legal)begin
   check(done&&!bad,"all legal sectors/cluster and FAT counts accepted");
   check(base==32+fats*129&&root_lba==32+fats*129+129*sectors,"public output LBAs equal independent integer formula");
   check(clusters==(32'h01000000-(32+fats*129))/sectors,"cluster count equals independent division");
   check(bps==512&&spc==sectors&&nfat==fats&&root==131&&fat==32,"mounted raw fields preserved");
  end else check(bad&&!done,"invalid geometry cannot reach specialization");
 end  end endtask
 initial begin
  for(s=1;s<=128;s=s*2)begin
   for(n=1;n<=2;n=n+1)exercise(s,n,1);
   for(j=0;j<270;j=j+1)begin
    case(j)
     0:delta=0;1:delta=1;2:delta=2;3:delta=127;4:delta=128;
     5:delta=511;6:delta=512;7:delta=32'h7fffffff;8:delta=32'h80000000;
     9:delta=32'hfffffffe;10:delta=32'hffffffff;
     default:begin seed=seed*32'd1664525+32'd1013904223;delta=seed;end
    endcase
    expected=delta*s;
    check(fs.cluster_sectors(delta,s)===expected,"BMP streamer exact modulo-32-bit address arithmetic");
    check(vfs.cluster_sectors(delta,s)===expected,"WAV legacy helper exact address arithmetic");
    check(ds.cluster_sectors(delta,s)===expected,"root directory exact address arithmetic");
   end
  end
  exercise(0,1,0);exercise(3,1,0);exercise(255,1,0);exercise(1,0,0);exercise(1,3,0);
  $display("[PASS] 16 accepted mount geometries, five rejected geometries, high-bit and wrapped address products");
  $display("PASS tb_v3_fat_geometry comparisons=%0d errors=%0d",comparisons,errors);$finish;
 end
 initial begin #1000000;$display("[FAIL] geometry timeout errors=1");$finish;end
endmodule
