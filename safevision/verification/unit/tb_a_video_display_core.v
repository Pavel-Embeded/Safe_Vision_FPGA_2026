`timescale 1ns/1ps
`include "pixel_format_defs.vh"
module display_case #(parameter HD=0)(output reg done);
 initial begin done = 0; end

 localparam W=HD ? 1280:640,H=HD ? 720:480,HT=HD ? 1650:800,VT=HD ? 750:525;
 localparam OX=HD ? 320:0,OY=HD ? 120:0;
 reg pc=0,mc=0,sc=0,rst=0;
 always #(HD ? 6.734:19.861)pc=~pc;always #4 mc=~mc;always #5 sc=~sc;
 wire [11:0] sx,sy,x,y;wire sde,sfs;wire rr,ra,rb,rv;wire [31:0] raddr,rdata;wire [15:0] rlen;
 wire fsb,ackb,reqb,fi,crc,swap_error,bc;wire [1:0] slot,active_slot;wire [7:0] gen,active_gen;
 wire [31:0] rgb;wire hs,vs,de,pv,ls,fs,afs,hb,vb,active_valid,fault;wire [1:0] layer;
 wire [31:0] uc,miss,ov;wire [15:0] level;wire [2:0] fetch_state;
 reg fr=0;reg [1:0] wrslot=1;reg [7:0] wrgen=8'h11;
 frame_swap_ctrl bswap(.clk(sc),.rst_n(rst),.frame_ready(fr),.wr_frame_index(wrslot[0]),.wr_slot_id(wrslot),.wr_generation(wrgen),.wr_crc_ok(1'b1),.frame_start(fsb),.swap_ack(ackb),.swap_req(reqb),.frame_index(fi),.slot_id(slot),.generation(gen),.crc_ok(crc),.swap_error(swap_error),.active_commit(bc),.active_next(),.generation_next(),.frame_index_next(),.state_o());
 wire ev=sde&&sx>=19&&sx<29&&sy>=21&&sy<24;
 a_video_display_core #(.HD(HD),.FONT_FILE("font8x16.mem")) dut(
 .sys_clk(sc),.mem_clk(mc),.pixel_clk(pc),.rst_n(rst),.swap_req_b(reqb),.mb_frame_index_b(fi),.mb_slot_id_b(slot),.mb_generation_b(gen),.mb_crc_ok_b(crc),.frame_start_evt_b(fsb),.swap_ack_evt_b(ackb),
 .rd_req(rr),.rd_addr(raddr),.rd_len(rlen),.rd_ack(ra),.rd_busy(rb),.rd_data(rdata),.rd_data_valid(rv),
 .cfg_valid(1'b0),.cfg_ready(),.cfg_osd_enable(1'b0),.cfg_mode(2'b0),.cfg_fps_tens(4'd6),.cfg_fps_ones(4'd0),.cfg_sd_ok(1'b1),.cfg_origin_x(12'd0),.cfg_origin_y(12'd0),.cfg_foreground(24'hffffff),
 .emergency_rgb(24'he13579),.emergency_valid(ev),.scan_x(sx),.scan_y(sy),.scan_de(sde),.scan_frame_start(sfs),
 .rgb(rgb[23:0]),.x(x),.y(y),.hsync(hs),.vsync(vs),.de(de),.pixel_valid(pv),.line_start(ls),.frame_start(fs),.active_frame_start(afs),.hblank(hb),.vblank(vb),.selected_layer(layer),
 .pix_active_slot(active_slot),.pix_generation(active_gen),.pix_frame_index(),.pix_active_valid(active_valid),.pix_frame_fault(fault),.pix_underflow_count(uc),.pix_missed_frame_count(miss),.mem_overflow_count(ov),.mem_fifo_pixels(level),.mem_dma_bytes(),.mem_dma_active(),.mem_dma_done(),.mem_fetch_state(fetch_state));
 wire mq,mw,mready;wire [31:0] ma,md;wire [3:0] strb;reg [31:0] response=0;reg response_valid=0;
 wire wr_ack,wr_busy;reg wr_req=0;integer write_beats=0,cycle=0;
 integer frame=0;reg starvation=0;
 assign mready=rst&&!starvation&&(cycle%23!=0);
 memory_arbiter arb(.clk(mc),.rst_n(rst),.video_fifo_level(level),.rd_req(rr),.rd_addr(raddr),.rd_len(rlen),.rd_ack(ra),.rd_busy(rb),.rd_data(rdata),.rd_data_valid(rv),
 .wr_req(wr_req),.wr_addr(32'h800000),.wr_data(32'h76543210),.wr_len(16'd4),.wr_ack(wr_ack),.wr_busy(wr_busy),
 .sd_req(1'b0),.sd_wr(1'b0),.sd_addr(32'd0),.sd_wdata(32'd0),.sd_len(16'd0),.sd_ack(),.sd_busy(),.sd_rdata(),.sd_rdata_valid(),
 .mem_req(mq),.mem_wr(mw),.mem_addr(ma),.mem_wdata(md),.mem_wstrb(strb),.mem_ready(mready),.mem_rdata(response),.mem_rdata_valid(response_valid),.wr_starve_cnt(),.rd_starve_cnt());
 function [15:0] pixel(input [31:0] a);reg [31:0] p;begin  p=(a&32'h9ffff)>>1;pixel=(p*17)^(p>>9)^(a>>16)^16'h4b93;  end endfunction
 function [23:0] expand(input [15:0] p);begin expand={p[15:11],p[15:13],p[10:5],p[10:9],p[4:0],p[4:2]}; end endfunction
 reg [31:0] queued[0:511];integer due[0:511],head=0,tail=0;
 always @(posedge mc)begin
  if(!rst)begin cycle=0;head=0;tail=0;response<=0;response_valid<=0;write_beats=0;end
  else begin
   cycle=cycle+1;response_valid<=0;
   if(head!=tail&&!starvation&&due[head]<=cycle)begin response<=queued[head];response_valid<=1;head=(head+1)%512;end
   if(mq&&mready)begin
    if(mw)write_beats=write_beats+1;
    else begin queued[tail]={pixel(ma+2),pixel(ma)};due[tail]=cycle+3+((ma>>2)%3);tail=(tail+1)%512;if(tail==head)begin $display("[FAIL] memory model overflow"); $finish; end end
   end
  end
 end
 always @(negedge mc)begin
  if(!rst)wr_req=0;
  else if(wr_ack)wr_req=0;
  else if(!wr_busy&&cycle%1024==17)wr_req=1;
 end
 reg [58:0] expected[0:4];reg [58:0] sample;integer i,checks=0,normal_pixels=0,emergency_pixels=0,fault_pixels=0,commits=0;
 reg reference_fault=0,oldfs=0;reg [1:0] lastslot=0;reg [7:0] lastgen=0;integer fault_count=0;reg want_valid;reg [23:0] want_rgb;reg [1:0] want_layer;reg media;integer address;
 always @(posedge pc)begin
  if(!rst)begin
   frame=0;reference_fault=0;lastslot=0;lastgen=0;oldfs=0;fault_count=0;
   for(i=0;i<5;i=i+1)expected[i]=0;
  end else if(dut.prn&&!done)begin
   if(active_slot!=lastslot||active_gen!=lastgen)begin
    if(!oldfs)begin $display("[FAIL] slot changed outside vblank HD=%0d",HD); $finish; end
    if(!((active_slot==1&&active_gen==8'h11)||(active_slot==2&&active_gen==8'h82)))begin $display("[FAIL] torn mailbox HD=%0d",HD); $finish; end
    commits=commits+1;lastslot=active_slot;lastgen=active_gen;
   end
   oldfs=sfs;media=sde&&sx>=OX&&sx<OX+640&&sy>=OY&&sy<OY+480;
   if(media&&active_valid&&!reference_fault&&(!dut.armed||dut.fifo_empty||!dut.fifo_valid))begin
    if(frame!=2)begin $display("[FAIL] unexpected underflow HD=%0d frame=%0d xy=%0d,%0d state=%0d level=%0d",HD,frame,sx,sy,fetch_state,level); $finish; end
    reference_fault=1;fault_count=fault_count+1;
   end
   want_rgb=0;want_valid=sde&&(!media||(active_valid&&!reference_fault));want_layer=want_valid ? 1:0;
   if(media&&want_valid)begin address=`SV_SLOT_BASE(active_slot)+2*((sy-OY)*640+sx-OX);want_rgb=expand(pixel(address));normal_pixels=normal_pixels+1;end
   if(media&&reference_fault)fault_pixels=fault_pixels+1;
   if(ev)begin want_rgb=24'he13579;want_valid=1;want_layer=3;emergency_pixels=emergency_pixels+1;end
   sample={sx,sy,dut.hs,dut.vs,sde,dut.ls,sfs,dut.afs,dut.hb,dut.vb,want_rgb,want_valid,want_layer};
   for(i=4;i>0;i=i-1)expected[i]=expected[i-1];expected[0]=sample;
   if(sfs)reference_fault=0;
   if(sx==HT-1&&sy==VT-1)frame=frame+1;
   #0.1;
   if(checks>10&&{x,y,hs,vs,de,ls,fs,afs,hb,vb,rgb[23:0],pv,layer}!==expected[4])
      begin $display("[FAIL] display HD=%0d frame=%0d xy=%0d,%0d rgb=%h expected=%h layer=%0d",HD,frame,x,y,rgb[23:0],expected[4][26:3],layer); $finish; end
   if(uc!==fault_count||ov!=0||miss!=0||swap_error)begin $display("[FAIL] display diagnostics HD=%0d uc=%0d/ref%0d ov=%0d miss=%0d swap=%b",HD,uc,fault_count,ov,miss,swap_error); $finish; end
   checks=checks+1;
  end
 end
 initial begin
  repeat(12)@(negedge sc);rst=1;repeat(15)@(negedge sc);fr=1;@(negedge sc);fr=0;
  wait(frame==2&&sy==OY+4&&sx==100);starvation=1;
  wait(frame==2&&sy==OY+24&&sx==100);starvation=0;
  wait(frame==3&&sy==120&&sx==100);@(negedge sc);wrslot=2;wrgen=8'h82;fr=1;@(negedge sc);fr=0;
  wait(frame==5&&sy==H);repeat(8)@(negedge pc);
  if(commits!=2||fault_count!=1||normal_pixels<900000||fault_pixels<200000||write_beats<100||emergency_pixels<100)begin $display("[FAIL] coverage HD=%0d commits=%0d faults=%0d pixels=%0d/%0d wr=%0d em=%0d",HD,commits,fault_count,normal_pixels,fault_pixels,write_beats,emergency_pixels); $finish; end
  done=1;$display("display HD=%0d checks=%0d normal=%0d emergency=%0d fault_pixels=%0d competing_write_beats=%0d commits=%0d",HD,checks,normal_pixels,emergency_pixels,fault_pixels,write_beats,commits);
 end
endmodule
module tb_a_video_display_core;
 wire a,b;display_case c0(a);display_case #(.HD(1)) c1(b);
 initial begin wait(a&&b);$display("PASS tb_a_video_display_core: actual B DMA+arbiter+swap, official async FIFO, complete BASE/HD frames, starvation/recovery, atomic slots and emergency priority");$finish;end
 initial begin #140000000;begin $display("[FAIL] display timeout"); $finish; end end
endmodule
