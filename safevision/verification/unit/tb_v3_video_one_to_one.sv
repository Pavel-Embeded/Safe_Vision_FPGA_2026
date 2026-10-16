`timescale 1ns/1ps
module tb_v3_video_one_to_one_model #(parameter HD=0)();
 reg sys=0,mem=0,pix=0,rst=0;
 always #5 sys=~sys;always #10 mem=~mem;
 generate if(HD)always #6.734 pix=~pix;else always #19.86 pix=~pix;endgenerate
 reg media_reset=0,cfg_valid=0,next_request=0,safety=0;
 reg[95:0] cfg=0;wire cfg_ready;reg[3:0] slots=15;
 reg audio_ready=0;reg[7:0] audio_gen=0;wire tv,busy,commit;
 wire[1:0] target,active;wire[7:0] target_gen,gen;
 wire fault,presentation_fault;wire[31:0] underflow;wire dma_busy,dma_progress;
 wire req;wire[31:0] addr,lookup_addr;wire[15:0] len;
 reg ack=0,memory_busy=0,valid=0;reg[31:0] data=0,lookup_crc=0;reg lookup_valid=0;
 wire[11:0] raw_x,raw_y,x,y;wire raw_de,raw_hs,raw_vs,frame_start;
 wire[23:0] rgb;wire hs,vs,de;
 reg corrupt_crc=0,allow_audio=1;
 v3_video_display_core #(.HD(HD),.PACKED_CACHE(1),.FONT_FILE("font8x16.mem"),.COMPACT_FONT_FILE("font8x16_compact.mem"),.STATUS_TEXT_FILE("v3_status_text.mem")) dut(
  .sys_clk(sys),.mem_clk(mem),.pixel_clk(pix),.sys_rst_n(rst),.mem_rst_n(rst),.pixel_rst_n(rst),
  .media_reset(media_reset),.cfg_valid(cfg_valid),.cfg_ready(cfg_ready),.cfg_data(cfg),.cache_valid(slots),
  .next_request(next_request),.safety_active(safety),.media_ready(audio_ready),.media_ready_generation(audio_gen),
  .transition_busy(busy),.frame_commit(commit),.active_slot(active),.generation(gen),
  .target_valid(tv),.target_slot(target),.target_generation(target_gen),.integrity_fault(fault),.presentation_fault(presentation_fault),
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
   if(HD)begin xx=ox-320;yy=oy-120;fx=0;fy=0;end
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
 reg[7:0] font[0:4095];initial $readmemh("font8x16.mem",font);
 integer ref_x=0,ref_y=0,ref_ticks=0,ref_count=0,ref_fps=0,ref_blink_count=0;
 reg ref_blink=1;reg[7:0] fps_history[0:20];reg blink_history[0:20];
 reg[26:0] timing_history[0:20];integer timing_cycles=0,monitor_ticks=0,hi;
 localparam HA=HD?1280:640,VA=HD?720:480,HT=HD?1650:800,VT=HD?750:525;
 localparam HF=HD?110:16,HSW=HD?40:96,VF=HD?5:10,VSW=HD?5:2,PIXEL_HZ=HD?74250000:25175000;
 wire ref_fs=ref_x==0&&ref_y==VA;
 wire ref_de=ref_x<HA&&ref_y<VA;
 wire ref_hs=(ref_x>=HA+HF&&ref_x<HA+HF+HSW)?(HD?1'b1:1'b0):(HD?1'b0:1'b1);
 wire ref_vs=(ref_y>=VA+VF&&ref_y<VA+VF+VSW)?(HD?1'b1:1'b0):(HD?1'b0:1'b1);
 always @(posedge pix)begin
  if(!rst)begin ref_x<=0;ref_y<=0;ref_ticks<=0;ref_count<=0;ref_fps<=0;
   ref_blink_count<=0;ref_blink<=1;monitor_ticks<=0;
   for(hi=0;hi<21;hi=hi+1)begin timing_history[hi]<=0;fps_history[hi]<=0;blink_history[hi]<=1;end
  end else begin
   if(ref_x==HT-1)begin ref_x<=0;if(ref_y==VT-1)ref_y<=0;else ref_y<=ref_y+1;end else ref_x<=ref_x+1;
   if(ref_ticks==PIXEL_HZ-1)begin ref_ticks<=0;ref_fps<=ref_count+(ref_fs?1:0);ref_count<=0;end
   else begin ref_ticks<=ref_ticks+1;if(ref_fs)ref_count<=ref_count+1;end
   if(ref_fs)begin if(ref_blink_count==29)begin ref_blink_count<=0;ref_blink<=~ref_blink;end
    else ref_blink_count<=ref_blink_count+1;end
   timing_history[0]<={ref_de,ref_hs,ref_vs,12'(ref_x),12'(ref_y)};
   fps_history[0]<=ref_fps;blink_history[0]<=ref_blink;
   for(hi=1;hi<21;hi=hi+1)begin timing_history[hi]<=timing_history[hi-1];
    fps_history[hi]<=fps_history[hi-1];blink_history[hi]<=blink_history[hi-1];end
   monitor_ticks<=monitor_ticks+1;
  end
 end
 always @(negedge pix)if(rst&&monitor_ticks>30)begin
  if({de,hs,vs,x,y}!==timing_history[20]||raw_x!=ref_x||raw_y!=ref_y||raw_de!==ref_de||frame_start!==ref_fs)begin
   if(errors<10)$display("[FAIL] independent fixed scan / output tags expected=%h got=%h",timing_history[20],{de,hs,vs,x,y});
   errors=errors+1;
  end
  timing_cycles=timing_cycles+1;
 end
 function[7:0] hex_ascii(input integer n);begin hex_ascii=n<10?48+n:55+n;end endfunction
 function[7:0] dec_ascii(input integer n,input integer place);
  begin dec_ascii=place==2?48+n/100:place==1?48+(n/10)%10:48+n%10;end
 endfunction
 // Independent glyph oracle: official font bytes plus human-readable content,
 // geometric regions, and per-channel rounded /255 blending. No DUT internals.
 function[15:0] normal_golden(input[15:0] background,input integer xx,yy,slot,gen,fps);
  reg[511:0] text;reg[7:0] code,bits;integer oy,len,category,row,index,period,brightness,energy;
  bit enabled,dot,panel,selected,border,bar_edge,bar_fill;reg[15:0] result,front;
  begin
   oy=0;len=0;category=2;row=0;enabled=0;text=0;dot=0;
   if(yy>=8&&yy<24)begin oy=8;len=37;enabled=1;
    text=HD?"SAFEVISION HD   SLOT 1 GEN 000 FPS 00                           ":
            "SAFEVISION BASE SLOT 1 GEN 000 FPS 00                           ";end
   else if(yy>=24&&yy<40)begin oy=24;len=40;enabled=1;text="SD READY CACHE F STATE PLAY LAT 21 PX                           ";end
   else if(yy>=40&&yy<56)begin oy=40;len=42;enabled=1;text="VIDEO UF 00000000 AUDIO UF 00000000 ERR 00                      ";end
   else if(cfg[55]&&yy>=80&&yy<256)begin
    row=(yy-80)/20;oy=80+row*20;len=35;category=0;enabled=yy<oy+16;
    case(row)
     0:text="CONFIG  NEXT:+ AUTO:- LONG NEXT:FIELD                           ";
     1:text="BRIGHTNESS  +000                                                ";
     2:text="CONTRAST    000                                                 ";
     3:text="SCALER      NEAREST                                             ";
     4:text="SCALE       FIT                                                 ";
     5:text="FADE        ON  32 FRAMES                                       ";
     6:text="VOLUME      000                                                 ";
     7:text="PERIOD      00 SECONDS                                          ";
     8:text="OSD ALPHA   000                                                 ";
    endcase
   end else if(yy>=VA-64&&yy<VA-48&&cfg[47:40]!=0)begin
    oy=VA-64;len=39;category=1;enabled=1;text="WARNING CODE 00 | PRESS NEXT TO RECOVER                         ";end
   else if(yy>=VA-40&&yy<VA-24)begin oy=VA-40;len=33;category=0;enabled=1;text="SAFEVISION | EMERGENCY EXIT SYSTEM                              ";end
   else if(yy>=VA-24&&yy<VA-8)begin oy=VA-24;len=6;category=2;enabled=1;text="LEVEL                                                           ";end
   index=(xx-8)/8;
   if(enabled&&xx>=8&&xx<8+len*8)begin
    code=text[(63-index)*8+:8];
    if(oy==8)begin
     if(index==21)code=49+slot;
     if(index>=27&&index<=29)code=dec_ascii(gen,29-index);
     if(index==35)code=dec_ascii(fps,1);if(index==36)code=dec_ascii(fps,0);
    end
    if(oy==40)begin
     if(index==40)code=hex_ascii(cfg[47:44]);if(index==41)code=hex_ascii(cfg[43:40]);
    end
    if(category==0&&oy>=100&&oy<=240)begin
     brightness=$signed(cfg[95:87]);period=cfg[60:59]==0?2:cfg[60:59]==1?5:cfg[60:59]==2?10:30;
     case(row)
      1:begin if(index==12)code=brightness<0?45:43;
       if(index>=13&&index<=15)code=dec_ascii(brightness<0?-brightness:brightness,15-index);end
      2:if(index>=12&&index<=14)code=dec_ascii(cfg[86:79],14-index);
      3:if(cfg[70]&&index>=12&&index<=19)begin
       case(index)12:code="B";13:code="I";14:code="L";15:code="I";16:code="N";17:code="E";18:code="A";19:code="R";endcase end
      4:if(!cfg[69]&&index>=12&&index<=14)begin case(index)12:code="1";13:code=":";14:code="1";endcase end
      5:if(!cfg[68]&&index>=12&&index<=14)begin case(index)12:code="O";13:code="F";14:code="F";endcase end
      6:if(index>=12&&index<=14)code=dec_ascii(cfg[67:61],14-index);
      7:if(index==12)code=dec_ascii(period,1);else if(index==13)code=dec_ascii(period,0);
      8:if(index>=12&&index<=14)code=dec_ascii(cfg[78:71],14-index);
     endcase
    end
    if(category==1)begin if(index==13)code=hex_ascii(cfg[47:44]);if(index==14)code=hex_ascii(cfg[43:40]);end
    bits=font[code*16+(yy-oy)];dot=bits[7-(xx-8)%8];
   end
   panel=cfg[55]&&xx>=4&&xx<300&&yy>=76&&yy<260;
   selected=panel&&yy>=100+cfg[58:56]*20&&yy<116+cfg[58:56]*20;
   border=cfg[47:40]!=0&&(xx<4||xx>=HA-4||yy<4||yy>=VA-4);
   energy=cfg[54:48]>100?100:cfg[54:48];
   bar_edge=xx>=80&&xx<282&&yy>=VA-22&&yy<VA-10&&(xx==80||xx==281||yy==VA-22||yy==VA-11);
   bar_fill=xx>80&&xx<81+energy*2&&yy>VA-22&&yy<VA-11;
   result=background;
   if((dot&&category==0)||panel)begin front=dot&&category==0?16'hffff:selected?16'h05bf:16'h1086;
    result=blend(front,result,cfg[78:71]);end
   if(border||(dot&&category==1))result=blend(16'hf800,result,224);
   if((dot&&category==2)||bar_edge||bar_fill)begin front=dot&&category==2?16'hffff:bar_fill?16'h07e0:16'h7bef;
    result=blend(front,result,224);end
   normal_golden=result;
  end
 endfunction
 function[15:0] safe_golden(input integer xx,yy,input bit blink);
  integer dx,dy,oy,ox,len,index,scaled_x,scaled_y;reg[255:0] text;reg[7:0] bits,code;bit dot,arrow,border;
  begin scaled_x=xx/2;scaled_y=yy/2;oy=0;ox=0;len=0;text=0;dot=0;
   if(scaled_y>=VA/8&&scaled_y<VA/8+16)begin oy=VA/8;ox=HA/4-36;len=9;text="EMERGENCY                       ";end
   else if(scaled_y>=VA/8+20&&scaled_y<VA/8+36)begin oy=VA/8+20;ox=HA/4-16;len=4;text="EXIT                            ";end
   else if(scaled_y>=VA*3/8&&scaled_y<VA*3/8+16)begin oy=VA*3/8;ox=HA/4-108;len=27;text="SAFE MODE - NEXT TO RECOVER     ";end
   if(len&&scaled_x>=ox&&scaled_x<ox+len*8)begin index=(scaled_x-ox)/8;code=text[(31-index)*8+:8];
    bits=font[code*16+scaled_y-oy];dot=bits[7-(scaled_x-ox)%8];end
   dy=yy>=VA/2?yy-VA/2:VA/2-yy;
   arrow=(xx>=HA/2-96&&xx<HA/2-32&&dy<=(xx-(HA/2-96))/2)||
    (xx>=HA/2-32&&xx<HA/2+96&&dy<=12);
   border=xx<4||xx>=HA-4||yy<4||yy>=VA-4;
   safe_golden=dot?16'h07e0:border?(blink?16'hf800:16'h7800):(arrow&&blink)?16'h07e0:16'h1800;
  end
 endfunction
 task compare_frame(input integer mode,input integer slot,input bit bilinear,input bit overlays);
  reg[15:0] expected;reg[23:0] expected_rgb;integer pixels,start_words;bit collecting;
  begin pixels=0;collecting=0;start_words=words;
   while(!collecting)begin @(negedge pix);if(de&&x==0&&y==0)collecting=1;end
   while(pixels<(HD?1280*720:640*480))begin
    if(de)begin
     if(mode==1)expected=safe_golden(x,y,blink_history[20]);
     else begin expected=(HD&&(x<320||x>=960||y<120||y>=600))?0:sampled(slot,x,y,bilinear);
      expected=normal_golden(expected,x,y,slot,slot+1,fps_history[20]);
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
 initial begin
  cfg[86:79]=128;cfg[78:71]=160;cfg[69]=0;cfg[68]=0;cfg[67:61]=80;
  #100;rst=1;update_cfg();
  wait(gen==1);wait_frame();wait_frame();compare_frame(0,0,0,0);
  cfg[70]=1;update_cfg();wait_frame();wait_frame();compare_frame(0,0,1,0);
  if(underflow!=0||fault||presentation_fault)begin
   $display("[FAIL] centered 1:1 bounds underflow=%0d fault=%b",underflow,fault);errors=errors+1;end
  $display("[PASS] centered 640x480 viewport with every black border and final source pixel");
  $display("[TB] tb_v3_video_one_to_one done comparisons=%0d errors=%0d",comparisons,errors);$finish;
 end
 initial begin #1000000000;$display("[FAIL] 1:1 timeout errors=1");$finish;end
endmodule
module tb_v3_video_one_to_one;tb_v3_video_one_to_one_model #(.HD(1)) model();endmodule
