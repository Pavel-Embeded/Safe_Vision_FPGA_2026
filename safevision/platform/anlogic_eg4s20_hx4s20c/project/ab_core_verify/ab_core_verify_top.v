


`ifndef AB_CORE_HD
`define AB_CORE_HD 0
`endif
module ab_core_verify_top(
 input wire sys_clk,mem_clk,pixel_clk,rst_n,control_bit,control_shift,submit,
 output wire [23:0] rgb,output wire hsync,vsync,de,pixel_valid,
 output wire [31:0] mem_probe,pixel_probe,output wire cfg_ready
);
 reg [59:0] control;
 always @(posedge sys_clk or negedge rst_n)
   if(!rst_n)control<=0;else if(control_shift)control<={control[58:0],control_bit};
 reg [19:0] mem_count;reg [2:0] valid_pipe;reg [31:0] addr_pipe0,addr_pipe1,response;
 reg [23:0] mem_control;
 wire mr,mw;wire [31:0] ma,md;wire [3:0] strobe;
 wire wr_req,wr_ack,wr_done,wr_crc,wr_error,writer_ready;
 wire [31:0] wr_addr,wr_data;wire [15:0] wr_len,wr_crc_value;wire [18:0] written;
 always @(posedge mem_clk or negedge rst_n)begin
  if(!rst_n)begin mem_count<=0;mem_control<=0;valid_pipe<=0;addr_pipe0<=0;addr_pipe1<=0;response<=0;end
  else begin
   if(control_shift)mem_control<={mem_control[22:0],control_bit};
   if(writer_ready && mem_control[1])mem_count<=mem_count+1'b1;
   valid_pipe<={valid_pipe[1:0],mr&&!mw};addr_pipe0<=ma;addr_pipe1<=addr_pipe0;
   if(valid_pipe[1])response<=addr_pipe1^32'h7c00a5ff;
  end
 end
 bmp_frame_write_bridge writer(.clk(mem_clk),.rst_n(rst_n),.start(mem_control[0]),
   .top_down(mem_control[2]),.slot_sel(mem_control[4:3]),.slot_base({12'd0,mem_control[23:6],2'd0}),
   .din(mem_count[15:0]),.din_valid(mem_control[1]),.din_ready(writer_ready),
   .wr_req(wr_req),.wr_addr(wr_addr),.wr_data(wr_data),.wr_len(wr_len),.wr_ready(wr_ack),
   .wr_done(wr_done),.slot_valid(),.crc_ok(wr_crc),.crc_value(wr_crc_value),.px_cnt(written),
   .wr_error(wr_error),.err_code(),.err_detail());
 wire [15:0] level,wr_starve,rd_starve;wire cmt,se;
 wire [11:0] sx,sy,x,y;wire sde,sfs;wire [1:0] layer,slot;wire [7:0] gen;
 wire [31:0] underflows,missed,overflows,bytes;wire fault,active,fi;wire [2:0] phase;
 safevision_core #(.HD(`AB_CORE_HD)) core(
  .sys_clk(sys_clk),.mem_clk(mem_clk),.pixel_clk(pixel_clk),.rst_n(rst_n),
  .frame_ready(submit),.wr_frame_index(control[1]),.wr_slot_id(control[3:2]),
  .wr_generation(control[11:4]),.wr_crc_ok(control[12]),
  .active_commit(cmt),.active_next(),.generation_next(),.frame_index_next(),.swap_error(se),.swap_state_o(),
  .frame_start_evt_b(),.swap_ack_evt_b(),
  .wr_req(wr_req),.wr_addr(wr_addr),.wr_data(wr_data),.wr_len(wr_len),.wr_ack(wr_ack),.wr_busy(),
  .sd_req(mem_control[5]),.sd_wr(mem_control[6]),.sd_addr({12'd0,mem_control[23:6],2'd0}),
  .sd_wdata({8'd0,mem_control}),.sd_len(16'd1),.sd_ack(),.sd_busy(),.sd_rdata(),.sd_rdata_valid(),
  .mem_req(mr),.mem_wr(mw),.mem_addr(ma),.mem_wdata(md),.mem_wstrb(strobe),
  .mem_ready(1'b1),.mem_rdata(response),.mem_rdata_valid(valid_pipe[2]),
  .wr_starve_cnt(wr_starve),.rd_starve_cnt(rd_starve),
  .cfg_valid(submit),.cfg_ready(cfg_ready),.cfg_osd_enable(control[59]),.cfg_mode(control[58:57]),.cfg_fps_tens(control[56:53]),.cfg_fps_ones(control[52:49]),.cfg_sd_ok(control[48]),.cfg_origin_x(control[47:36]),.cfg_origin_y(control[35:24]),.cfg_foreground(control[23:0]),
  .emergency_rgb({sx,sy}),.emergency_valid(sde&&sx[5:0]==6'd31),.scan_x(sx),.scan_y(sy),.scan_de(sde),.scan_frame_start(sfs),
  .rgb(rgb),.x(x),.y(y),.hsync(hsync),.vsync(vsync),.de(de),.pixel_valid(pixel_valid),.line_start(),.frame_start(),.active_frame_start(),.hblank(),.vblank(),.selected_layer(layer),
  .pix_active_slot(slot),.pix_generation(gen),.pix_frame_index(fi),.pix_active_valid(active),.pix_frame_fault(fault),.pix_underflow_count(underflows),.pix_missed_frame_count(missed),.mem_overflow_count(overflows),.mem_fifo_pixels(level),.mem_dma_bytes(bytes),.mem_dma_active(),.mem_dma_done(),.mem_fetch_state(phase));
 assign mem_probe=bytes^overflows^{wr_starve,rd_starve}^md^{wr_crc_value,12'd0,wr_crc,wr_done,wr_error,se}^{13'd0,written};
 assign pixel_probe=underflows^missed^{x,y,slot,layer,active,fault,fi,gen[0]};
endmodule
