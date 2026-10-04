// Internal implementation probe for stages1-15. Independent clock inputs allow
// worst-case 100/125/25.175 or74.25MHz analysis without changing B's board top.
// No board pinout/SDRAM pad timing/HDMI serializer is claimed by this probe.
`ifndef A_DISPLAY_HD
`define A_DISPLAY_HD 0
`endif
module a_display_verify_top(
 input wire sys_clk,mem_clk,pixel_clk,rst_n,control_bit,control_shift,submit,
 output wire [23:0] rgb,output wire hsync,vsync,de,pixel_valid,
 output wire [31:0] mem_probe,pixel_probe,output wire cfg_ready
);
 reg [59:0] control;
 always @(posedge sys_clk or negedge rst_n)
   if(!rst_n)control<=0;else if(control_shift)control<={control[58:0],control_bit};
 wire rr;wire [31:0] ra,rd;wire [15:0] len,level;reg ack,busy,data_valid;
 reg [15:0] remain;reg [31:0] addr,response;
 // In-domain registered burst responder solely keeps every A data path live.
 always @(posedge mem_clk or negedge rst_n)begin
  if(!rst_n)begin ack<=0;busy<=0;remain<=0;addr<=0;response<=0;data_valid<=0;end
  else begin
   ack<=0;data_valid<=0;
   if(!busy&&rr)begin ack<=1;busy<=1;remain<=len;addr<=ra;end
   else if(busy)begin
    response<={addr[15:0]^16'h4567,addr[15:0]^16'h1234};data_valid<=1;addr<=addr+4;
    remain<=remain-1'b1;if(remain==1)busy<=0;
   end
  end
 end
 wire [11:0] sx,sy,x,y;wire sde,sfs;wire [1:0] layer,slot;wire [7:0] gen;
 wire [31:0] underflows,missed,overflows,bytes;wire fault,active,fi;wire [2:0] phase;
 a_video_display_core #(.HD(`A_DISPLAY_HD)) core(
  .sys_clk(sys_clk),.mem_clk(mem_clk),.pixel_clk(pixel_clk),.rst_n(rst_n),
  .swap_req_b(control[0]),.mb_frame_index_b(control[1]),.mb_slot_id_b(control[3:2]),.mb_generation_b(control[11:4]),.mb_crc_ok_b(control[12]),.frame_start_evt_b(),.swap_ack_evt_b(),
  .rd_req(rr),.rd_addr(ra),.rd_len(len),.rd_ack(ack),.rd_busy(busy),.rd_data(response),.rd_data_valid(data_valid),
  .cfg_valid(submit),.cfg_ready(cfg_ready),.cfg_osd_enable(control[59]),.cfg_mode(control[58:57]),.cfg_fps_tens(control[56:53]),.cfg_fps_ones(control[52:49]),.cfg_sd_ok(control[48]),.cfg_origin_x(control[47:36]),.cfg_origin_y(control[35:24]),.cfg_foreground(control[23:0]),
  .emergency_rgb({sx,sy}),.emergency_valid(sde&&sx[5:0]==6'd31),.scan_x(sx),.scan_y(sy),.scan_de(sde),.scan_frame_start(sfs),
  .rgb(rgb),.x(x),.y(y),.hsync(hsync),.vsync(vsync),.de(de),.pixel_valid(pixel_valid),.line_start(),.frame_start(),.active_frame_start(),.hblank(),.vblank(),.selected_layer(layer),
  .pix_active_slot(slot),.pix_generation(gen),.pix_frame_index(fi),.pix_active_valid(active),.pix_frame_fault(fault),.pix_underflow_count(underflows),.pix_missed_frame_count(missed),.mem_overflow_count(overflows),.mem_fifo_pixels(level),.mem_dma_bytes(bytes),.mem_dma_active(),.mem_dma_done(),.mem_fetch_state(phase));
 assign mem_probe=bytes^overflows^{13'd0,phase,level};
 assign pixel_probe=underflows^missed^{x,y,slot,layer,active,fault,fi,gen[0]};
endmodule
