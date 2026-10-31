`timescale 1ns/1ps
module tb_v3_directory_sv_names;
 reg clk=0,rst=0,start=0;always #5 clk=~clk;
 reg[7:0] sector[0:511],data=0;reg valid=0,rdone=0;reg ent_ready=0;
 wire[1:0] ready,request,done,bad,ev,ws;wire[7:0] code[0:1],detail[0:1],attr[0:1];
 wire[87:0] name[0:1];wire[31:0] first[0:1],size[0:1],address[0:1];wire[15:0] index[0:1];
 reg wd=0;integer pending_walk=0;
 fat32_directory_scanner #(.SV_MEDIA_ONLY(1)) dut(.clk(clk),.rst_n(rst),.scan_en(start),.scan_done(done[0]),.dir_bad(bad[0]),
 .err_code(code[0]),.err_detail(detail[0]),.dbg_state(),.sec_per_clus(8'd1),.root_clus(32'd2),
 .root_dir_lba(32'd8192),.data_start_lba(32'd8192),.ent_name(name[0]),.ent_attr(attr[0]),
 .ent_first_clus(first[0]),.ent_size(size[0]),.ent_index(index[0]),.ent_valid(ev[0]),.ent_ready(ent_ready),
 .sd_rd_addr(address[0]),.sd_rd_len(),.sd_rd_en(request[0]),.sd_rd_ready(1'b1),.sd_data(data),.sd_data_valid(valid),
 .sd_data_ready(ready[0]),.sd_data_last(1'b0),.sd_rd_done(rdone),.sd_timeout_err(1'b0),.sd_crc16_err(1'b0),
 .sd_err_code(8'd0),.sd_err_detail(8'd0),.wk_cur_clus(),.wk_start(ws[0]),.wk_rst_walk(),
 .wk_busy(1'b0),.wk_done(wd),.wk_next_clus(32'd0),.wk_eoc(1'b1),.wk_error(1'b0),.wk_err_code(8'd0),.wk_err_detail(8'd0));
 integer errors=0,comparisons=0,cycle=0,byte_index=0,received=0,expected_count=0;
 integer round,slot,k,off,guard;
 reg sending=0;reg[31:0] random_state=32'h176ac359;reg[175:0] held;reg holding=0;
 reg[87:0] expected_names[0:15];reg[31:0] expected_first[0:15],expected_size[0:15];reg[15:0] expected_indices[0:15];
 task check(input  condition,input [4095:0] message);begin
  condition = (condition === 1'b1); comparisons = comparisons + 1;if(!condition)begin errors = errors + 1;if(errors<6)$display("[FAIL] %s round=%0d byte=%0d",message,round,byte_index);end
   end endtask
 always @(negedge clk)begin
  random_state=random_state*32'd1664525+32'd1013904223;
  ent_ready=cycle%127>=23&&random_state[30];
 end
 always @(posedge clk)begin
  cycle=cycle+1;rdone<=0;wd<=0;
  if(!rst)begin sending<=0;valid<=0;pending_walk<=0;holding<=0;end
  else begin
   if(holding)check(ev[0]&&{name[0],attr[0],first[0],size[0],index[0]}===held,"published entry immutable throughout backpressure");
   holding<=ev[0]&&!ent_ready;held<={name[0],attr[0],first[0],size[0],index[0]};
   if(ev[0]&&ent_ready)begin
    check(received<expected_count,"no extra or deleted directory entry published");
    check(name[0]===expected_names[received],"name bytes equal raw sector order");
    check(attr[0]===8'h20&&first[0]===expected_first[received],"full 32bit cluster little-endian fields preserved");
    check(size[0]===expected_size[received]&&index[0]===expected_indices[received],"size upper byte and skipped-slot index preserved");
    received=received+1;
   end
   if(request[0])begin
    check(address[0]==8192,"both request the same volume-relative root LBA");
    sending<=1;byte_index<=0;data<=sector[0];valid<=1;
   end else if(sending)begin
    if(valid&&ready[0])begin
     if(byte_index==511)begin sending<=0;valid<=0;rdone<=1;end
     else begin byte_index<=byte_index+1;data<=sector[byte_index+1];valid<=cycle%11!=0;end
    end else if(!valid)valid<=1;
   end
   if(ws[0])pending_walk<=3;
   else if(pending_walk!=0)begin pending_walk<=pending_walk-1;if(pending_walk==1)wd<=1;end
  end
 end
 reg[87:0] item_name;reg[31:0] item_first,item_size;reg stopped;reg[7:0] item_attr,first_byte;reg is_media;
 initial begin
  for(round=0;round<1000;round=round+1)begin
   @(negedge clk);rst=0;start=0;repeat(3)@(negedge clk);
   expected_count=0;received=0;stopped=0;
   for(slot=0;slot<16;slot=slot+1)begin
    off=slot*32;for(k=0;k<32;k=k+1)sector[off+k]=v_cast_s8(round*73+slot*11+k);
    item_name={"SV",v_cast_s8(48+round%10),v_cast_s8(48+(round/10)%10),v_cast_s8(48+slot%10),v_cast_s8(48+(round+slot)%10),"  ",slot[0] ? "WAV":"BMP"};
    is_media=1;
    case((round+slot)%11)
     0:begin item_name[87:80]="X";is_media=0;end
     1:begin item_name[79:72]="v";is_media=0;end
     2:begin item_name[71:64]="/";is_media=0;end
     3:begin item_name[63:56]=":";is_media=0;end
     4:begin item_name[55:48]="A";is_media=0;end
     5:begin item_name[47:40]="a";is_media=0;end
     6:begin item_name[39:32]="_";is_media=0;end
     7:begin item_name[31:24]="X";is_media=0;end
     8:begin item_name[23:0]="TXT";is_media=0;end
     default:;
    endcase
    item_first=32'h82ac0137^(round*32'h01000811+slot*32'h01004567);
    item_size=32'haf9e2701^(round*32'h00070103+slot*32'h02014197);
    item_attr=8'h20;first_byte=item_name[87:80];
    if(round%3!=0)case(slot%7)
     0:item_attr=8'h0f;1:item_attr=8'h08;2:item_attr=8'h10;3:first_byte=8'he5;
    endcase
    if(round%4==3&&slot==10)first_byte=0;
    for(k=0;k<11;k=k+1)sector[off+k]=item_name[87-k*8-:8];
    sector[off]=first_byte;sector[off+11]=item_attr;
    sector[off+20]=item_first[23:16];sector[off+21]=item_first[31:24];
    sector[off+26]=item_first[7:0];sector[off+27]=item_first[15:8];
    for(k=0;k<4;k=k+1)sector[off+28+k]=item_size[k*8+:8];
    if(first_byte==0)stopped=1;
    if(is_media&&!stopped&&first_byte!=8'he5&&item_attr==8'h20)begin
     expected_names[expected_count]=item_name;expected_first[expected_count]=item_first;
     expected_size[expected_count]=item_size;expected_indices[expected_count]=slot;expected_count = expected_count + 1;
    end
   end
   rst=1;@(negedge clk);start=1;@(negedge clk);start=0;guard=0;
   while(!done[0]&&guard<5000)begin @(negedge clk);guard = guard + 1;end
   check(done[0]&&!bad[0]&&received==expected_count,"all retained entries finish once after the last ready edge");
  end
  $display("[PASS] 1000 numeric SV BMP/WAV directory scans, exact field/index oracle, invalid-name skipping and random stalls");
  $display("PASS tb_v3_directory_sv_names comparisons=%0d errors=%0d",comparisons,errors);$finish;
 end
 initial begin #100000000;$display("[FAIL] directory compact timeout errors=1");$finish;end

function signed [7:0] v_cast_s8; input signed [7:0] value; begin  v_cast_s8=value;   end endfunction
endmodule
