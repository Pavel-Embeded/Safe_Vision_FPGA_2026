`timescale 1ns/1ps
module tb_v3_walker_assemble_equivalence;
 reg clk=0,rst=0,rst_walk=0,start=0;always #5 clk=~clk;
 reg[31:0]cur=0,fat=33,total=1000;reg ready=1,valid=0,last=0,done=0,toerr=0,crcerr=0;
 reg[7:0]data=0,errcode=8'h35,detail=8'h77;
 wire[160:0]a,b;wire[15:0]la,lb;
 fat32_cluster_walker d(.clk(clk),.rst_n(rst),.rst_walk(rst_walk),.start(start),.cur_clus(cur),.busy(a[0]),.done(a[1]),.next_clus(a[33:2]),.eoc(a[34]),.error(a[35]),.err_code(a[43:36]),.err_detail(a[51:44]),.hop_cnt(a[83:52]),.dbg_state(a[87:84]),.fat_start_lba(fat),.total_clus(total),.sd_rd_addr(a[119:88]),.sd_rd_len(la),.sd_rd_en(a[120]),.sd_rd_ready(ready),.sd_data(data),.sd_data_valid(valid),.sd_data_ready(a[121]),.sd_data_last(last),.sd_rd_done(done),.sd_timeout_err(toerr),.sd_crc16_err(crcerr),.sd_err_code(errcode),.sd_err_detail(detail));
 v3_fat32_walker_reference r(.clk(clk),.rst_n(rst),.rst_walk(rst_walk),.start(start),.cur_clus(cur),.busy(b[0]),.done(b[1]),.next_clus(b[33:2]),.eoc(b[34]),.error(b[35]),.err_code(b[43:36]),.err_detail(b[51:44]),.hop_cnt(b[83:52]),.dbg_state(b[87:84]),.fat_start_lba(fat),.total_clus(total),.sd_rd_addr(b[119:88]),.sd_rd_len(lb),.sd_rd_en(b[120]),.sd_rd_ready(ready),.sd_data(data),.sd_data_valid(valid),.sd_data_ready(b[121]),.sd_data_last(last),.sd_rd_done(done),.sd_timeout_err(toerr),.sd_crc16_err(crcerr),.sd_err_code(errcode),.sd_err_detail(detail));
 integer errors=0,comparisons=0,offset,kind,n,entry_offset,rounds=0;reg[31:0]entry,seed=32'h814762be;
 always @(posedge clk)begin #1;if(rst)begin
  comparisons = comparisons + 1;
  if({a[121:0],la}!=={b[121:0],lb})begin if(errors<8)$display("[FAIL] cycle/output mismatch offset=%0d kind=%0d byte=%0d",offset,kind,n);errors = errors + 1;end
 end end
 initial begin
  repeat(4)@(negedge clk);rst=1;
  for(offset=0;offset<128;offset = offset + 1)for(kind=0;kind<10;kind = kind + 1)begin
   @(negedge clk);rst_walk=1;cur=32'h12340000+offset;fat=33+offset;total=kind==9 ? 32'hffffffff:1000;
   @(negedge clk);rst_walk=0;start=1;@(negedge clk);start=0;
   wait(a[120]);@(negedge clk);entry_offset=offset*4;
   case(kind)
    0:entry=0;1:entry=1;2:entry=2;3:entry=1001;4:entry=1002;
    5:entry=32'h0ffffff7;6:entry=32'h0ffffff8;7:entry=32'hffffffff;
    default:begin seed=seed*1664525+1013904223;entry=seed;end
   endcase
   for(n=0;n<512;n = n + 1)begin
    valid=1;last=n==511;seed=seed*1664525+1013904223;
    data=(n>=entry_offset&&n<entry_offset+4) ? (entry>>(8*(n-entry_offset))):seed[7:0];
    @(negedge clk);valid=0;last=0;if(n%17==0)@(negedge clk);
   end
   repeat(5)@(negedge clk);rounds = rounds + 1;
  end
  if(errors==0)$display("[PASS]128 aligned entries, sector-tail508, end/bad/reserved/range and current-byte assembly cycle equivalent");
  $display("[TB] tb_v3_walker_assemble_equivalence done errors=%0d comparisons=%0d rounds=%0d",errors,comparisons,rounds);$finish;
 end
 initial begin #15000000;$display("[FAIL] bounded miter watchdog errors=1");$finish;end
endmodule
