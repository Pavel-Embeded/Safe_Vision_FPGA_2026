`include "video_mode_defs.vh"
// V3 presentation clock is never stopped. Geometry, hard SAFE and output tags
// use global pixel reset only. media_reset flushes fetch/control epochs without
// resetting scan. cfg is committed in vertical blank; audio/video target and
// final generation are atomic bundled descriptors across clock domains.
module v3_video_display_core #(
 parameter integer HD=0,FADE_FRAMES=32,MEM_TIMEOUT=4000000,TRANSITION_TIMEOUT_FRAMES=300,PACKED_CACHE=0,
 parameter FONT_FILE="font8x16.mem",
 parameter COMPACT_FONT_FILE="../../assets/fonts/font8x16_compact.mem",
 parameter STATUS_TEXT_FILE="../../assets/fonts/v3_status_text.mem",
 parameter integer PIXEL_HZ=HD?74250000:25175000
)(
 input wire sys_clk,mem_clk,pixel_clk,sys_rst_n,mem_rst_n,pixel_rst_n,
 input wire media_reset,cfg_valid,output wire cfg_ready,input wire[95:0] cfg_data,
 input wire[3:0] cache_valid,input wire next_request,safety_active,
 input wire media_ready,input wire[7:0] media_ready_generation,
 output wire transition_busy,output reg frame_commit,output reg[1:0] active_slot,
 output reg[7:0] generation,output reg target_valid,output reg[1:0] target_slot,
 output reg[7:0] target_generation,output reg integrity_fault,presentation_fault,
 output reg[31:0] underflows,output wire dma_busy,dma_progress,
 output wire rd_req,output wire[31:0] rd_addr,output wire[15:0] rd_len,
 input wire rd_ack,rd_busy,input wire[31:0] rd_data,input wire rd_valid,
 output wire[31:0] lookup_addr,input wire[31:0] lookup_crc,input wire lookup_valid,
 output wire[11:0] raw_x,raw_y,output wire raw_de,raw_hs,raw_vs,frame_start,
 output wire[11:0] x,y,output reg[23:0] rgb,output wire hs,vs,de
);
 localparam HA=HD?1280:640,HF=HD?110:16,HS=HD?40:96,HB=HD?220:48;
 localparam VA=HD?720:480,VF=HD?5:10,VS=HD?5:2,VB=HD?20:33;
 localparam HT=HA+HF+HS+HB,VT=VA+VF+VS+VB,LATENCY=21;
 wire line_start,active_frame_start;
 video_timing #(.H_ACTIVE(HA),.H_FRONT(HF),.H_SYNC(HS),.H_BACK(HB),
  .V_ACTIVE(VA),.V_FRONT(VF),.V_SYNC(VS),.V_BACK(VB),
  .HSYNC_ACTIVE(HD?1'b1:1'b0),.VSYNC_ACTIVE(HD?1'b1:1'b0)) timing(
  .clk(pixel_clk),.rst_n(pixel_rst_n),.x(raw_x),.y(raw_y),.de(raw_de),
  .hsync(raw_hs),.vsync(raw_vs),.line_start(line_start),.frame_start(frame_start),
  .active_frame_start(active_frame_start),.hblank(),.vblank());
 (* async_reg="true" *) reg media_m1,media_m2,media_p1,media_p2,safe_p1,safe_p2;
 always @(posedge mem_clk or negedge mem_rst_n)begin
  if(!mem_rst_n)begin media_m1<=0;media_m2<=0;end
  else begin media_m1<=media_reset;media_m2<=media_m1;end
 end
 always @(posedge pixel_clk or negedge pixel_rst_n)begin
  if(!pixel_rst_n)begin media_p1<=0;media_p2<=0;safe_p1<=1;safe_p2<=1;end
  else begin media_p1<=media_reset;media_p2<=media_p1;safe_p1<=safety_active;safe_p2<=safe_p1;end
 end
 wire fetch_mem_rst_n=mem_rst_n&&!media_m2,fetch_pixel_rst_n=pixel_rst_n&&!media_p2;
 reg[95:0] cfg_shadow;reg[3:0] cache_shadow;reg cfg_pending;
 wire cfg_send_ready,cfg_received;wire[99:0] cfg_packet;
 assign cfg_ready=!cfg_pending&&cfg_send_ready;
 always @(posedge sys_clk or negedge sys_rst_n)begin
  if(!sys_rst_n)begin cfg_shadow<=0;cache_shadow<=0;cfg_pending<=0;end
  else begin
   if(cfg_pending&&cfg_send_ready)cfg_pending<=0;
   if(cfg_valid&&cfg_ready)begin cfg_shadow<=cfg_data;cache_shadow<=cache_valid;cfg_pending<=1;end
   if(cache_shadow!=cache_valid)begin cache_shadow<=cache_valid;cfg_pending<=1;end
  end
 end
 video_cdc_mailbox #(.WIDTH(100)) config_mailbox(
  .src_clk(sys_clk),.src_rst_n(sys_rst_n),.src_data({cfg_shadow,cache_shadow}),
  .src_valid(cfg_pending),.src_ready(cfg_send_ready),
  .dst_clk(pixel_clk),.dst_rst_n(pixel_rst_n),.dst_data(cfg_packet),
  .dst_valid(cfg_received),.dst_ready(frame_start));
 reg[95:0] cfg;reg[3:0] slots;
 reg next_pending_sys,request_outstanding,pixel_busy_sys;wire next_send_ready,next_received;
 wire next_accept=next_request&&!transition_busy&&!safety_active&&!media_reset;
 assign transition_busy=pixel_busy_sys||request_outstanding;
 always @(posedge sys_clk or negedge sys_rst_n)begin
  if(!sys_rst_n)next_pending_sys<=0;
  else begin if(next_pending_sys&&next_send_ready)next_pending_sys<=0;
   if(next_accept)next_pending_sys<=1;
   if(media_reset||safety_active)next_pending_sys<=0;end
 end
 video_cdc_mailbox #(.WIDTH(1)) next_mailbox(
  .src_clk(sys_clk),.src_rst_n(sys_rst_n),.src_data(1'b1),
  .src_valid(next_pending_sys),.src_ready(next_send_ready),
  .dst_clk(pixel_clk),.dst_rst_n(pixel_rst_n),.dst_data(),
  .dst_valid(next_received),.dst_ready(1'b1));
 reg[8:0] audio_shadow;reg audio_pending;wire audio_send_ready,audio_received;
 wire[8:0] audio_packet;reg[8:0] audio_available;
 always @(posedge sys_clk or negedge sys_rst_n)begin
  if(!sys_rst_n)begin audio_shadow<=0;audio_pending<=0;end
  else begin if(audio_pending&&audio_send_ready)audio_pending<=0;
   if(audio_shadow!={media_ready,media_ready_generation})begin
    audio_shadow<={media_ready,media_ready_generation};audio_pending<=1;end
  end
 end
 video_cdc_mailbox #(.WIDTH(9)) audio_ready_mailbox(
  .src_clk(sys_clk),.src_rst_n(sys_rst_n),.src_data(audio_shadow),
  .src_valid(audio_pending),.src_ready(audio_send_ready),
  .dst_clk(pixel_clk),.dst_rst_n(pixel_rst_n),.dst_data(audio_packet),
  .dst_valid(audio_received),.dst_ready(1'b1));
 wire[1:0] current,target;wire[7:0] gen,fade_alpha,target_gen_p;
 wire busy,initialized,commit_toggle,next_done_toggle,direct_target,presentation_fault_p;
 always @(posedge pixel_clk or negedge pixel_rst_n)begin
  if(!pixel_rst_n)begin cfg<=0;slots<=0;audio_available<=0;end
  else begin
   if(cfg_received&&frame_start)begin cfg<=cfg_packet[99:4];slots<=cfg_packet[3:0];end
   if(audio_received)audio_available<=audio_packet;
  end
 end
 v3_presentation_ctrl #(.FADE_FRAMES(FADE_FRAMES),
  .TRANSITION_TIMEOUT_FRAMES(TRANSITION_TIMEOUT_FRAMES)) presentation(
  .clk(pixel_clk),.rst_n(pixel_rst_n),.frame_start(frame_start),.media_reset(media_p2),
  .safety(safe_p2),.request(next_received),.fade_enable(cfg_received?cfg_packet[72]:cfg[68]),
  .valid_slots(cfg_received?cfg_packet[3:0]:slots),
  .audio_ready(audio_available[8]),.audio_generation(audio_available[7:0]),
  .current(current),.target(target),.generation(gen),.target_generation(target_gen_p),.alpha(fade_alpha),
  .busy(busy),.initialized(initialized),.direct_target(direct_target),.commit_toggle(commit_toggle),
  .next_done_toggle(next_done_toggle),.presentation_fault(presentation_fault_p));
 wire coord_valid;wire[9:0] sx,sy;wire[7:0] fx,fy;
 scaler_coords #(.HD(HD)) coords(.clk(pixel_clk),.rst_n(pixel_rst_n),.de(raw_de),
  .x(raw_x),.y(raw_y),.fit(cfg[69]),.valid(coord_valid),.sx(sx),.sy(sy),.fx(fx),.fy(fy));
 reg row_pending;reg[9:0] pending_row;wire row_request_ready;
 wire[9:0] row_next=pending_row==479?10'd479:pending_row+1'b1;
 wire[1:0] fetch_current=(!initialized&&busy&&direct_target)?target:current;
 wire[23:0] row_descriptor={fetch_current,target,(busy&&!direct_target),pending_row,row_next[8:0]};
 wire response_valid;wire[23:0] response_data;
 wire[15:0] a00,a10,a01,a11,b00,b10,b01,b11;
 wire rows_ready,sample_valid,primed,cache_fault;
 reg enabled;
 function[9:0] visible_source_row;
  input[11:0] screen_row;input fit_mode;
  reg[9:0] n;reg[19:0] product;
  begin
   if(HD&&fit_mode)begin n=screen_row[9:0];product=n*10'd683;visible_source_row=product[19:10];end
   else if(screen_row<((VA-480)/2))visible_source_row=0;
   else if(screen_row>=((VA-480)/2)+480)visible_source_row=479;
   else visible_source_row=screen_row-((VA-480)/2);
  end
 endfunction
 wire[11:0] next_visible_y=raw_y<VA-1?raw_y+1'b1:12'd0;
 wire[9:0] prepared_source_row=visible_source_row(next_visible_y,cfg[69]);
 integer next_y;
 always @(posedge pixel_clk or negedge fetch_pixel_rst_n)begin
  if(!fetch_pixel_rst_n)begin row_pending<=0;pending_row<=0;enabled<=0;end
  else begin
   if(row_pending&&row_request_ready)row_pending<=0;
   if(frame_start)begin pending_row<=0;row_pending<=(slots[current]&&initialized)||(busy&&direct_target&&slots[target]);end
   // Two output lines of lookahead use all four source-row banks. This lets
   // bounded physical SDRAM command/quiet/refresh gaps overlap scan time.
   else if(line_start&&raw_y<VA-2&&initialized&&slots[current])begin
    next_y=raw_y+2;
    if(cfg[69])begin pending_row<=HD?(next_y*2)/3:next_y;row_pending<=1;end
    else if(next_y>=((VA-480)/2)&&next_y<((VA-480)/2)+480)begin
     pending_row<=next_y-((VA-480)/2);row_pending<=1;end
   end
   if(raw_x==HT-1&&raw_y==VT-1)enabled<=initialized&&slots[current]&&primed;
   if(frame_start&&!initialized)enabled<=0;
  end
 end
 v3_line_cache #(.TIMEOUT(MEM_TIMEOUT),.PACKED_ROWS(PACKED_CACHE)) cache(
  .mem_clk(mem_clk),.mem_rst_n(fetch_mem_rst_n),.pixel_clk(pixel_clk),.pixel_rst_n(fetch_pixel_rst_n),
  .write_clk(sys_clk),.write_rst_n(sys_rst_n&&!media_reset),
  .prepare_valid(raw_x==HA),.prepare_sy(prepared_source_row),
  .request_valid(row_pending),.request_ready(row_request_ready),.request_data(row_descriptor),
  .response_valid(response_valid),.response_ready(1'b1),.response_data(response_data),
  .sx(sx),.sy(sy),.coord_valid(coord_valid&&(!PACKED_CACHE||enabled)),.current_slot(current),.target_slot(target),
  .dual_needed(busy&&!direct_target),.primed(primed),
  .a00(a00),.a10(a10),.a01(a01),.a11(a11),.b00(b00),.b10(b10),.b01(b01),.b11(b11),
  .rows_ready(rows_ready),.sample_valid(sample_valid),.rd_req(rd_req),.rd_addr(rd_addr),.rd_len(rd_len),
  .rd_ack(rd_ack),.rd_busy(rd_busy),.rd_data(rd_data),.rd_valid(rd_valid),
  .lookup_addr(lookup_addr),.lookup_crc(lookup_crc),.lookup_valid(lookup_valid),
  .fault(cache_fault),.dma_busy(dma_busy),.dma_progress(dma_progress));
 (* async_reg="true" *) reg fault_s1,fault_s2,fault_p1,fault_p2,present_s1,present_s2;
 always @(posedge sys_clk or negedge sys_rst_n)begin
  if(!sys_rst_n)begin fault_s1<=0;fault_s2<=0;integrity_fault<=0;present_s1<=0;present_s2<=0;presentation_fault<=0;end
  else begin fault_s1<=cache_fault;fault_s2<=fault_s1;
   present_s1<=presentation_fault_p;present_s2<=present_s1;
   if(media_reset)presentation_fault<=0;else if(present_s2)presentation_fault<=1;
   if(media_reset)integrity_fault<=0;else if(fault_s2)integrity_fault<=1;end
 end
 always @(posedge pixel_clk or negedge pixel_rst_n)begin
  if(!pixel_rst_n)begin fault_p1<=0;fault_p2<=0;end
  else begin fault_p1<=cache_fault;fault_p2<=fault_p1;end
 end
 reg[7:0] fx3,fy3;reg[31:0] pixel_underflows;
 always @(posedge pixel_clk or negedge pixel_rst_n)begin
  if(!pixel_rst_n)begin fx3<=0;fy3<=0;pixel_underflows<=0;end
  else begin fx3<=fx;fy3<=fy;
   if(media_p2)pixel_underflows<=0;
   else if(sample_valid&&!rows_ready&&enabled&&!safe_p2&&!fault_p2&&pixel_underflows!=32'hffffffff)
    pixel_underflows<=pixel_underflows+1'b1;
  end
 end
 wire[15:0] source_a,source_b,fade_pixel,adjusted;wire av,bv,fv,cv;
 v3_scaler_bilinear_thirds sa(.clk(pixel_clk),.rst_n(pixel_rst_n),.valid_in(sample_valid&&rows_ready&&enabled),
  .bilinear(cfg[70]),.p00(a00),.p10(a10),.p01(a01),.p11(a11),.fx(fx3),.fy(fy3),.pixel(source_a),.valid_out(av));
 v3_scaler_bilinear_thirds sb(.clk(pixel_clk),.rst_n(pixel_rst_n),.valid_in(sample_valid&&rows_ready&&enabled),
  .bilinear(cfg[70]),.p00(b00),.p10(b10),.p01(b01),.p11(b11),.fx(fx3),.fy(fy3),.pixel(source_b),.valid_out(bv));
 alpha_blend fade(.clk(pixel_clk),.rst_n(pixel_rst_n),.valid_in(av),
  .front(busy&&!direct_target?source_b:16'd0),.back(source_a),
  .alpha(busy&&!direct_target?fade_alpha:8'd0),.pixel(fade_pixel),.valid_out(fv));
 color_adjust adjust(.clk(pixel_clk),.rst_n(pixel_rst_n),.valid_in(fv),.pixel_in(fade_pixel),
  .brightness(cfg[95:87]),.contrast(cfg[86:79]),.pixel_out(adjusted),.valid_out(cv));
 // Four layers, in this order: background, status/menu OSD, warning graphic,
 // energy/config HUD. Transparent layers use alpha=0, never priority mux.
 wire[15:0] osd_pixel4,em_pixel4,hud_pixel4,safe_pixel4;
 wire[7:0] osd_alpha4,em_alpha4,hud_alpha4;
 v3_status_layers #(.HD(HD),.PIXEL_HZ(PIXEL_HZ),.PIPE_LATENCY(LATENCY),.FONT_FILE(FONT_FILE),
  .COMPACT_FONT_FILE(COMPACT_FONT_FILE),.TEXT_FILE(STATUS_TEXT_FILE)) graphics(
  .pixel_clk(pixel_clk),.pixel_rst_n(pixel_rst_n),.raw_x(raw_x),.raw_y(raw_y),.raw_de(raw_de),
  .frame_start(frame_start),.cfg_data(cfg),.cache_valid(slots),.underflows(pixel_underflows),
  .active_slot(current),.generation(gen),.busy(busy),
  .safety_active(safe_p2||media_p2||fault_p2||presentation_fault_p||!enabled),
  .osd_rgb565(osd_pixel4),.emergency_rgb565(em_pixel4),.hud_rgb565(hud_pixel4),.safe_rgb565(safe_pixel4),
  .osd_alpha(osd_alpha4),.emergency_alpha(em_alpha4),.hud_alpha(hud_alpha4));
 reg[15:0] osd_pixels[0:6],em_pixels[0:9],hud_pixels[0:12],safe_pixels[0:15];
 reg[7:0] osd_alphas[0:6],em_alphas[0:9],hud_alphas[0:12];
 reg[26:0] tags[0:20];reg[20:0] missing_tags;
 integer p;
 always @(posedge pixel_clk or negedge pixel_rst_n)begin
  if(!pixel_rst_n)begin
   for(p=0;p<21;p=p+1)tags[p]<=0;
   for(p=0;p<7;p=p+1)begin osd_pixels[p]<=0;osd_alphas[p]<=0;end
   for(p=0;p<10;p=p+1)begin em_pixels[p]<=0;em_alphas[p]<=0;end
   for(p=0;p<13;p=p+1)begin hud_pixels[p]<=0;hud_alphas[p]<=0;end
   for(p=0;p<16;p=p+1)safe_pixels[p]<=0;
   missing_tags<=0;
  end else begin
   tags[0]<={raw_de,raw_hs,raw_vs,raw_x,raw_y};
   for(p=1;p<21;p=p+1)tags[p]<=tags[p-1];
   osd_pixels[0]<=osd_pixel4;osd_alphas[0]<=osd_alpha4;
   em_pixels[0]<=em_pixel4;em_alphas[0]<=em_alpha4;
   hud_pixels[0]<=hud_pixel4;hud_alphas[0]<=hud_alpha4;
   safe_pixels[0]<=safe_pixel4;
   for(p=1;p<7;p=p+1)begin osd_pixels[p]<=osd_pixels[p-1];osd_alphas[p]<=osd_alphas[p-1];end
   for(p=1;p<10;p=p+1)begin em_pixels[p]<=em_pixels[p-1];em_alphas[p]<=em_alphas[p-1];end
   for(p=1;p<13;p=p+1)begin hud_pixels[p]<=hud_pixels[p-1];hud_alphas[p]<=hud_alphas[p-1];end
   for(p=1;p<16;p=p+1)safe_pixels[p]<=safe_pixels[p-1];
   missing_tags[0]<=0;missing_tags[1]<=missing_tags[0];missing_tags[2]<=missing_tags[1];
   missing_tags[3]<=sample_valid&&!rows_ready&&enabled;
   for(p=4;p<21;p=p+1)missing_tags[p]<=missing_tags[p-1];
  end
 end
 wire[15:0] o1,o2,o3;wire ov1,ov2,ov3;
 alpha_blend layer_osd(.clk(pixel_clk),.rst_n(pixel_rst_n),.valid_in(tags[10][26]),
  .front(osd_pixels[6]),.back(cv?adjusted:16'd0),.alpha(osd_alphas[6]),.pixel(o1),.valid_out(ov1));
 v3_constant224_blend #(.EMERGENCY(1)) layer_em(.clk(pixel_clk),.rst_n(pixel_rst_n),.valid_in(ov1),
  .foreground(2'd0),.back(o1),.enabled(em_alphas[9][7]),.pixel(o2),.valid_out(ov2));
 v3_constant224_blend layer_hud(.clk(pixel_clk),.rst_n(pixel_rst_n),.valid_in(ov2),
  .foreground(hud_pixels[12][15]?2'd0:hud_pixels[12][10]?2'd1:2'd2),.back(o2),.enabled(hud_alphas[12][7]),.pixel(o3),.valid_out(ov3));
 wire hard_safe=safe_p2||media_p2||fault_p2||presentation_fault_p||!enabled||missing_tags[19];
 wire[15:0] final565=hard_safe?safe_pixels[15]:o3;
 always @(posedge pixel_clk or negedge pixel_rst_n)begin
  if(!pixel_rst_n)rgb<=0;
  else rgb<=tags[19][26]?{final565[15:11],final565[15:13],final565[10:5],final565[10:9],
                            final565[4:0],final565[4:2]}:24'd0;
 end
 assign {de,hs,vs,x,y}=tags[20];
 reg status_pending;wire status_ready,status_valid;wire[55:0] status;
 always @(posedge pixel_clk or negedge pixel_rst_n)begin
  if(!pixel_rst_n)status_pending<=0;
  else begin if(status_pending&&status_ready)status_pending<=0;
   if(frame_start||media_p2)status_pending<=1;end
 end
 video_cdc_mailbox #(.WIDTH(56)) status_mailbox(
  .src_clk(pixel_clk),.src_rst_n(pixel_rst_n),
  .src_data({pixel_underflows,next_done_toggle,commit_toggle,busy,current,gen,busy,target,target_gen_p}),
  .src_valid(status_pending),.src_ready(status_ready),
  .dst_clk(sys_clk),.dst_rst_n(sys_rst_n),.dst_data(status),
  .dst_valid(status_valid),.dst_ready(1'b1));
 reg old_commit,last_next_done,done_snapshot;
 always @(posedge sys_clk or negedge sys_rst_n)begin
  if(!sys_rst_n)begin pixel_busy_sys<=0;request_outstanding<=0;
   frame_commit<=0;active_slot<=0;generation<=0;
   target_valid<=0;target_slot<=0;target_generation<=0;underflows<=0;old_commit<=0;last_next_done<=0;done_snapshot<=0;end
  else begin frame_commit<=0;
   if(status_valid)begin underflows<=status[55:24];last_next_done<=status[23];frame_commit<=status[22]!=old_commit;
    old_commit<=status[22];pixel_busy_sys<=status[21];active_slot<=status[20:19];generation<=status[18:11];
    target_valid<=status[10];target_slot<=status[9:8];target_generation<=status[7:0];end
   if(status_valid&&status[23]!=done_snapshot&&request_outstanding)request_outstanding<=0;
   if(next_accept)begin request_outstanding<=1;done_snapshot<=last_next_done;end
   if(media_reset||safety_active)request_outstanding<=0;
  end
 end
endmodule

