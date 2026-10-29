`timescale 1ns/1ps
module tb_v3_video_model #(parameter HD=0)();
 reg sys=0,mem=0,pix=0,rst=0;
 always #5 sys=~sys;always #12.5 mem=~mem;
 generate if(HD)always #6.734 pix=~pix;else always #19.86 pix=~pix;endgenerate
 reg media_reset=0,cfg_valid=0,next_request=0,safety=0;
 reg[95:0] cfg=0;wire cfg_ready;reg[3:0] slots=15;
 reg audio_ready=0;reg[7:0] audio_gen=0;wire tv,busy,commit;
 wire[1:0] target,active;wire[7:0] target_gen,gen;
 wire fault;wire[31:0] underflow;wire dma_busy,dma_progress;
 wire req;wire[31:0] addr,lookup_addr;wire[15:0] len;
 reg ack=0,memory_busy=0,valid=0;reg[31:0] data=0,lookup_crc=0;reg lookup_valid=0;
 wire[11:0] raw_x,raw_y,x,y;wire raw_de,raw_hs,raw_vs,frame_start;
 wire[23:0] rgb;wire hs,vs,de;
 reg corrupt_crc=0,allow_audio=1;
 v3_video_display_core #(.HD(HD)) dut(
  .sys_clk(sys),.mem_clk(mem),.pixel_clk(pix),.sys_rst_n(rst),.mem_rst_n(rst),.pixel_rst_n(rst),
  .media_reset(media_reset),.cfg_valid(cfg_valid),.cfg_ready(cfg_ready),.cfg_data(cfg),.cache_valid(slots),
  .next_request(next_request),.safety_active(safety),.media_ready(audio_ready),.media_ready_generation(audio_gen),
  .transition_busy(busy),.frame_commit(commit),.active_slot(active),.generation(gen),
  .target_valid(tv),.target_slot(target),.target_generation(target_gen),.integrity_fault(fault),
  .underflows(underflow),.dma_busy(dma_busy),.dma_progress(dma_progress),
  .rd_req(req),.rd_addr(addr),.rd_len(len),.rd_ack(ack),.rd_busy(memory_busy),.rd_data(data),.rd_valid(valid),
  .lookup_addr(lookup_addr),.lookup_crc(lookup_crc),.lookup_valid(lookup_valid),
  .raw_x(raw_x),.raw_y(raw_y),.raw_de(raw_de),.raw_hs(raw_hs),.raw_vs(raw_vs),.frame_start(frame_start),
  .x(x),.y(y),.rgb(rgb),.hs(hs),.vs(vs),.de(de));
 function[31:0] slot_base(input integer slot);begin slot_base=slot*32'h000a0000;end endfunction
 function integer address_slot(input[31:0] a);begin address_slot=a/32'h000a0000;end endfunction
 function[15:0] source_pixel(input integer slot,input integer px,input integer py);
  begin source_pixel={5'((px+slot*7+py)%32),6'((px/2+py+slot*11)%64),5'((py/3+px/5+slot*13)%32)};end
 endfunction
 function[31:0] source_word(input[31:0] a);
  integer s,o,py,px;begin s=address_slot(a);o=a-slot_base(s);py=o/1280;px=(o%1280)/2;
   source_word={source_pixel(s,px+1,py),source_pixel(s,px,py)};end
 endfunction
 function[31:0] crcword(input[31:0] initial_crc,input[31:0] d);
  reg[31:0] c;integer b;begin c=initial_crc^d;
   for(b=0;b<32;b=b+1)c=c[0]?(c>>1)^32'hedb88320:c>>1;crcword=c;end
 endfunction
 reg[31:0] crcs[0:1919];integer s,r,c;reg[31:0] state;
 initial begin for(s=0;s<4;s=s+1)for(r=0;r<480;r=r+1)begin state=32'hffffffff;
  for(c=0;c<320;c=c+1)state=crcword(state,source_word(slot_base(s)+r*1280+c*4));
  crcs[s*480+r]=~state;end end
 reg[31:0] transaction_address;integer remaining=0,words=0,phase=0;
 always @(posedge mem)begin
  ack<=0;valid<=0;
  if(!rst||media_reset)begin memory_busy<=0;remaining<=0;end
  else begin
   lookup_crc<=crcs[address_slot(lookup_addr)*480+(lookup_addr-slot_base(address_slot(lookup_addr)))/1280]^(corrupt_crc?32'd1:0);
   lookup_valid<=1;
   if(req&&!memory_busy)begin ack<=1;memory_busy<=1;transaction_address<=addr;remaining<=len;end
   else if(memory_busy)begin
    if(remaining==0)memory_busy<=0;
    else if(phase%13!=12)begin
     valid<=1;data<=source_word(transaction_address);transaction_address<=transaction_address+4;
     remaining<=remaining-1;words<=words+1;
    end
    phase<=phase+1;
   end
  end
 end
 always @(posedge sys)if(rst&&tv&&allow_audio)begin audio_ready<=1;audio_gen<=target_gen;end
 integer errors=0,comparisons=0,frames=0,commits=0;
 always @(posedge sys)if(commit)commits<=commits+1;
 task update_cfg;begin @(negedge sys);while(!cfg_ready)@(negedge sys);cfg_valid=1;
  @(negedge sys);cfg_valid=0;end endtask
 task request_next;begin @(negedge sys);next_request=1;@(negedge sys);next_request=0;end endtask
 task wait_frame;begin @(posedge pix);while(!(raw_x==0&&raw_y==0))@(posedge pix);end endtask
 function[15:0] blend(input[15:0] f,b,input integer alpha);
  integer rr,gg,bb;begin rr=(f[15:11]*alpha+b[15:11]*(255-alpha)+127)/255;
   gg=(f[10:5]*alpha+b[10:5]*(255-alpha)+127)/255;
   bb=(f[4:0]*alpha+b[4:0]*(255-alpha)+127)/255;blend={5'(rr),6'(gg),5'(bb)};end
 endfunction
 function[15:0] sampled(input integer slot,ox,oy,input bit bilinear);
  integer xx,yy,fx,fy,nx,ny,rt,rb,rr,gt,gb,gg,bt,bb,bv;
  reg[15:0] p00,p10,p01,p11;begin
   if(HD)begin xx=((ox-160)*2)/3;yy=(oy*2)/3;fx=(((ox-160)*2)%3)*256/3;fy=((oy*2)%3)*256/3;end
   else begin xx=ox;yy=oy;fx=0;fy=0;end
   nx=xx==639?639:xx+1;ny=yy==479?479:yy+1;
   p00=source_pixel(slot,xx,yy);p10=source_pixel(slot,nx,yy);p01=source_pixel(slot,xx,ny);p11=source_pixel(slot,nx,ny);
   if(!bilinear)sampled=p00;
   else begin
    rt=(p00[15:11]*(256-fx)+p10[15:11]*fx+128)/256;rb=(p01[15:11]*(256-fx)+p11[15:11]*fx+128)/256;rr=(rt*(256-fy)+rb*fy+128)/256;
    gt=(p00[10:5]*(256-fx)+p10[10:5]*fx+128)/256;gb=(p01[10:5]*(256-fx)+p11[10:5]*fx+128)/256;gg=(gt*(256-fy)+gb*fy+128)/256;
    bt=(p00[4:0]*(256-fx)+p10[4:0]*fx+128)/256;bb=(p01[4:0]*(256-fx)+p11[4:0]*fx+128)/256;bv=(bt*(256-fy)+bb*fy+128)/256;
    sampled={5'(rr),6'(gg),5'(bv)};
   end
  end
 endfunction
 task compare_frame(input integer mode,input integer slot,input bit bilinear,input bit overlays);
  reg[15:0] expected;reg[23:0] expected_rgb;integer pixels,start_words;bit collecting;
  begin pixels=0;collecting=0;start_words=words;
   while(!collecting)begin @(negedge pix);if(de&&x==0&&y==0)collecting=1;end
   while(pixels<(HD?1280*720:640*480))begin
    if(de)begin
     if(mode==1)expected=(x<4||x>=(HD?1280:640)-4||y<4||y>=(HD?720:480)-4||
       (x>=(HD?640:320)-96&&x<(HD?640:320)+96&&y>=(HD?360:240)-12&&y<(HD?360:240)+12))?16'hf800:16'h1800;
     else begin expected=(HD&&(x<160||x>=1120))?0:sampled(slot,x,y,bilinear);
      if(overlays)begin
       if(x<240&&y<40)expected=blend(16'h18df,expected,160);
       if(x<4||x>=(HD?1280:640)-4||y<4||y>=(HD?720:480)-4)expected=blend(16'hf800,expected,192);
       if(y>=(HD?720:480)-20&&x<150)expected=blend(16'h07e0,expected,224);
      end
     end
     expected_rgb={expected[15:11],expected[15:13],expected[10:5],expected[10:9],expected[4:0],expected[4:2]};
     if(rgb!==expected_rgb)begin
      if(errors<10)$display("[FAIL] HD=%0d xy=%0d,%0d mode=%0d expected=%h got=%h sy=%0d rows=%b enabled=%b",HD,x,y,mode,expected_rgb,rgb,dut.sy,dut.rows_ready,dut.enabled);
      errors=errors+1;
     end
     if((x<(HD?1280:640)&&y<(HD?720:480))!==de)begin $display("[FAIL] tags DE geometry");errors=errors+1;end
     comparisons=comparisons+1;pixels=pixels+1;
    end
    @(negedge pix);
   end
   if(mode==0&&!busy&&words-start_words>160000)begin $display("[FAIL] row reuse words=%0d",words-start_words);errors=errors+1;end
   frames=frames+1;$display("[PASS] full raster HD=%0d mode=%0d slot=%0d bilinear=%0d pixels=%0d words=%0d",HD,mode,slot,bilinear,pixels,words-start_words);
  end
 endtask
 integer wait_count;
 initial begin
  cfg[86:79]=128;cfg[78:71]=160;cfg[69]=1;cfg[68]=1;cfg[67:61]=80;
  #100;rst=1;update_cfg();
  wait(gen==1);wait_frame();wait_frame();compare_frame(0,0,0,0);
  cfg[70]=1;update_cfg();wait_frame();wait_frame();compare_frame(0,0,1,0);
  cfg[55]=1;cfg[54:48]=75;cfg[47:40]=1;update_cfg();wait_frame();wait_frame();compare_frame(0,0,1,1);
  cfg[55]=0;cfg[47:40]=0;update_cfg();wait_frame();wait_frame();
  allow_audio=0;audio_ready=0;request_next();wait(tv&&target_gen==2);wait(busy);
  repeat(35)wait_frame();
  if(gen!=1||!busy)begin $display("[FAIL] committed without matching audio generation");errors=errors+1;end
  allow_audio=1;wait(gen==2);wait_frame();wait_frame();compare_frame(0,1,1,0);
  if(underflow!=0||fault)begin $display("[FAIL] normal DMA underflow=%d fault=%b",underflow,fault);errors=errors+1;end
  safety=1;wait_frame();compare_frame(1,0,0,0);
  media_reset=1;repeat(200)@(posedge sys);media_reset=0;wait_frame();compare_frame(1,0,0,0);

  safety=0;corrupt_crc=1;wait(tv);allow_audio=1;wait(fault);wait_frame();compare_frame(1,0,0,0);
  $display("[PASS] media-reset SAFE continuity and corrupt CRC detection");
  $display("[TB] tb_v3_video_%s done frames=%0d comparisons=%0d errors=%0d",HD?"hd":"base",frames,comparisons,errors);
  if(errors==0)$display("PASS tb_v3_video_%s",HD?"hd":"base");
  $finish;
 end
 initial begin #2000000000;$display("[FAIL] video test timeout errors=1");$finish;end
endmodule
module tb_v3_video_base;tb_v3_video_model #(.HD(0)) model();endmodule
module tb_v3_video_hd;tb_v3_video_model #(.HD(1)) model();endmodule
