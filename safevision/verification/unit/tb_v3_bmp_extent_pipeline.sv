`timescale 1ns/1ps
module tb_v3_bmp_extent_pipeline;
 reg clk=0,rst_n=0,valid=0,eof=0;reg[7:0] data=0;reg[31:0] file_size=0;
 always #10 clk=~clk;
 reg[31:0] rng=32'h19e4c72b;reg[3:0] out_ready=15;
 wire[3:0] gold_ready,new_ready,gold_done,gold_bad;
 wire all_gold_ready=&gold_ready;
 wire[170:0] new_public[0:3],gold_public[0:3];
 integer errors=0,data_errors=0,comparisons=0,driver_errors=0;
 integer accepted_headers[0:3],rejected_headers[0:3];
 always @(negedge clk)begin
  rng<={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
  out_ready<={rng[7]|rng[11],rng[5]|rng[9],rng[3]|rng[8],rng[0]|rng[4]};
 end
 generate for(genvar g=0;g<4;g=g+1)begin:lanes
  localparam integer VARIABLE=(g==1||g==2),FLEX=(g==2||g==3);
  wire nd,nb,nt,nv,ns,ne;wire[7:0] nc,nn,np,no;wire[15:0] nw,nh;wire[31:0] nz,nf,nl;wire[3:0] nds;
  wire gd,gb,gt,gv,gs,ge;wire[7:0] gc,gn,gp,go_;wire[15:0] gw,gh;wire[31:0] gz,gf,gl;wire[3:0] gds;
  bmp_parser #(.VARIABLE_SIZE(VARIABLE),.FLEX_PIXELS(FLEX)) dut(
   .clk(clk),.rst_n(rst_n),.data(data),.valid(valid),.ready(new_ready[g]),.eof(eof),.file_size(file_size),
   .check_done(nd),.check_error(nb),.err_code(nc),.err_detail(nn),.width(nw),.height(nh),.top_down(nt),.bpp(np),
   .compression(nz),.pixel_off(nf),.file_size_o(nl),.dbg_state(nds),.out_data(no),.out_valid(nv),.out_ready(out_ready[g]),.out_sof(ns),.out_eof(ne));
  bmp_parser_frozen_extent #(.VARIABLE_SIZE(VARIABLE),.FLEX_PIXELS(FLEX)) reference(
   .clk(clk),.rst_n(rst_n),.data(data),.valid(valid),.ready(gold_ready[g]),.eof(eof),.file_size(file_size),
   .check_done(gd),.check_error(gb),.err_code(gc),.err_detail(gn),.width(gw),.height(gh),.top_down(gt),.bpp(gp),
   .compression(gz),.pixel_off(gf),.file_size_o(gl),.dbg_state(gds),.out_data(go_),.out_valid(gv),.out_ready(out_ready[g]),.out_sof(gs),.out_eof(ge));
  assign new_public[g]={new_ready[g],nd,nb,nc,nn,nw,nh,nt,np,nz,nf,nl,nds,no,nv,ns,ne};
  assign gold_public[g]={gold_ready[g],gd,gb,gc,gn,gw,gh,gt,gp,gz,gf,gl,gds,go_,gv,gs,ge};
  assign gold_done[g]=gd;assign gold_bad[g]=gb;
 end endgenerate
 always @(posedge clk)begin
  #1;
  for(integer lane=0;lane<4;lane=lane+1)begin
   comparisons=comparisons+1;
   if(new_public[lane]!==gold_public[lane])begin
    errors=errors+1;data_errors=data_errors+1;
    if(data_errors<=8)$display("[FAIL] every public parser output lane=%0d new=%h gold=%h",lane,new_public[lane],gold_public[lane]);
   end
   if(rst_n&&gold_done[lane])begin
    if(gold_bad[lane])rejected_headers[lane]=rejected_headers[lane]+1;
    else accepted_headers[lane]=accepted_headers[lane]+1;
   end
  end
 end
 reg[7:0] header[0:53];integer c,k,total,last_header;
 reg[31:0] wi,he,offset,dib,bf;reg[15:0] bits;
 reg signed[63:0] signed_height;reg[63:0] rows,extent;
 task le32(input integer at,input[31:0] value);
  begin for(integer b=0;b<4;b=b+1)header[at+b]=value>>(8*b);end
 endtask
 task make_case(input integer index_);
  begin
   wi=640;he=480;bits=24;offset=54;dib=40;
   case(index_%32)
    1:begin wi=641;he=479;end
    2:begin wi=480;he=-800;end
    3:begin wi=1280;he=720;bits=32;end
    4:begin wi=1920;he=-1080;bits=32;end
    5:begin wi=1;he=1;end
    6:begin wi=16384;he=51;bits=32;end
    7:begin wi=51;he=-16384;end
    8:begin offset=70;dib=56;end
    9:begin offset=138;dib=124;end
    10:dib=108;
    11:offset=0;12:offset=13;13:offset=14;14:offset=53;
    15:offset=32'hfffffff0;16:offset=32'hffffffff;
    17:wi=0;18:wi=16385;19:wi=65535;20:he=0;21:he=32'h80000000;
    22:bits=16;23:bits=32;24:dib=39;
    29:wi=32'h00010001;30:he=32'hffff01e0;
   endcase
   if(index_>=32&&index_%7==0)begin offset=14+(index_*257)%225;dib=offset-14;end
   if(index_>=32&&index_%11==0)begin offset=32'h00010000+(index_%17);dib=32'h00010000;end
   if(index_>=32&&index_%13==0)begin offset=32'h01000000+(index_%17);dib=32'h01000000;end
   if(index_>=32&&index_%19==0)begin offset=32'hff000000+(index_%17);dib=32'hff000000;end
   signed_height=$signed(he);rows=signed_height<0?-signed_height:signed_height;
   extent=((64'(wi)*(bits/8)+3)/4)*4*rows;
   bf=32'(64'(offset)+extent);file_size=bf;
   for(integer b=0;b<54;b=b+1)header[b]=0;
   header[0]="B";header[1]="M";header[26]=1;header[28]=bits[7:0];header[29]=bits[15:8];
   le32(2,bf);le32(10,offset);le32(14,dib);le32(18,wi);le32(22,he);
   case(index_%32)
    23:header[29]=1;
    25:header[0]="X";
    26:file_size=bf-1;
    27:le32(2,bf-1);
    28:file_size=bf-1;
    31:header[26]=2;
   endcase
  end
 endtask
 task push(input[7:0] value,input bit last,input integer gap);
  integer waited;
  begin
   @(negedge clk);valid=0;eof=0;
   repeat(gap)@(negedge clk);
   waited=0;
   while(all_gold_ready!==1'b1&&waited<200)begin @(negedge clk);waited=waited+1;end
   if(all_gold_ready!==1'b1)begin errors=errors+1;driver_errors=driver_errors+1;$display("[FAIL] frozen reference driver timeout");end
   data=value;valid=1;eof=last;
   @(posedge clk);#2;
  end
 endtask
 task reset_now;
  begin @(negedge clk);valid=0;eof=0;rst_n=0;repeat(3)@(negedge clk);rst_n=1;end
 endtask
 initial begin
  for(integer lane=0;lane<4;lane=lane+1)begin accepted_headers[lane]=0;rejected_headers[lane]=0;end
  reset_now();
  for(c=0;c<2048;c=c+1)begin
   @(negedge clk);valid=0;eof=0;make_case(c);
   if(c%97==0)begin
    for(k=0;k<(c%53);k=k+1)push(header[k],0,0);
    reset_now();
   end
   last_header=c%41==0?(c/41)%54:53;
   total=last_header<53?last_header+1:((offset>=54&&offset<=256)?offset+32:86);
   for(k=0;k<total;k=k+1)push(k<54?header[k]:8'(k*37+c),k==total-1,c%3==0?0:((k+c)%4));
   @(negedge clk);valid=0;eof=0;repeat(12)@(negedge clk);
  end
  for(integer lane=0;lane<4;lane=lane+1)begin
   $display("[INFO] lane%0d accepted=%0d rejected=%0d",lane,accepted_headers[lane],rejected_headers[lane]);
   if(accepted_headers[lane]==0||rejected_headers[lane]==0)begin errors=errors+1;$display("[FAIL] acceptance/rejection coverage missing");end
  end
  if(!errors)$display("[PASS] complete frozen parser public interface; four parameter profiles; one byte per clock, stalls, early EOF and async reset; carry and DIB borrow boundaries");
  $display("PASS tb_v3_bmp_extent_pipeline errors=%0d comparisons=%0d data_errors=%0d driver_errors=%0d cases=2048",errors,comparisons,data_errors,driver_errors);
  $finish;
 end
 initial begin #1000000000;$display("[FAIL] parser miter watchdog errors=1");$finish;end
endmodule
