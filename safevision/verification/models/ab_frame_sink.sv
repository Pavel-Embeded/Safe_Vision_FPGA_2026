`timescale 1ns/1ps
`include "pixel_format_defs.vh"


module ab_frame_sink(
    input wire mem_clk,rst_n,start,top_down,input wire [15:0] pixel,
    input wire pixel_valid,output wire pixel_ready,input wire [9:0] pixel_x,pixel_y,
    output reg done=0,output reg [31:0] errors=0
);
    reg sys_clk=0,pixel_clk=0;
    always #5 sys_clk=~sys_clk;
    always #19.861 pixel_clk=~pixel_clk;
    wire wr_req,wr_ack,wr_done,crc_ok,wr_error;
    wire [31:0] wr_addr,wr_data;wire [15:0] wr_len;
    wire [3:0] slot_valid;wire [18:0] px_cnt;
    bmp_frame_write_bridge writer(.clk(mem_clk),.rst_n(rst_n),.start(start),.top_down(top_down),
      .slot_sel(2'd1),.slot_base(`SV_IMG1_BASE),.din(pixel),.din_valid(pixel_valid),
      .din_ready(pixel_ready),.wr_req(wr_req),.wr_addr(wr_addr),.wr_data(wr_data),
      .wr_len(wr_len),.wr_ready(wr_ack),.wr_done(wr_done),.slot_valid(slot_valid),
      .crc_ok(crc_ok),.crc_value(),.px_cnt(px_cnt),.wr_error(wr_error),.err_code(),.err_detail());
    reg submit_pending=0;
    wire submit_ready,frame_ready;
    wire [11:0] payload;
    always @(posedge mem_clk or negedge rst_n)
      if(!rst_n)submit_pending<=0;
      else begin
        if(submit_pending && submit_ready)submit_pending<=0;
        if(wr_done && crc_ok && slot_valid[1])submit_pending<=1;
      end
    video_cdc_mailbox #(.WIDTH(12)) submit(
      .src_clk(mem_clk),.src_rst_n(rst_n),.src_data({1'b0,2'd1,8'h21,1'b1}),
      .src_valid(submit_pending),.src_ready(submit_ready),
      .dst_clk(sys_clk),.dst_rst_n(rst_n),.dst_data(payload),
      .dst_valid(frame_ready),.dst_ready(1'b1));
    wire mem_req,mem_wr;wire [31:0] mem_addr,mem_wdata;wire [3:0] mem_wstrb;
    reg mem_ready=0;reg [31:0] mem_rdata=0;reg mem_rdata_valid=0;
    reg [31:0] memory[0:1048575];
    reg [15:0] expected[0:307199];
    integer received=0,cycles=0;
    reg [31:0] address_pipe[0:2];reg [2:0] valid_pipe=0;
    always @(posedge mem_clk)begin
      if(!rst_n)begin mem_ready<=0;valid_pipe<=0;mem_rdata_valid<=0;end
      else begin
        cycles<=cycles+1;mem_ready<=cycles%17!=0;
        address_pipe[0]<=mem_addr;address_pipe[1]<=address_pipe[0];address_pipe[2]<=address_pipe[1];
        valid_pipe<={valid_pipe[1:0],mem_req && mem_ready && !mem_wr};
        mem_rdata_valid<=valid_pipe[2];
        if(valid_pipe[2])mem_rdata<=memory[address_pipe[2][21:2]];
        if(mem_req && mem_ready && mem_wr)begin
          if(mem_wstrb!==4'hf)$fatal(1,"partial frame write");
          memory[mem_addr[21:2]]<=mem_wdata;
        end
        if(pixel_valid && pixel_ready)begin
          if(pixel_x>=640 || pixel_y>=480)$fatal(1,"source pixel coordinate");
          expected[pixel_y*640+pixel_x]=pixel;received=received+1;
        end
        if(wr_error)$fatal(1,"B frame writer error during card/display integration");
      end
    end
    wire [23:0] rgb;wire [11:0] x,y;wire de,pv,active,fault,fs,ack,cmt,swap_error;
    wire [31:0] underflows,overflows;
    safevision_core #(.FONT_FILE("font8x16.mem")) core(
      .sys_clk(sys_clk),.mem_clk(mem_clk),.pixel_clk(pixel_clk),.rst_n(rst_n),
      .frame_ready(frame_ready),.wr_frame_index(payload[11]),.wr_slot_id(payload[10:9]),
      .wr_generation(payload[8:1]),.wr_crc_ok(payload[0]),
      .active_commit(cmt),.active_next(),.generation_next(),.frame_index_next(),
      .swap_error(swap_error),.swap_state_o(),.frame_start_evt_b(fs),.swap_ack_evt_b(ack),
      .wr_req(wr_req),.wr_addr(wr_addr),.wr_data(wr_data),.wr_len(wr_len),.wr_ack(wr_ack),.wr_busy(),
      .sd_req(1'b0),.sd_wr(1'b0),.sd_addr(32'd0),.sd_wdata(32'd0),.sd_len(16'd0),
      .sd_ack(),.sd_busy(),.sd_rdata(),.sd_rdata_valid(),
      .mem_req(mem_req),.mem_wr(mem_wr),.mem_addr(mem_addr),.mem_wdata(mem_wdata),
      .mem_wstrb(mem_wstrb),.mem_ready(mem_ready),.mem_rdata(mem_rdata),.mem_rdata_valid(mem_rdata_valid),
      .wr_starve_cnt(),.rd_starve_cnt(),
      .cfg_valid(1'b0),.cfg_ready(),.cfg_osd_enable(1'b0),.cfg_mode(2'd0),
      .cfg_fps_tens(4'd6),.cfg_fps_ones(4'd0),.cfg_sd_ok(1'b1),
      .cfg_origin_x(12'd0),.cfg_origin_y(12'd0),.cfg_foreground(24'hffffff),
      .emergency_rgb(24'd0),.emergency_valid(1'b0),
      .scan_x(),.scan_y(),.scan_de(),.scan_frame_start(),
      .rgb(rgb),.x(x),.y(y),.hsync(),.vsync(),.de(de),.pixel_valid(pv),
      .line_start(),.frame_start(),.active_frame_start(),.hblank(),.vblank(),
      .selected_layer(),.pix_active_slot(),.pix_generation(),.pix_frame_index(),
      .pix_active_valid(active),.pix_frame_fault(fault),.pix_underflow_count(underflows),
      .pix_missed_frame_count(),.mem_overflow_count(overflows),.mem_fifo_pixels(),
      .mem_dma_bytes(),.mem_dma_active(),.mem_dma_done(),.mem_fetch_state());
    function [23:0] expand565(input [15:0] p);
      expand565={p[15:11],p[15:13],p[10:5],p[10:9],p[4:0],p[4:2]};
    endfunction
    integer compared=0,commits=0,acks=0;
    always @(posedge sys_clk)begin
      if(rst_n && cmt)commits=commits+1;
      if(rst_n && ack)acks=acks+1;
    end
    always @(posedge pixel_clk)begin
      if(rst_n && active && de && !done)begin
        if(x>=640 || y>=480 || !pv || rgb!==expand565(expected[y*640+x]))begin
          errors=errors+1;
          if(errors<5)$display("[FAIL] card/display pixel x=%0d y=%0d got=%h",x,y,rgb);
        end
        compared=compared+1;
        if(compared==307200)begin
          if(received!=307200 || px_cnt!=307200 || commits!=1 || acks!=1 ||
             underflows!=0 || overflows!=0 || fault || swap_error)errors=errors+1;
          $display("[DISPLAY] received=%0d compared=%0d errors=%0d commits=%0d acks=%0d underflow=%0d overflow=%0d",
            received,compared,errors,commits,acks,underflows,overflows);
          done=1;
        end
      end
    end

    initial if($test$plusargs("WAVES"))begin
      wait(submit_pending);
      $dumpfile("card_display.vcd");
      $dumpvars(0,submit_pending,frame_ready,fs,ack,cmt,active,x,y,de,pv,rgb);
      wait(compared>=640);$dumpoff;
    end
endmodule
