// Complete synthesized board RTL with a true 50/100/125/25.185 MHz clock set.
// SD card: real BMP byte stream in a synthetic FAT32 volume. FIFO: actual
// vendor ERAM/FIFO Verilog. Memory: strict application contract model, not AC.
// HDMI: vendor core/PHY contract stubs; pixel checks stop at accepted AXIS data.
`timescale 1ns/1ps
`include "pixel_format_defs.vh"
module tb_safevision_card_display;
    localparam integer W = 640;
    localparam integer H = 480;
    localparam integer FRAME_PIX = W*H;                       // 307200
    localparam integer FILE_BYTES = 54 + FRAME_PIX*3;         // 921654
    localparam integer FILE_SECTORS = (FILE_BYTES + 511)/512; // 1801
    localparam integer CLK_HZ = 50_000_000;

    // 卷几何（与 tb_card_to_screen 同布局）
    localparam [31:0] VOL_BASE = 32'd16;
    localparam [7:0]  SPC      = 8'd32;
    localparam [15:0] RSVD     = 16'd1;
    localparam [7:0]  NFAT     = 8'd1;
    localparam [31:0] FATSZ    = 32'd1;
    localparam [31:0] TOTSEC   = 32'd2048;
    localparam [31:0] ROOTCLUS = 32'd2;
    localparam [31:0] FILE_CLUS = 32'd3;
    localparam integer FILE_CLUS_N = (FILE_SECTORS + 31)/32;  // 57
    localparam [31:0] FILE_CLUS_LAST = FILE_CLUS + FILE_CLUS_N - 1;  // 59
    localparam [31:0] VOL_FAT_LBA   = 32'd1;
    localparam [31:0] VOL_ROOT_LBA  = 32'd2;
    localparam [31:0] VOL_FILE0_LBA = 32'd34;

    localparam [31:0] SLOT1_WORD = `SV_IMG1_BASE >> 2;        // 163840
    localparam [31:0] SLOT0_WORD = `SV_IMG0_BASE >> 2;        // 0

    // ---------------------------------------------------------------- 期望值
    // ★ 唯一真相：写卡用它、算期望也用它
    function [23:0] px24;
        input integer x;
        input integer y;
        reg [7:0] red,green,blue;
        begin
            // Narrow EACH channel before concatenation. An unsized multiply
            // inside a concat silently discarded R/G in the old test pattern.
            // Every channel varies in x and y, so row order and channel order
            // are independently visible to the memory and AXIS scoreboards.
            // Mix coordinate high bits into visible RGB565 blue bits too;
            // otherwise a +256 row/column error could repeat the same color.
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

    reg file_pattern=0;
    reg [7:0] bmp_hdr [0:53];
    initial begin
        integer i;
        for (i = 0; i < 54; i = i + 1) bmp_hdr[i] = 8'h00;
        bmp_hdr[0]  = 8'h42; bmp_hdr[1] = 8'h4D;                 // "BM"
        bmp_hdr[2]  = (FILE_BYTES) & 8'hFF;
        bmp_hdr[3]  = (FILE_BYTES >> 8) & 8'hFF;
        bmp_hdr[4]  = (FILE_BYTES >> 16) & 8'hFF;
        bmp_hdr[5]  = (FILE_BYTES >> 24) & 8'hFF;
        bmp_hdr[10] = 54;                                        // bfOffBits
        bmp_hdr[14] = 40;                                        // biSize
        bmp_hdr[18] = W & 8'hFF;  bmp_hdr[19] = (W >> 8) & 8'hFF;
        bmp_hdr[22] = H & 8'hFF;  bmp_hdr[23] = (H >> 8) & 8'hFF; // +480 ⇒ 自底向上
        bmp_hdr[26] = 1;                                         // biPlanes
        bmp_hdr[28] = 24;                                        // biBitCount
        bmp_hdr[34] = (FRAME_PIX*3) & 8'hFF;
        bmp_hdr[35] = ((FRAME_PIX*3) >> 8) & 8'hFF;
        bmp_hdr[36] = ((FRAME_PIX*3) >> 16) & 8'hFF;
        bmp_hdr[37] = ((FRAME_PIX*3) >> 24) & 8'hFF;
    end

    // 卡上文件第 j 个字节（行序自底向上，通道 B,G,R）
    function [7:0] filebyte;
        input integer j;
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
                y = H - 1 - r;
                pxv = px24(x, y) ^ (file_pattern ? 24'hffffff : 24'd0);
                filebyte = (c == 0) ? pxv[7:0] : (c == 1) ? pxv[15:8] : pxv[23:16];
            end
        end
    endfunction

    // 光栅像素 k（k = y*W + x）的期望 RGB565
    function [15:0] exp565_k;
        input integer k;
        begin
            exp565_k = px565(k % W, k / W);
        end
    endfunction

    task mbr_set_card0;
        begin
            u_card.sector[450] = 8'h0C;             // FAT32 LBA (XINT13)
            u_card.sector[454] = VOL_BASE[7:0];     // 分区起始 LBA（小端）
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
        integer c, s, o, j;
        begin
            u_card.mk_fat32_dbr(16'd512, SPC, RSVD, NFAT, FATSZ, ROOTCLUS, TOTSEC, 1'b1);
            // FAT：FAT[2]=EOC，FAT[3..58]=next，FAT[59]=EOC
            u_card.vol_zero(VOL_FAT_LBA);
            u_card.vol_set_le(VOL_FAT_LBA, 16'd8, 32'h0FFF_FFFF, 3'd4);
            for (c = 3; c <= FILE_CLUS_LAST - 1; c = c + 1)
                u_card.vol_set_le(VOL_FAT_LBA, c*4, c+1, 3'd4);
            u_card.vol_set_le(VOL_FAT_LBA, FILE_CLUS_LAST*4, 32'h0FFF_FFFF, 3'd4);
            // 根目录：4 条目录项
            u_card.vol_zero(VOL_ROOT_LBA);
            u_card.mk_dir_entry(VOL_ROOT_LBA, 16'd0,  "SV0001  BMP", 8'h20, FILE_CLUS, FILE_BYTES);
            u_card.mk_dir_entry(VOL_ROOT_LBA, 16'd32, "SV0002  BMP", 8'h20, FILE_CLUS, FILE_BYTES);
            u_card.mk_dir_entry(VOL_ROOT_LBA, 16'd64, "SV0003  BMP", 8'h20, FILE_CLUS, FILE_BYTES);
            u_card.mk_dir_entry(VOL_ROOT_LBA, 16'd96, "SV0004  BMP", 8'h20, FILE_CLUS, FILE_BYTES);
            // 文件主体：整幅真 BMP 写进卷（簇连续 ⇒ 文件扇区 s 在卷内 LBA = 34+s）
            for (s = 0; s < FILE_SECTORS; s = s + 1) begin
                u_card.vol_used[VOL_FILE0_LBA + s] = 1'b1;
                for (o = 0; o < 512; o = o + 1) begin
                    j = s*512 + o;
                    u_card.vol[(VOL_FILE0_LBA + s)*512 + o] = (j < FILE_BYTES) ? filebyte(j) : 8'h00;
                end
            end
            mbr_set_card0;
        end
    endtask


 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,btn_next=1,btn_auto=1;
 wire sd_ncs,sd_dclk,sd_mosi,sd_miso,uart_txd;
 wire [3:0] led;wire d0,d1,d2,dc,scl;tri1 sda;
 safevision_top #(.FONT_FILE("font8x16.mem"),.PLAYER_SPI_INIT_DIV(1)) dut(
 .clk(clk),.rst_n(rst_n),.btn_next(btn_next),.btn_auto(btn_auto),.btn_emergency(1'b1),.uart_txd(uart_txd),.led(led),
 .sd_ncs(sd_ncs),.sd_dclk(sd_dclk),.sd_mosi(sd_mosi),.sd_miso(sd_miso),
 .HDMI_D0_P(d0),.HDMI_D1_P(d1),.HDMI_D2_P(d2),.HDMI_CLK_P(dc),
 .HDMI_DDC_SCL(scl),.HDMI_DDC_SDA(sda));
 sd_spi_card_model #(.VOL_BASE(VOL_BASE),.VOL_SECTORS(2048)) u_card(
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
     // Observe one edge after the publisher changed. The shared engine may
     // already be reading the OLD active slot; read-busy is not an undrained
     // write. Check actual outstanding writes, including the final quiet gap.
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
 integer full_frames=0,new_slot_frames=0,axis_k=0,pixel_bad=0,tag_bad=0;
 reg axis_slot=0;
 reg compare_axis=0;
 reg [15:0] expected_p;reg [23:0] expected_rgb;
 always @(posedge dut.pixel_clk)if(dut.axis_valid&&dut.axis_ready)begin
   if(dut.axis_user)begin
     if(compare_axis&&axis_k!=FRAME_PIX)tag_bad=tag_bad+1;
     compare_axis=dut.active&&!dut.frame_fault&&!dut.safety_active;axis_k=0;
     axis_slot=dut.core.display.pix_active_slot[0];
   end
   if(compare_axis)begin
     if(axis_k>=FRAME_PIX)tag_bad=tag_bad+1;
     else begin
       expected_p=axis_slot?exp565_k(axis_k):~exp565_k(axis_k);expected_rgb=rgb565(expected_p);
       if(dut.axis_data!==expected_rgb)begin
         if(pixel_bad<4)$display("[DIAG] AXIS pixel=%0d got=%06x expected=%06x",axis_k,dut.axis_data,expected_rgb);
         pixel_bad=pixel_bad+1;
       end
       if(dut.axis_last!==((axis_k%W)==W-1))tag_bad=tag_bad+1;
     end
     axis_k=axis_k+1;
     if(axis_k==FRAME_PIX)begin full_frames=full_frames+1;compare_axis=0;
       if(!axis_slot)new_slot_frames=new_slot_frames+1;
       $display("[TB] checked full display frame %0d (%0d pixels), underflows=%0d",full_frames,FRAME_PIX,dut.underflows);end
   end
 end
 task cmp_mem(input integer base,input string name);
 integer j,bad;reg [31:0] expected;
 begin bad=0;for(j=0;j<FRAME_PIX/2;j=j+1)begin
   expected={exp565_k(j*2+1),exp565_k(j*2)};
   if(base==SLOT0_WORD)expected=~expected;
   if(dut.memory_ip.mem[base+j]!==expected)begin
     if(bad==0)$display("[DIAG] memory word=%0d got=%08x expected=%08x",j,dut.memory_ip.mem[base+j],expected);
     bad=bad+1;
   end
 end check(bad==0,name);end endtask
 integer before_frames;
 initial begin
   check(px24(7,11)===24'h0c1222&&px24(0,1)===24'h010105&&
         px24(255,255)===24'h00fe06,
         "independent 8-bit RGB pattern samples include x/y and all channels");
   check(px565(0,0)!=px565(256,0)&&px565(256,0)!=px565(512,0)&&
         px565(0,0)!=px565(0,256),
         "row/column high bits remain distinct after RGB565 quantization");
   build_volume;repeat(20)@(negedge clk);rst_n=1;
   wait(dut.pl_card_usable);check(dut.pl_file_cnt==4,"FAT32 indexed four files at 50 MHz");
   wait(dut.pl_frame_cnt==1);check(dut.card_mode,"card owns producer after first frame");
   check(dut.sk_frame_ok,"first frame CRC accepted after memory drain and swap");
   cmp_mem(SLOT1_WORD,"slot 1 has all 153600 correct words from bottom-up BMP");
   wait(full_frames>=2);
   check(pixel_bad==0&&tag_bad==0,"two full VGA AXIS frames: RGB and SOF/EOL pixel-exact");
   before_frames=full_frames;
   // A second, DIFFERENT image must reach the other slot and the screen;
   // otherwise a stale buffer could pass a repeated-identical-image test.
   file_pattern=1;build_volume;
   @(negedge clk);btn_next=0;repeat(70000)@(negedge clk);btn_next=1;
   wait(dut.pl_frame_cnt==2);
   cmp_mem(SLOT0_WORD,"slot 0 has all 153600 correct words after next-button frame");
   wait(new_slot_frames>=2);
   check(dut.pl_fail_stage==0&&dut.sk_ec==0,"no player or sink error on two physical-rate card frames");
   check(publish_count==2&&unsafe_publish==0,"exactly two frame events, both after physical write drain");
   check(active_writes==0,"displayed slot never overwritten by card producer");
   check(dut.underflows==0&&dut.overflows==0&&!dut.frame_fault,"no display underflow, FIFO overflow or frame fault");
   check(pixel_bad==0&&tag_bad==0,"all accepted active-frame pixels and line markers match");
   check(!dut.hdmi_backpressure,"no HDMI queue overflow");
   check(dut.memory_ip.protocol_errors==0,"strict SDRAM application burst contract respected");
   $display("CARD DISPLAY checks=%0d errors=%0d checked_frames=%0d write_bursts=%0d read_bursts=%0d publishes=%0d undrained_publishes=%0d",checks,errors,full_frames,dut.memory_ip.write_bursts,dut.memory_ip.read_bursts,publish_count,unsafe_publish);
   if(errors)$fatal(1,"CARD DISPLAY FAILED");
   test_done=1;$display("[PASS] CARD DISPLAY PASS");$finish;
 end
 initial begin #2000000000;$fatal(1,"CARD DISPLAY watchdog: player=%0d ec=%02x sink=%0d px=%0d frames=%0d active=%b fault=%b",dut.pl_state,dut.pl_ec,dut.sk_state,dut.sk_px_written,dut.pl_frame_cnt,dut.active,dut.frame_fault);end
endmodule
