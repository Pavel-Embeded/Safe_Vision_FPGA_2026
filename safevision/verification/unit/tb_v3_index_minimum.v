`timescale 1ns/1ps


module tb_v3_index_minimum;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,clear=0,commit=0,valid=0;reg[87:0] name=0;
 reg[31:0] cluster=0,size=0;reg[15:0] cursor=0;
 wire done,selected;wire[3:0] count,mask;wire[15:0] key;wire[31:0] fc,sz;
 file_index #(.CURSOR_MODE(1),.CANDIDATE_SLOTS(1)) dut(
 .clk(clk),.rst_n(rst_n),.ent_name(name),.ent_attr(8'h20),
 .ent_first_clus(cluster),.ent_size(size),.ent_index(16'd0),.ent_valid(valid),.ent_ready(),
 .idx_clear(clear),.idx_commit(commit),.idx_done(done),.file_cnt(count),.file_valid(mask),
 .insufficient(),.err_code(),.err_detail(),.cursor_key(cursor),.sel_key(key),
 .sel_slot(2'd0),.sel_first_clus(fc),.sel_size(sz),.sel_valid(selected),
 .sel_wav_first_clus(),.sel_wav_size(),.sel_wav_valid(),.bmp_seen(),.wav_seen());
 integer errors=0,comparisons=0,round,attempt,i,number,expected,cursor_number,legal,guard;
 function[15:0] bcd;input integer n;begin begin bcd=((n/1000)<<12)|(((n/100)%10)<<8)|(((n/10)%10)<<4)|(n%10);end  end endfunction
 function[87:0] filename;input integer n;reg[7:0] a,b,c,d;begin begin
  a=48+n/1000;b=48+(n/100)%10;c=48+(n/10)%10;d=48+n%10;
  filename={16'h5356,a,b,c,d,16'h2020,24'h424d50};end  end endfunction
 task ck;input condition;input[511:0] msg;begin begin comparisons=comparisons+1;
  if(!condition)begin errors=errors+1;$display("[FAIL] %s round=%0d expected=%0d key=%h",msg,round,expected,key);end end  end endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  for(round=0;round<12;round=round+1)begin
   cursor_number=(round==11) ? 9999:round*711;legal=0;attempt=0;
   while(legal<4 && attempt<20)begin
    attempt=attempt+1;cursor=bcd(cursor_number);clear=1;@(negedge clk);clear=0;
    expected=10000;
    for(i=0;i<193;i=i+1)begin
     number=((i*73+round*19)%193)*47+1;
     if(number>cursor_number && number<expected)expected=number;
     name=filename(number);cluster=8000+number;size=921654+(number%10)*32;valid=1;
     @(negedge clk);valid=0;repeat((i+round)%4)@(negedge clk);

     name=filename(number);name[23:0]=24'h574156;valid=1;@(negedge clk);valid=0;
    end
    repeat(4)@(negedge clk);commit=1;@(negedge clk);commit=0;
    guard=0;while(!done && guard<12)begin @(negedge clk);guard=guard+1;end
    ck(done,"finite commit");
    if(expected==10000)begin
     ck(!selected && count==0 && mask==0,"directory exhaustion publishes no phantom candidate");legal=4;
    end else begin
     ck(selected && count==1 && mask==1,"one physical candidate slot");
     ck(key==bcd(expected) && fc==8000+expected && sz==921654+(expected%10)*32,"minimum key and entire 32-bit payload equal reference");
     cursor_number=expected;

     if(expected%7!=0)legal=legal+1;
     repeat(3)@(negedge clk);
     name=filename(1);cluster=1;size=1;valid=1;@(negedge clk);valid=0;
     repeat(4)@(negedge clk);ck(key==bcd(expected)&&fc==8000+expected,"committed candidate frozen against late entries");
    end
   end
   ck(legal==4,"four legal candidates or finite exhausted directory");
  end
  if(errors==0)$display("[PASS] repeated whole-directory minimum selection, rejection cursor, exhaustion and freeze");
  $display("[TB] tb_v3_index_minimum done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #10000000;$display("[FAIL] global timeout");$finish;end
endmodule
