


`timescale 1ns/1ps
`include "pixel_format_defs.vh"
module tb_safevision_card_display #(parameter integer HD=0,SD_HALF_NS=10,RD_LAT=4,BMP_TOP_DOWN=0);
    localparam integer SCREEN_W=HD?1280:640,SCREEN_PIX=HD?921600:307200;
    localparam integer W = 640;
    localparam integer H = 480;
    localparam integer FRAME_PIX = W*H;
    localparam integer FILE_BYTES = 54 + FRAME_PIX*3;
    localparam integer FILE_SECTORS = (FILE_BYTES + 511)/512;
    localparam integer CLK_HZ = 50_000_000;


    localparam [31:0] VOL_BASE = 32'd16;
    localparam [7:0]  SPC      = 8'd32;
    localparam [15:0] RSVD     = 16'd1;
    localparam [7:0]  NFAT     = 8'd1;
    localparam [31:0] FATSZ    = 32'd2;
    localparam [31:0] TOTSEC   = 32'd8192;
    localparam [31:0] ROOTCLUS = 32'd2;
    localparam [31:0] FILE_CLUS = 32'd3;
    localparam integer FILE_CLUS_N = (FILE_SECTORS + 31)/32;
    localparam [31:0] FILE_CLUS_LAST = FILE_CLUS + FILE_CLUS_N - 1;
    localparam [31:0] VOL_FAT_LBA   = 32'd1;
    localparam [31:0] VOL_ROOT_LBA  = 32'd3;
    localparam [31:0] VOL_FILE0_LBA = 32'd35;

    localparam [31:0] SLOT1_WORD = `SV_IMG1_BASE >> 2;
    localparam [31:0] SLOT0_WORD = `SV_IMG0_BASE >> 2;


    function [23:0] px24;
        input integer x;
        input integer y;
        reg [7:0] red,green,blue;
        begin


            red=x^y;green=x+y;
            blue=(x*3)^(y*5)^((x>>8)<<6)^((y>>8)<<5);
            px24={red,green,blue};
        end
    endfunction

    function [15:0] px565;
        input integer x;
        input integer y;
        reg [23:0] p;
        begin
            p = px24(x, y);
            px565 = { p[23:19], p[15:10], p[7:3] };
        end
    endfunction

    function [23:0] image_mask24(input integer image_id);
      case(image_id)
        1:image_mask24=24'h5a3cc3;
        2:image_mask24=24'ha55aa5;
        3:image_mask24=24'h3cc35a;
        default:image_mask24=0;
      endcase
    endfunction

    function [15:0] image_mask565(input integer image_id);
      case(image_id)
        1:image_mask565=16'h59f8;
        2:image_mask565=16'ha2d4;
        3:image_mask565=16'h3e0b;
        default:image_mask565=0;
      endcase
    endfunction
    reg file_pattern=0;
    reg [7:0] bmp_hdr [0:53];
    initial begin
        integer i;
        for (i = 0; i < 54; i = i + 1) bmp_hdr[i] = 8'h00;
        bmp_hdr[0]  = 8'h42; bmp_hdr[1] = 8'h4D;
        bmp_hdr[2]  = (FILE_BYTES) & 8'hFF;
        bmp_hdr[3]  = (FILE_BYTES >> 8) & 8'hFF;
        bmp_hdr[4]  = (FILE_BYTES >> 16) & 8'hFF;
        bmp_hdr[5]  = (FILE_BYTES >> 24) & 8'hFF;
        bmp_hdr[10] = 54;
        bmp_hdr[14] = 40;
        bmp_hdr[18] = W & 8'hFF;  bmp_hdr[19] = (W >> 8) & 8'hFF;

        bmp_hdr[22] = (BMP_TOP_DOWN ? -H : H) & 8'hFF;
        bmp_hdr[23] = ((BMP_TOP_DOWN ? -H : H) >> 8) & 8'hFF;
        bmp_hdr[24] = ((BMP_TOP_DOWN ? -H : H) >> 16) & 8'hFF;
        bmp_hdr[25] = ((BMP_TOP_DOWN ? -H : H) >> 24) & 8'hFF;
        bmp_hdr[26] = 1;
        bmp_hdr[28] = 24;
        bmp_hdr[34] = (FRAME_PIX*3) & 8'hFF;
        bmp_hdr[35] = ((FRAME_PIX*3) >> 8) & 8'hFF;
        bmp_hdr[36] = ((FRAME_PIX*3) >> 16) & 8'hFF;
        bmp_hdr[37] = ((FRAME_PIX*3) >> 24) & 8'hFF;
    end


    function [7:0] filebyte;
        input integer j;
        input integer image_id;
        integer p, n, c, r, x, y;
        reg [23:0] pxv;
        begin
            if (j < 54) filebyte = bmp_hdr[j];
            else begin
                p = j - 54;
                n = p / 3;
                c = p - n*3;
                r = n / W;
                x = n - r*W;
                y = BMP_TOP_DOWN ? r : H - 1 - r;
                pxv = px24(x, y) ^ image_mask24(image_id) ^ (file_pattern ? 24'hffffff : 24'd0);
                filebyte = (c == 0) ? pxv[7:0] : (c == 1) ? pxv[15:8] : pxv[23:16];
            end
        end
    endfunction


    function [15:0] exp565_k;
        input integer k;
        begin
            exp565_k = px565(k % W, k / W);
        end
    endfunction

    task mbr_set_card0;
        begin
            u_card.sector[450] = 8'h0C;
            u_card.sector[454] = VOL_BASE[7:0];
            u_card.sector[455] = VOL_BASE[15:8];
            u_card.sector[456] = VOL_BASE[23:16];
            u_card.sector[457] = VOL_BASE[31:24];
            u_card.sector[458] = 8'h00;
            u_card.sector[459] = 8'h00;
            u_card.sector[460] = 8'h01;
            u_card.sector[461] = 8'h00;
            u_card.sector[510] = 8'h55;
            u_card.sector[511] = 8'hAA;
        end
    endtask

    task build_volume;
        integer c, s, o, j, image_id, first_cluster, last_cluster, file_lba;
        begin
            u_card.mk_fat32_dbr(16'd512, SPC, RSVD, NFAT, FATSZ, ROOTCLUS, TOTSEC, 1'b1);


            u_card.vol_zero(VOL_FAT_LBA);
            u_card.vol_zero(VOL_FAT_LBA+1);
            u_card.vol_set_le(VOL_FAT_LBA, 16'd8, 32'h0FFF_FFFF, 3'd4);

            u_card.vol_zero(VOL_ROOT_LBA);
            u_card.mk_dir_entry(VOL_ROOT_LBA, 16'd0,  "SV0001  BMP", 8'h20, FILE_CLUS, FILE_BYTES);
            u_card.mk_dir_entry(VOL_ROOT_LBA, 16'd32, "SV0002  BMP", 8'h20, FILE_CLUS+FILE_CLUS_N, FILE_BYTES);
            u_card.mk_dir_entry(VOL_ROOT_LBA, 16'd64, "SV0003  BMP", 8'h20, FILE_CLUS+2*FILE_CLUS_N, FILE_BYTES);
            u_card.mk_dir_entry(VOL_ROOT_LBA, 16'd96, "SV0004  BMP", 8'h20, FILE_CLUS+3*FILE_CLUS_N, FILE_BYTES);
            for(image_id=0;image_id<4;image_id=image_id+1)begin
            first_cluster=FILE_CLUS+image_id*FILE_CLUS_N;
            last_cluster=first_cluster+FILE_CLUS_N-1;
            file_lba=VOL_FILE0_LBA+image_id*FILE_CLUS_N*SPC;
            for(c=first_cluster;c<last_cluster;c=c+1)
                u_card.vol_set_le(VOL_FAT_LBA+c/128,(c%128)*4,c+1,3'd4);
            u_card.vol_set_le(VOL_FAT_LBA+last_cluster/128,(last_cluster%128)*4,32'h0FFF_FFFF,3'd4);


            for (s = 0; s < FILE_SECTORS; s = s + 1) begin
                u_card.vol_used[file_lba + s] = 1'b1;
                for (o = 0; o < 512; o = o + 1) begin
                    j = s*512 + o;
                    u_card.vol[(file_lba + s)*512 + o] = (j < FILE_BYTES) ? filebyte(j,image_id) : 8'h00;
                end
            end
            end
            mbr_set_card0;
        end
    endtask


 reg clk=0;always #(SD_HALF_NS) clk=~clk;
 reg rst_n=0,btn_next=1,btn_auto=1;
 wire sd_ncs,sd_dclk,sd_mosi,sd_miso,uart_txd;
 wire [3:0] led;wire d0,d1,d2,dc,scl;tri1 sda;
 safevision_top #(.HD(HD),.PLAYER_SPI_FAST_DIV(0),.FONT_FILE("font8x16.mem"),.PLAYER_SPI_INIT_DIV(1)) dut(
 .clk(clk),.rst_n(rst_n),.btn_next(btn_next),.btn_auto(btn_auto),.btn_emergency(1'b1),.uart_txd(uart_txd),.led(led),
 .sd_ncs(sd_ncs),.sd_dclk(sd_dclk),.sd_mosi(sd_mosi),.sd_miso(sd_miso),
 .HDMI_D0_P(d0),.HDMI_D1_P(d1),.HDMI_D2_P(d2),.HDMI_CLK_P(dc),
 .HDMI_DDC_SCL(scl),.HDMI_DDC_SDA(sda));
 defparam dut.memory_ip.RD_LAT=RD_LAT;
 sd_spi_card_model #(.VOL_BASE(VOL_BASE),.VOL_SECTORS(8192)) u_card(
 .sclk(sd_dclk),.cs_n(sd_ncs),.mosi(sd_mosi),.miso(sd_miso),.i_dead(1'b0),
 .o_cmd(),.o_arg(),.o_acmd41_arg(),.o_cmd_cnt(),.o_acmd41_cnt(),.o_cmd_valid());
 integer errors=0,checks=0;reg test_done=0;
 task check(input bit cond,input string name);
 begin checks=checks+1;if(cond)$display("[PASS] %s",name);
 else begin errors=errors+1;$display("[FAIL] %s",name);end end endtask
 function [23:0] rgb565(input [15:0] p);
 begin rgb565={{p[15:11],p[15:13]},{p[10:5],p[10:9]},{p[4:0],p[4:2]}};end endfunction
 integer publish_count=0,unsafe_publish=0,active_writes=0;
 reg pub_d=0;
 always @(posedge dut.mem_clk)if(dut.mem_rst_n)begin
   if(dut.publish_toggle!=pub_d)begin
     publish_count=publish_count+1;


     if(dut.adapter.wcnt!=0||dut.app_wr_en||dut.prod_wr_busy||
        dut.adapter.state==1||dut.adapter.state==2)unsafe_publish=unsafe_publish+1;
   end
   pub_d=dut.publish_toggle;
   if(dut.app_wr_en&&dut.app_wr_dm!=15&&dut.active)begin
     if(dut.app_wr_addr>=SLOT1_WORD&&dut.app_wr_addr<SLOT1_WORD+FRAME_PIX/2&&
        dut.core.display.pix_active_slot==1)active_writes=active_writes+1;
     if(dut.app_wr_addr<FRAME_PIX/2&&dut.core.display.pix_active_slot==0)
       active_writes=active_writes+1;
   end
 end
 integer media_k,screen_x,screen_y;
 integer full_frames=0,new_slot_frames=0,axis_k=0,pixel_bad=0,tag_bad=0;
 integer image_frames[0:3];integer image_n;
 reg axis_slot=0;reg [7:0] axis_generation=0;reg injecting_fault=0,recovered_epoch=0;
 reg compare_axis=0;
 always @(posedge dut.mem_clk)if(dut.mem_rst_n&&dut.integrity_fault&&!injecting_fault)
   $fatal(1,"unexpected source/readback integrity fault: words=%0d blocks=%0d bad=%08x expected=%08x actual=%08x direction=%b",dut.integrity_words,dut.integrity_blocks,dut.integrity_bad_addr,dut.integrity_expected,dut.integrity_actual,dut.integrity_top_down);
 always @(posedge dut.pixel_clk)if(dut.pixel_rst_n&&dut.active&&!injecting_fault&&
    (dut.underflows!=0||dut.overflows!=0||dut.frame_fault))
   $fatal(1,"healthy playback failed: HD=%0d RD_LAT=%0d U=%0d O=%0d fault=%b",HD,RD_LAT,dut.underflows,dut.overflows,dut.frame_fault);
 reg [15:0] expected_p;reg [23:0] expected_rgb;
 always @(posedge dut.pixel_clk)if(dut.axis_valid&&dut.axis_ready)begin
   if(dut.axis_user)begin
     if(compare_axis&&axis_k!=SCREEN_PIX)tag_bad=tag_bad+1;
     compare_axis=dut.active&&!dut.frame_fault&&!dut.safety_active&&!injecting_fault;axis_k=0;
     axis_slot=dut.core.display.pix_active_slot[0];axis_generation=dut.core.display.pix_generation;
   end
   if(compare_axis)begin
     if(axis_k>=SCREEN_PIX)tag_bad=tag_bad+1;
     else begin
       screen_x=axis_k%SCREEN_W;screen_y=axis_k/SCREEN_W;
       if(!HD||(screen_x>=320&&screen_x<960&&screen_y>=120&&screen_y<600))begin
         media_k=HD?(screen_y-120)*640+(screen_x-320):axis_k;
         expected_p=exp565_k(media_k)^image_mask565((axis_generation+3)&3);
         if(!(axis_slot&&axis_generation==1&&!recovered_epoch))expected_p=~expected_p;
         expected_rgb=rgb565(expected_p);
       end else expected_rgb=0;
       if(dut.axis_data!==expected_rgb)begin
         if(pixel_bad<4)$display("[DIAG] AXIS pixel=%0d got=%06x expected=%06x",axis_k,dut.axis_data,expected_rgb);
         pixel_bad=pixel_bad+1;
       end
       if(dut.axis_last!==((axis_k%SCREEN_W)==SCREEN_W-1))tag_bad=tag_bad+1;
     end
     axis_k=axis_k+1;
     if(axis_k==SCREEN_PIX)begin full_frames=full_frames+1;compare_axis=0;
       image_frames[(axis_generation+3)&3]=image_frames[(axis_generation+3)&3]+1;
       if(!axis_slot)new_slot_frames=new_slot_frames+1;
       $display("[TB] checked full display frame %0d (%0d pixels), underflows=%0d",full_frames,SCREEN_PIX,dut.underflows);end
   end
 end
 task cmp_mem(input integer base,input integer image_id,input bit inverted,input string name);
 integer j,bad;reg [31:0] expected;
 begin bad=0;for(j=0;j<FRAME_PIX/2;j=j+1)begin
   expected={exp565_k(j*2+1)^image_mask565(image_id),exp565_k(j*2)^image_mask565(image_id)};
   if(inverted)expected=~expected;
   if(dut.memory_ip.mem[base+j]!==expected)begin
     if(bad==0)$display("[DIAG] memory word=%0d got=%08x expected=%08x",j,dut.memory_ip.mem[base+j],expected);
     bad=bad+1;
   end
 end check(bad==0,name);end endtask
 integer before_frames,auto_count;
 reg [31:0] previous_underflows=0;
 always @(posedge dut.pixel_clk)if(dut.underflows!=previous_underflows)begin
   previous_underflows<=dut.underflows;
   $display("[UNDERFLOW] t=%0t fifo=%0d active=%b dma_state=%0d issued=%0d drained=%0d req=%b busy=%b ch=%0d hw=%0d wbuf=%0d wm=%0d critical=%b",$time,dut.display_fifo_level,dut.display_dma_active,dut.core.display.fetch.checked_read.dma.read_state,dut.core.display.fetch.checked_read.dma.issued_words,dut.core.display.fetch.checked_read.dma.drained_words,dut.core.rd_req,dut.core.rd_busy,dut.core.arbiter.cur_ch,dut.adapter.state,dut.adapter.wcnt,dut.core.arbitration_level,dut.core.arbiter.video_critical);
 end
 initial begin
   for(image_n=0;image_n<4;image_n=image_n+1)image_frames[image_n]=0;
   forever begin #50000000;
     if(rst_n)$display("[PROGRESS] card t=%0t player=%0d sink=%0d source=%0d blocks=%0d gfault=%b vCRC=%b frames=%0d",$time,dut.pl_state,dut.sk_state,dut.integrity_words,dut.integrity_blocks,dut.integrity_fault,dut.playback_fault,dut.pl_frame_cnt);
   end
 end
 initial begin
   check(px24(7,11)===24'h0c1222&&px24(0,1)===24'h010105&&
         px24(255,255)===24'h00fe06,
         "independent 8-bit RGB pattern samples include x/y and all channels");
   check(px565(0,0)!=px565(256,0)&&px565(256,0)!=px565(512,0)&&
         px565(0,0)!=px565(0,256),
         "row/column high bits remain distinct after RGB565 quantization");
   #1;build_volume;repeat(20)@(negedge clk);rst_n=1;
   wait(dut.pl_card_usable);check(dut.pl_file_cnt==4&&dut.pl_cur_file==0,"FAT32 indexed four distinct files and selected index 0");
   wait(dut.pl_frame_cnt==1);check(dut.card_mode,"card owns producer after first frame");
   check(dut.sk_frame_ok,"first frame CRC accepted after memory drain and swap");
   cmp_mem(SLOT1_WORD,0,0,"slot 1 has all 153600 correct words in raster order from signed BMP height");
   wait(full_frames>=2);
   check(pixel_bad==0&&tag_bad==0,"two full BASE/720p AXIS frames: RGB and SOF/EOL pixel-exact");
   before_frames=full_frames;


   file_pattern=1;build_volume;
   @(negedge clk);btn_next=0;repeat(70000)@(negedge clk);btn_next=1;
   wait(dut.pl_frame_cnt==2);
   check(dut.pl_cur_file==1,"next button selects the distinct second file");
   cmp_mem(SLOT0_WORD,1,1,"slot 0 has all 153600 correct words after next-button frame");
   wait(new_slot_frames>=2);
   check(dut.pl_fail_stage==0&&dut.sk_ec==0,"no player or sink error on two physical-rate card frames");
   check(publish_count==2&&unsafe_publish==0,"exactly two frame events, both after physical write drain");
   check(active_writes==0,"displayed slot never overwritten by card producer");
   check(dut.underflows==0&&dut.overflows==0&&!dut.frame_fault,"no display underflow, FIFO overflow or frame fault");
   check(pixel_bad==0&&tag_bad==0,"all accepted active-frame pixels and line markers match");
   check(!dut.hdmi_backpressure,"no HDMI queue overflow");
   check(dut.memory_ip.protocol_errors==0,"strict SDRAM application burst contract respected");
   @(negedge clk);btn_auto=0;
   wait(dut.pl_frame_cnt>=3);
   check(dut.pl_cur_file==2,"automatic mode selects the third file across two FAT sectors");
   cmp_mem(SLOT1_WORD,2,1,"third file has all 153600 distinct correct words");
   @(negedge clk);btn_auto=1;
   wait(!dut.btn_auto_db);
   wait(dut.pl_frame_cnt>=4 && dut.pl_state==7);
   check(dut.pl_cur_file==3,"automatic mode selects the distinct fourth file");
   cmp_mem(SLOT0_WORD,3,1,"fourth file has all 153600 distinct correct words");
   wait(image_frames[2]>=2&&image_frames[3]>=2);
   check(dut.pl_frame_cnt>=4&&!dut.integrity_fault&&!dut.playback_fault,"two additional automatic frames pass readback and playback CRC");
   check(dut.underflows==0&&dut.overflows==0&&pixel_bad==0&&tag_bad==0,"automatic swaps retain exact pixels and no underflow");
   check(publish_count>=4&&unsafe_publish==0&&active_writes==0,"automatic mode preserves inactive-slot ownership and publication barriers");


   injecting_fault=1;compare_axis=0;
   auto_count=(dut.core.display.pix_active_slot==1)?SLOT1_WORD:0;
   dut.memory_ip.mem[auto_count+7]=dut.memory_ip.mem[auto_count+7]^32'h00010000;
   wait(dut.playback_fault);
   check(dut.playback_bad_addr==auto_count*4,"runtime fault reports first corrupt block byte address");
   wait(dut.safety_active&&dut.safety_level==2);
   check(!dut.tx_reset&&!dut.hdmi_backpressure,"runtime CRC fault switches to red Exit without resetting HDMI");


   @(negedge clk);rst_n=0;recovered_epoch=1;repeat(100)@(negedge clk);rst_n=1;
   wait(dut.pl_frame_cnt==1);
   check(dut.integrity_pass&&!dut.integrity_fault&&!dut.playback_fault&&dut.sk_frame_ok,"common reset recovers by re-verifying the new complete image");


   before_frames=full_frames;injecting_fault=0;
   wait(full_frames>=before_frames+2);
   check(pixel_bad==0&&tag_bad==0,"two complete post-reset frames have exact RGB and SOF/EOL");
   check(dut.underflows==0&&dut.overflows==0&&!dut.frame_fault&&!dut.safety_active,
         "post-reset normal playback stays healthy after runtime memory corruption");
   check(unsafe_publish==0&&active_writes==0&&dut.memory_ip.protocol_errors==0,
         "ownership and physical memory contract remain valid across reset");
   $display("CARD DISPLAY HD=%0d SD_HALF_NS=%0d RD_LAT=%0d TOP_DOWN=%0d checks=%0d errors=%0d checked_frames=%0d post_reset_frames=%0d distinct_images=4 write_bursts=%0d read_bursts=%0d publishes=%0d undrained_publishes=%0d",HD,SD_HALF_NS,RD_LAT,BMP_TOP_DOWN,checks,errors,full_frames,full_frames-before_frames,dut.memory_ip.write_bursts,dut.memory_ip.read_bursts,publish_count,unsafe_publish);
   if(errors)$fatal(1,"CARD DISPLAY FAILED");
   test_done=1;$display("[PASS] CARD DISPLAY PASS");$finish;
 end
 initial begin #(64'd8000000000);$fatal(1,"CARD DISPLAY watchdog: player=%0d ec=%02x sink=%0d px=%0d frames=%0d active=%b fault=%b",dut.pl_state,dut.pl_ec,dut.sk_state,dut.sk_px_written,dut.pl_frame_cnt,dut.active,dut.frame_fault);end
endmodule
