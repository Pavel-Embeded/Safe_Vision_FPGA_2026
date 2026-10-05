// ============================================================================
// tb_card_to_screen.sv - SD-card/FAT32 front half -> RGB565 pixel stream
// ----------------------------------------------------------------------------
// WHY THIS EXISTS (the gap it closes)
//   tb_b_frame_memory.sv and tb_ab_frame_display.sv both start from a BMP byte
//   stream that the TESTBENCH INVENTS. Neither one touches the SD/FAT32 front
//   half. This testbench puts a real (synthetic but fully deterministic) BMP
//   FILE on the sd_spi_card_model and drives the real storage chain:
//
//     sd_spi_card_model
//       -> sd_initializer
//       -> sd_sector_reader        (single-sector CMD17, shared SPI + shared
//                                   read bus with the front-half modules)
//       -> mbr_parser              (card LBA 0 = MBR -> volume base)
//       -> fat32_boot_parser       (volume LBA 0 = DBR/BPB)
//       -> fat32_directory_scanner (+ fat32_cluster_walker)
//       -> file_index              (SV0001.BMP selection + sort)
//       -> file_streamer           (+ fat32_cluster_walker, cluster chain)
//       -> bmp_parser              (BMP header validation)
//       -> bmp_unpack              (BGR888 -> RGB565)
//
//   and asserts the RGB565 pixel stream against the bytes that were actually
//   placed on the card (see "WHAT IS ASSERTED AGAINST WHAT" below).
//
// WHAT IS ASSERTED AGAINST WHAT
//   The expectation is NOT a second invention. It is computed from the exact
//   byte sequence the card model returns for file offset j (`filebyte(j)`),
//   which is built from:
//     * the 54-byte BMP header written into the card's volume at the file's
//       first sector (vol_set), and
//     * the card model's documented default sector pattern (sector[k]=k+0x11)
//       for every later sector of the file.
//   If the chain mis-addresses, drops, reorders or duplicates a byte, the
//   pixel comparison fails. `filebyte()` is the single source of truth used
//   BOTH to lay the file down and to compute the expected pixels.
//
// WHY A 640x480 BMP (and why the pixel data is mostly the card default pattern)
//   bmp_parser.v hard-codes width==640 && height==+/-480 (see its `size_ok`
//   and BMP_PIX_BYTES=921600). A 640x480 24-bit BMP is 921654 bytes = 1801
//   sectors, which does NOT fit in sd_spi_card_model's 64-sector volume
//   (~32 KB). So we place the first sector of the file (header + first bytes)
//   in the volume and let the remaining sectors fall through to the model's
//   deterministic default pattern. The volume still holds a genuine FAT32
//   image (DBR + FAT + root directory + 4 directory entries); only the bulk
//   pixel payload comes from the card model's default fill. Everything the
//   front half must get right (MBR/volume base, BPB, directory scan, index,
//   cluster chain, byte stream, BMP header) is real.
//
// WHAT THIS DOES **NOT** PROVE
//   * Real SD card timing / protocol AC: the card model answers instantly at
//     the SPI bit level but has no NCR, no busy polling, no timing models.
//   * Multi-sector CMD18: sd_sector_reader is CMD17 only (rd_len must be 1).
//   * The volume is a synthetic, tiny FAT32 image (1 FAT sector, 32
//     sectors/cluster, ~2048 sectors declared). It is not a real card image.
//   * The bulk of the pixel payload is the card model's default pattern, not
//     bytes written by this TB (see above).
//   * It stops at bmp_unpack: no frame_writer / SDRAM / A display core here.
//   * Single clock domain (50 MHz): no CDC.
//
// How to run: safevision/tools/run_card_to_screen_sim.ps1
// Plusarg +STOP_AFTER_SCAN stops right after file_index commit (fast smoke run
// of the front half only, no 921654-byte stream).
// ============================================================================
`timescale 1ns / 1ps
`include "safevision_defs.vh"
`include "pixel_format_defs.vh"

module tb_card_to_screen;

    // ------------------------------------------------------------------------
    // Clock / reset / bookkeeping
    // ------------------------------------------------------------------------
    localparam integer CLK_HZ = 50_000_000;
    reg clk   = 1'b0;
    always #10 clk = ~clk;                 // 20 ns -> 50 MHz
    reg rst_n = 1'b0;

    integer errors = 0;
    task check;
        input         cond;
        input [255:0] name;
        begin
            if (cond) $display("[PASS] %0s", name);
            else begin $display("[FAIL] %0s", name); errors = errors + 1; end
        end
    endtask

    // ------------------------------------------------------------------------
    // Card / volume geometry (see file header for the layout arithmetic)
    // ------------------------------------------------------------------------
    localparam [31:0] VOL_BASE  = 32'd16;     // partition 0 start (card LBA)
    localparam [7:0]  SPC       = 8'd32;      // sectors per cluster (2^5)
    localparam [15:0] RSVD      = 16'd1;      // reserved sectors
    localparam [7:0]  NFAT      = 8'd1;       // number of FATs
    localparam [31:0] FATSZ     = 32'd1;      // FAT size in sectors
    localparam [31:0] TOTSEC    = 32'd2048;   // total sectors (declared)
    localparam [31:0] ROOTCLUS  = 32'd2;      // root directory cluster
    localparam [31:0] FILE_CLUS = 32'd3;      // first cluster of SV0001.BMP
    localparam [31:0] FILE_CLUS_LAST = 32'd59;// last cluster (57 clusters 3..59)

    localparam integer W = 640;
    localparam integer H = 480;
    localparam integer PIX_TOTAL = W * H;                       // 307200
    localparam [31:0]  FILE_SIZE = 32'd921654;                  // 54 + 640*480*3
    localparam integer FILE_BYTES = 54 + W * H * 3;             // 921654

    // volume-relative LBAs (all < 64 so the card model maps them to vol[])
    localparam [31:0] VOL_DBR_LBA   = 32'd0;
    localparam [31:0] VOL_FAT_LBA   = 32'd1;
    localparam [31:0] VOL_ROOT_LBA  = 32'd2;
    localparam [31:0] VOL_FILE0_LBA = 32'd34;   // data_start(2)+(3-2)*32 = 34

    // ------------------------------------------------------------------------
    // BMP header (54 bytes). height = -480 -> top-down, so file row order ==
    // raster order and pixel n uses file bytes [54+3n .. 54+3n+2].
    // ------------------------------------------------------------------------
    reg [7:0] bmp_hdr [0:53];
    initial begin
        integer k;
        for (k = 0; k < 54; k = k + 1) bmp_hdr[k] = 8'h00;
        bmp_hdr[0]  = 8'h42; bmp_hdr[1]  = 8'h4D;                 // "BM"
        bmp_hdr[2]  = 8'h36; bmp_hdr[3]  = 8'h10;
        bmp_hdr[4]  = 8'h0E; bmp_hdr[5]  = 8'h00;                 // bfSize 921654
        bmp_hdr[10] = 8'h36;                                      // bfOffBits 54
        bmp_hdr[14] = 8'h28;                                      // biSize 40
        bmp_hdr[18] = 8'h80; bmp_hdr[19] = 8'h02;                 // width 640
        bmp_hdr[22] = 8'h20; bmp_hdr[23] = 8'hFE;
        bmp_hdr[24] = 8'hFF; bmp_hdr[25] = 8'hFF;                 // height -480
        bmp_hdr[26] = 8'h01;                                      // planes 1
        bmp_hdr[28] = 8'h18;                                      // bpp 24
        bmp_hdr[34] = 8'h00; bmp_hdr[35] = 8'h10;
        bmp_hdr[36] = 8'h0E; bmp_hdr[37] = 8'h00;                 // image 921600
    end

    // ------------------------------------------------------------------------
    // Unmapped card sectors fall back to the card model's default pattern
    // sector[k] = (k & 0xFF) + 0x11. The MBR is written into that same buffer
    // (card LBA 0 is outside the volume window), so a handful of offsets carry
    // MBR bytes instead of the pattern. sector_byte(k) is the exact byte the
    // card returns for offset k of ANY unmapped sector.
    // ------------------------------------------------------------------------
    function [7:0] sector_byte;
        input integer k;
        begin
            case (k)
                450:     sector_byte = 8'h0C;              // partition type
                454:     sector_byte = VOL_BASE[7:0];      // partition start LBA
                455:     sector_byte = VOL_BASE[15:8];
                456:     sector_byte = VOL_BASE[23:16];
                457:     sector_byte = VOL_BASE[31:24];
                458:     sector_byte = 8'h00;              // partition sector count
                459:     sector_byte = 8'h00;
                460:     sector_byte = 8'h01;
                461:     sector_byte = 8'h00;
                510:     sector_byte = 8'h55;              // MBR signature
                511:     sector_byte = 8'hAA;
                default: sector_byte = (k & 32'hFF) + 32'h11;
            endcase
        end
    endfunction

    // ------------------------------------------------------------------------
    // Byte the card returns for file offset j. Single source of truth.
    //   j <  54            : BMP header (placed in vol, file first sector)
    //   j <  512           : rest of the file's first sector (vol_zero -> 0)
    //   j >= 512           : unmapped sector -> sector_byte(j & 511)
    // ------------------------------------------------------------------------
    function [7:0] filebyte;
        input integer j;
        begin
            if (j < 54)       filebyte = bmp_hdr[j];
            else if (j < 512) filebyte = 8'h00;
            else              filebyte = sector_byte(j & 32'h1FF);
        end
    endfunction

    // Pixel byte index p (= file offset - 54) -> card byte
    function [7:0] pixbyte;
        input integer p;
        integer jj;
        begin
            jj = p + 54;
            if (jj < 512) pixbyte = 8'h00;
            else          pixbyte = sector_byte(jj & 32'h1FF);
        end
    endfunction

    // Expected RGB565 for raster pixel n (top-down BMP, 640*3 stride = 1920)
    function [15:0] exp565;
        input integer n;
        integer b3;
        reg [7:0] bb, gg, rr;
        begin
            b3 = n * 3;
            bb = pixbyte(b3);
            gg = pixbyte(b3 + 1);
            rr = pixbyte(b3 + 2);
            exp565 = { rr[7:3], gg[7:2], bb[7:3] };
        end
    endfunction

    // ========================================================================
    // SPI bus + card model
    // ========================================================================
    wire sd_ncs, sd_dclk, sd_mosi, sd_miso;
    wire [5:0]  o_cmd;
    wire [31:0] o_arg, o_acmd41_arg;
    wire [7:0]  o_cmd_cnt, o_acmd41_cnt;
    wire        o_cmd_valid;

    sd_spi_card_model #(
        .VOL_BASE (VOL_BASE)
    ) u_card (
        .sclk         (sd_dclk),
        .cs_n         (sd_ncs),
        .mosi         (sd_mosi),
        .miso         (sd_miso),
        .i_dead       (1'b0),
        .o_cmd        (o_cmd),
        .o_arg        (o_arg),
        .o_acmd41_arg (o_acmd41_arg),
        .o_cmd_cnt    (o_cmd_cnt),
        .o_acmd41_cnt (o_acmd41_cnt),
        .o_cmd_valid  (o_cmd_valid)
    );

    // ========================================================================
    // All nets declared up front (never let Verilog build an implicit 1-bit net
    // for a signal used inside an always block - that silently hangs the chain).
    // ========================================================================
    // sd_initializer
    wire        sdhc, init_done, init_error;
    wire [7:0]  init_err_code;
    wire        init_cs_n, init_tx_valid;
    wire [7:0]  init_tx_data;
    wire [15:0] init_clk_div;
    reg         init_start;

    // mbr_parser
    reg         mp_start;
    wire        mp_done, mp_has;
    wire [7:0]  mp_ec, mp_ed;
    wire [31:0] mp_vol_base, mp_part_secs;
    wire [31:0] mp_rd_addr;
    wire [15:0] mp_rd_len;
    wire        mp_rd_en, mp_data_ready;

    // fat32_boot_parser
    reg         bp_start;
    wire        bp_done, bp_err;
    wire [7:0]  bp_ec, bp_ed, bp_spc, bp_nfat;
    wire [15:0] bp_bps;
    wire [31:0] bp_fat_lba, bp_root_clus, bp_root_lba, bp_data_lba, bp_tot_sec, bp_tot_clus;
    wire [31:0] bp_rd_addr;
    wire [15:0] bp_rd_len;
    wire        bp_rd_en, bp_data_ready;

    // fat32_directory_scanner + its walker
    reg         scan_en;
    wire        scan_done, dir_bad;
    wire [7:0]  dn_ec, dn_ed;
    wire [87:0] ent_name;
    wire [7:0]  ent_attr;
    wire [31:0] ent_first_clus, ent_size;
    wire [15:0] ent_index;
    wire        ent_valid, ent_ready;
    wire [31:0] dn_rd_addr;
    wire [15:0] dn_rd_len;
    wire        dn_rd_en, dn_data_ready;
    wire [31:0] dn_wk_cur, dn_wk_next;
    wire        dn_wk_start, dn_wk_rst, dn_wk_busy, dn_wk_done, dn_wk_eoc, dn_wk_err;
    wire [7:0]  dn_wk_ec, dn_wk_ed;
    wire [31:0] wd_rd_addr;
    wire [15:0] wd_rd_len;
    wire        wd_rd_en, wd_data_ready;

    // file_index
    reg         idx_clear, idx_commit;
    wire        idx_done;
    wire [3:0]  file_cnt, file_valid;
    wire        insufficient;
    wire [7:0]  idx_ec, idx_ed;
    wire [31:0] sel_first_clus, sel_size;
    wire        sel_valid;
    wire [31:0] sel_wav_clus, sel_wav_size;
    wire        sel_wav_valid;
    wire [15:0] bmp_seen, wav_seen;

    // file_streamer + its walker
    reg         fst_start;
    reg  [31:0] fst_first_clus, fst_file_size;
    wire        fst_busy, fst_done, fst_error;
    wire [7:0]  fst_ec, fst_ed;
    wire [31:0] fst_bytes;
    wire [7:0]  fst_data;
    wire        fst_valid, fst_sof, fst_eof;
    wire [31:0] fst_rd_addr;
    wire [15:0] fst_rd_len;
    wire        fst_rd_en, fst_data_ready;
    wire [31:0] fst_wk_cur, fst_wk_next;
    wire        fst_wk_start, fst_wk_rst, fst_wk_busy, fst_wk_done, fst_wk_eoc, fst_wk_err;
    wire [7:0]  fst_wk_ec, fst_wk_ed;
    wire [31:0] wf_rd_addr;
    wire [15:0] wf_rd_len;
    wire        wf_rd_en, wf_data_ready;

    // bmp_parser
    wire        bp_ready;
    wire        bmp_check_done, bmp_check_error;
    wire [7:0]  bmp_ec, bmp_ed;
    wire [15:0] bmp_width, bmp_height;
    wire        bmp_top_down;
    wire [7:0]  bmp_bpp;
    wire [31:0] bmp_compression, bmp_pixel_off, bmp_file_size_o;
    wire [7:0]  bpo_data;
    wire        bpo_valid, bpo_sof, bpo_eof, bpo_ready;

    // bmp_unpack
    wire [15:0] bpu_pixel;
    wire        bpu_valid;
    wire [9:0]  bpu_x, bpu_y;
    wire        bpu_sof, bpu_eof, bpu_done, bpu_error;
    wire [7:0]  bpu_ec, bpu_ed;

    // sd_sector_reader (shared) + spi_master
    wire        rd_ready;
    wire [7:0]  rd_data;
    wire        rd_data_valid, rd_data_last;
    wire        rd_done, rd_to, rd_crc;
    wire [7:0]  rd_ec, rd_ed;
    wire        rd_cs_n, rd_tx_valid;
    wire [7:0]  rd_tx_data;
    wire [15:0] rd_clk_div;
    wire        spi_tx_ready, spi_busy, spi_rx_valid;
    wire [7:0]  spi_rx_data;

    // ========================================================================
    // Read-bus ownership: phase selects which front-half master owns the reader;
    // within SCAN/STREAM the walker gets the bus while it is busy.
    // (This mirrors top_stage6_fat32_mount.v's arbitration pattern.)
    // ========================================================================
    localparam [1:0] PH_MBR = 2'd0, PH_BOOT = 2'd1, PH_SCAN = 2'd2, PH_STREAM = 2'd3;
    reg [1:0] phase = PH_MBR;

    wire scan_wk = (phase == PH_SCAN)   && dn_wk_busy;
    wire strm_wk = (phase == PH_STREAM) && fst_wk_busy;

    wire        bus_rd_en   = (phase == PH_MBR)  ? mp_rd_en :
                              (phase == PH_BOOT) ? bp_rd_en :
                              (phase == PH_SCAN) ? (scan_wk ? wd_rd_en : dn_rd_en) :
                                                   (strm_wk ? wf_rd_en : fst_rd_en);
    wire [31:0] bus_rd_addr = (phase == PH_MBR)  ? mp_rd_addr :
                              (phase == PH_BOOT) ? bp_rd_addr :
                              (phase == PH_SCAN) ? (scan_wk ? wd_rd_addr : dn_rd_addr) :
                                                   (strm_wk ? wf_rd_addr : fst_rd_addr);
    wire [15:0] bus_rd_len  = (phase == PH_MBR)  ? mp_rd_len :
                              (phase == PH_BOOT) ? bp_rd_len :
                              (phase == PH_SCAN) ? (scan_wk ? wd_rd_len : dn_rd_len) :
                                                   (strm_wk ? wf_rd_len : fst_rd_len);
    wire        bus_data_ready = (phase == PH_MBR)  ? mp_data_ready :
                                 (phase == PH_BOOT) ? bp_data_ready :
                                 (phase == PH_SCAN) ? (scan_wk ? wd_data_ready : dn_data_ready) :
                                                      (strm_wk ? wf_data_ready : fst_data_ready);

    // Volume base added exactly ONCE (interface_spec 3.2.1). mbr_parser reads
    // card LBA 0 while mbr_vol_base is still 0, so it lands on the MBR too.
    wire [31:0] rd_addr_to_reader = bus_rd_addr + mp_vol_base;

    // ========================================================================
    // Module instances
    // ========================================================================
    sd_initializer u_init (
        .clk(clk), .rst_n(rst_n), .start(init_start),
        .sdhc(sdhc), .init_done(init_done), .init_error(init_error),
        .err_code(init_err_code), .err_detail(), .retry_cnt(), .dbg_state(),
        .spi_cs_n(init_cs_n), .spi_clk_div(init_clk_div),
        .spi_tx_valid(init_tx_valid), .spi_tx_data(init_tx_data),
        .spi_tx_ready(spi_tx_ready), .spi_rx_data(spi_rx_data), .spi_rx_valid(spi_rx_valid)
    );

    mbr_parser u_mbr (
        .clk(clk), .rst_n(rst_n), .start(mp_start),
        .parse_done(mp_done), .err_code(mp_ec), .err_detail(mp_ed), .dbg_state(),
        .has_mbr(mp_has), .vol_base_lba(mp_vol_base), .part_secs(mp_part_secs),
        .sd_rd_addr(mp_rd_addr), .sd_rd_len(mp_rd_len), .sd_rd_en(mp_rd_en),
        .sd_rd_ready(rd_ready), .sd_data(rd_data), .sd_data_valid(rd_data_valid),
        .sd_data_ready(mp_data_ready), .sd_data_last(rd_data_last),
        .sd_rd_done(rd_done), .sd_timeout_err(rd_to), .sd_crc16_err(rd_crc),
        .sd_err_code(rd_ec), .sd_err_detail(rd_ed)
    );

    fat32_boot_parser u_boot (
        .clk(clk), .rst_n(rst_n), .start(bp_start),
        .mount_done(bp_done), .mount_error(bp_err), .err_code(bp_ec), .err_detail(bp_ed),
        .dbg_state(),
        .bytes_per_sec(bp_bps), .sec_per_clus(bp_spc), .num_fats(bp_nfat),
        .fat_start_lba(bp_fat_lba), .root_clus(bp_root_clus),
        .root_dir_lba(bp_root_lba), .data_start_lba(bp_data_lba),
        .total_sec(bp_tot_sec), .total_clus(bp_tot_clus),
        .sd_rd_addr(bp_rd_addr), .sd_rd_len(bp_rd_len), .sd_rd_en(bp_rd_en),
        .sd_rd_ready(rd_ready), .sd_data(rd_data), .sd_data_valid(rd_data_valid),
        .sd_data_ready(bp_data_ready), .sd_data_last(rd_data_last),
        .sd_rd_done(rd_done), .sd_timeout_err(rd_to), .sd_crc16_err(rd_crc),
        .sd_err_code(rd_ec), .sd_err_detail(rd_ed)
    );

    fat32_directory_scanner u_scan (
        .clk(clk), .rst_n(rst_n), .scan_en(scan_en),
        .scan_done(scan_done), .dir_bad(dir_bad), .err_code(dn_ec), .err_detail(dn_ed),
        .dbg_state(),
        .sec_per_clus(bp_spc), .root_clus(bp_root_clus),
        .root_dir_lba(bp_root_lba), .data_start_lba(bp_data_lba),
        .ent_name(ent_name), .ent_attr(ent_attr), .ent_first_clus(ent_first_clus),
        .ent_size(ent_size), .ent_index(ent_index), .ent_valid(ent_valid), .ent_ready(ent_ready),
        .sd_rd_addr(dn_rd_addr), .sd_rd_len(dn_rd_len), .sd_rd_en(dn_rd_en),
        .sd_rd_ready(rd_ready), .sd_data(rd_data), .sd_data_valid(rd_data_valid),
        .sd_data_ready(dn_data_ready), .sd_data_last(rd_data_last),
        .sd_rd_done(rd_done), .sd_timeout_err(rd_to), .sd_crc16_err(rd_crc),
        .sd_err_code(rd_ec), .sd_err_detail(rd_ed),
        .wk_cur_clus(dn_wk_cur), .wk_start(dn_wk_start), .wk_rst_walk(dn_wk_rst),
        .wk_busy(dn_wk_busy), .wk_done(dn_wk_done), .wk_next_clus(dn_wk_next),
        .wk_eoc(dn_wk_eoc), .wk_error(dn_wk_err), .wk_err_code(dn_wk_ec), .wk_err_detail(dn_wk_ed)
    );

    fat32_cluster_walker u_wk_dir (
        .clk(clk), .rst_n(rst_n), .rst_walk(dn_wk_rst), .start(dn_wk_start),
        .cur_clus(dn_wk_cur), .busy(dn_wk_busy), .done(dn_wk_done), .next_clus(dn_wk_next),
        .eoc(dn_wk_eoc), .error(dn_wk_err), .err_code(dn_wk_ec), .err_detail(dn_wk_ed),
        .hop_cnt(), .dbg_state(),
        .fat_start_lba(bp_fat_lba), .total_clus(bp_tot_clus),
        .sd_rd_addr(wd_rd_addr), .sd_rd_len(wd_rd_len), .sd_rd_en(wd_rd_en),
        .sd_rd_ready(rd_ready), .sd_data(rd_data), .sd_data_valid(rd_data_valid),
        .sd_data_ready(wd_data_ready), .sd_data_last(rd_data_last),
        .sd_rd_done(rd_done), .sd_timeout_err(rd_to), .sd_crc16_err(rd_crc),
        .sd_err_code(rd_ec), .sd_err_detail(rd_ed)
    );

    file_index u_idx (
        .clk(clk), .rst_n(rst_n),
        .ent_name(ent_name), .ent_attr(ent_attr), .ent_first_clus(ent_first_clus),
        .ent_size(ent_size), .ent_index(ent_index), .ent_valid(ent_valid), .ent_ready(ent_ready),
        .idx_clear(idx_clear), .idx_commit(idx_commit), .idx_done(idx_done),
        .file_cnt(file_cnt), .file_valid(file_valid), .insufficient(insufficient),
        .err_code(idx_ec), .err_detail(idx_ed),
        .sel_slot(2'd0), .sel_first_clus(sel_first_clus), .sel_size(sel_size), .sel_valid(sel_valid),
        .sel_wav_first_clus(sel_wav_clus), .sel_wav_size(sel_wav_size), .sel_wav_valid(sel_wav_valid),
        .bmp_seen(bmp_seen), .wav_seen(wav_seen)
    );

    file_streamer u_fst (
        .clk(clk), .rst_n(rst_n),
        .start(fst_start), .first_clus(fst_first_clus), .file_size(fst_file_size),
        .busy(fst_busy), .done(fst_done), .error(fst_error), .err_code(fst_ec), .err_detail(fst_ed),
        .bytes_rd(fst_bytes), .dbg_state(),
        .data(fst_data), .valid(fst_valid), .ready(bp_ready), .sof(fst_sof), .eof(fst_eof),
        .sec_per_clus(bp_spc), .fat_start_lba(bp_fat_lba),
        .data_start_lba(bp_data_lba), .total_clus(bp_tot_clus),
        .wk_cur_clus(fst_wk_cur), .wk_start(fst_wk_start), .wk_rst_walk(fst_wk_rst),
        .wk_busy(fst_wk_busy), .wk_done(fst_wk_done), .wk_next_clus(fst_wk_next),
        .wk_eoc(fst_wk_eoc), .wk_error(fst_wk_err),
        .wk_err_code(fst_wk_ec), .wk_err_detail(fst_wk_ed),
        .sd_rd_addr(fst_rd_addr), .sd_rd_len(fst_rd_len), .sd_rd_en(fst_rd_en),
        .sd_rd_ready(rd_ready), .sd_data(rd_data), .sd_data_valid(rd_data_valid),
        .sd_data_ready(fst_data_ready), .sd_data_last(rd_data_last),
        .sd_rd_done(rd_done), .sd_timeout_err(rd_to), .sd_crc16_err(rd_crc),
        .sd_err_code(rd_ec), .sd_err_detail(rd_ed)
    );

    fat32_cluster_walker u_wk_fst (
        .clk(clk), .rst_n(rst_n), .rst_walk(fst_wk_rst), .start(fst_wk_start),
        .cur_clus(fst_wk_cur), .busy(fst_wk_busy), .done(fst_wk_done), .next_clus(fst_wk_next),
        .eoc(fst_wk_eoc), .error(fst_wk_err), .err_code(fst_wk_ec), .err_detail(fst_wk_ed),
        .hop_cnt(), .dbg_state(),
        .fat_start_lba(bp_fat_lba), .total_clus(bp_tot_clus),
        .sd_rd_addr(wf_rd_addr), .sd_rd_len(wf_rd_len), .sd_rd_en(wf_rd_en),
        .sd_rd_ready(rd_ready), .sd_data(rd_data), .sd_data_valid(rd_data_valid),
        .sd_data_ready(wf_data_ready), .sd_data_last(rd_data_last),
        .sd_rd_done(rd_done), .sd_timeout_err(rd_to), .sd_crc16_err(rd_crc),
        .sd_err_code(rd_ec), .sd_err_detail(rd_ed)
    );

    bmp_parser u_bmp (
        .clk(clk), .rst_n(rst_n),
        .data(fst_data), .valid(fst_valid), .ready(bp_ready), .eof(fst_eof),
        .file_size(fst_file_size),
        .check_done(bmp_check_done), .check_error(bmp_check_error),
        .err_code(bmp_ec), .err_detail(bmp_ed),
        .width(bmp_width), .height(bmp_height), .top_down(bmp_top_down),
        .bpp(bmp_bpp), .compression(bmp_compression), .pixel_off(bmp_pixel_off),
        .file_size_o(bmp_file_size_o), .dbg_state(),
        .out_data(bpo_data), .out_valid(bpo_valid), .out_ready(bpo_ready),
        .out_sof(bpo_sof), .out_eof(bpo_eof)
    );

    bmp_unpack u_unpack (
        .clk(clk), .rst_n(rst_n),
        .din(bpo_data), .din_valid(bpo_valid), .din_ready(bpo_ready),
        .din_sof(bpo_sof), .din_eof(bpo_eof),
        .width(bmp_width), .height(bmp_height), .top_down(bmp_top_down), .pixel_off(bmp_pixel_off),
        .pixel(bpu_pixel), .pixel_valid(bpu_valid), .pixel_ready(1'b1),
        .x(bpu_x), .y(bpu_y), .img_sof(bpu_sof), .img_eof(bpu_eof),
        .done(bpu_done), .error(bpu_error), .err_code(bpu_ec), .err_detail(bpu_ed),
        .dbg_state()
    );

    sd_sector_reader u_rd (
        .clk(clk), .rst_n(rst_n), .sdhc(sdhc),
        .rd_en(bus_rd_en), .rd_addr(rd_addr_to_reader), .rd_len(bus_rd_len), .rd_ready(rd_ready),
        .data(rd_data), .data_valid(rd_data_valid), .data_ready(bus_data_ready),
        .data_last(rd_data_last),
        .rd_done(rd_done), .busy(), .timeout_err(rd_to), .crc16_err(rd_crc),
        .err_code(rd_ec), .err_detail(rd_ed), .crc_rx(), .dbg_state(),
        .spi_cs_n(rd_cs_n), .spi_clk_div(rd_clk_div),
        .spi_tx_valid(rd_tx_valid), .spi_tx_data(rd_tx_data),
        .spi_tx_ready(spi_tx_ready), .spi_rx_data(spi_rx_data), .spi_rx_valid(spi_rx_valid)
    );

    wire spi_use_reader = init_done;
    wire        spi_tx_valid = spi_use_reader ? rd_tx_valid : init_tx_valid;
    wire [7:0]  spi_tx_data  = spi_use_reader ? rd_tx_data  : init_tx_data;
    wire [15:0] spi_clk_div  = spi_use_reader ? rd_clk_div  : init_clk_div;
    assign sd_ncs = init_cs_n & rd_cs_n;

    spi_master #(.CLK_FREQ(CLK_HZ)) u_spi (
        .clk(clk), .rst_n(rst_n), .clk_div(spi_clk_div), .cs_n(sd_ncs),
        .tx_valid(spi_tx_valid), .tx_data(spi_tx_data), .tx_ready(spi_tx_ready),
        .rx_data(spi_rx_data), .rx_valid(spi_rx_valid), .busy(spi_busy),
        .sclk(sd_dclk), .mosi(sd_mosi), .miso(sd_miso)
    );

    // ========================================================================
    // Volume construction (tasks write directly into the card model)
    // ========================================================================
    task mbr_set_card0;
        begin
            // NOTE: do NOT wipe u_card.sector[]. The card model's default
            // pattern (sector[k]=k+0x11) is what every unmapped sector - and
            // therefore the bulk of the BMP file - returns. Wiping it here was
            // a real bug: the file's later sectors came back as 0x00 and every
            // pixel after #152 mismatched. mbr_parser only reads a few offsets,
            // so we overlay just those and leave the pattern intact.
            u_card.sector[450] = 8'h0C;      // FAT32 XINT13
            u_card.sector[454] = VOL_BASE[7:0];    // partition start LBA (LE)
            u_card.sector[455] = VOL_BASE[15:8];
            u_card.sector[456] = VOL_BASE[23:16];
            u_card.sector[457] = VOL_BASE[31:24];
            u_card.sector[458] = 8'h00;      // partition sector count = 0x00010000
            u_card.sector[459] = 8'h00;
            u_card.sector[460] = 8'h01;
            u_card.sector[461] = 8'h00;
            u_card.sector[510] = 8'h55;
            u_card.sector[511] = 8'hAA;
        end
    endtask

    task build_volume;
        integer c, k;
        begin
            // DBR (volume LBA 0)
            u_card.mk_fat32_dbr(16'd512, SPC, RSVD, NFAT, FATSZ, ROOTCLUS, TOTSEC, 1'b1);
            // FAT (volume LBA 1): FAT[2]=EOC, FAT[3..58]=next, FAT[59]=EOC
            u_card.vol_zero(VOL_FAT_LBA);
            u_card.vol_set_le(VOL_FAT_LBA, 16'd8, 32'h0FFF_FFFF, 3'd4);   // FAT[2]
            for (c = 3; c <= 58; c = c + 1)
                u_card.vol_set_le(VOL_FAT_LBA, c * 4, c + 1, 3'd4);
            u_card.vol_set_le(VOL_FAT_LBA, 16'd236, 32'h0FFF_FFFF, 3'd4); // FAT[59]
            // Root directory (volume LBA 2): 4 entries, then 0x00 terminator
            u_card.vol_zero(VOL_ROOT_LBA);
            u_card.mk_dir_entry(VOL_ROOT_LBA, 16'd0,   "SV0001  BMP", 8'h20, FILE_CLUS, FILE_SIZE);
            u_card.mk_dir_entry(VOL_ROOT_LBA, 16'd32,  "SV0002  BMP", 8'h20, FILE_CLUS, FILE_SIZE);
            u_card.mk_dir_entry(VOL_ROOT_LBA, 16'd64,  "SV0003  BMP", 8'h20, FILE_CLUS, FILE_SIZE);
            u_card.mk_dir_entry(VOL_ROOT_LBA, 16'd96,  "SV0004  BMP", 8'h20, FILE_CLUS, FILE_SIZE);
            // File first sector (volume LBA 34): header in the first 54 bytes,
            // the rest stays zero (vol_zero). Later sectors fall through to the
            // card model default pattern - see filebyte().
            u_card.vol_zero(VOL_FILE0_LBA);
            for (k = 0; k < 54; k = k + 1)
                u_card.vol_set(VOL_FILE0_LBA, k[15:0], bmp_hdr[k]);
            // MBR (card LBA 0 -> card model default sector[] area)
            mbr_set_card0;
        end
    endtask

    // ========================================================================
    // Monitors
    // ========================================================================
    // Directory-entry counter (scanner -> file_index)
    integer ent_count = 0;
    reg [87:0] ent0_name;
    reg [31:0] ent0_clus, ent0_size;
    reg [7:0]  ent0_attr;
    always @(posedge clk) begin
        if (rst_n && ent_valid && ent_ready) begin
            if (ent_count == 0) begin
                ent0_name = ent_name; ent0_attr = ent_attr;
                ent0_clus = ent_first_clus; ent0_size = ent_size;
            end
            ent_count = ent_count + 1;
        end
    end

    // file_streamer byte monitor: byte-for-byte against filebyte()
    integer fst_got = 0, fst_mism = 0, fst_sof_n = 0, fst_eof_n = 0;
    integer fst_first_bad = -1;
    always @(posedge clk) begin
        if (rst_n && fst_valid && bp_ready) begin
            if (fst_sof) fst_sof_n = fst_sof_n + 1;
            if (fst_data !== filebyte(fst_got)) begin
                fst_mism = fst_mism + 1;
                if (fst_first_bad < 0) begin
                    fst_first_bad = fst_got;
                    $display("[INFO] stream mismatch @%0d got=%02x want=%02x",
                             fst_got, fst_data, filebyte(fst_got));
                end
            end
            if (fst_eof) fst_eof_n = fst_eof_n + 1;
            fst_got = fst_got + 1;
        end
    end

    // Pixel monitor: every RGB565 pixel against exp565()
    integer pix_n = 0, pix_bad = 0;
    integer pix_sof_n = 0;
    always @(posedge clk) begin
        if (rst_n && bpu_valid) begin
            if (bpu_sof) pix_sof_n = pix_sof_n + 1;
            if (bpu_pixel !== exp565(pix_n)) begin
                pix_bad = pix_bad + 1;
                if (pix_bad <= 5)
                    $display("[INFO] pixel mismatch @%0d (x=%0d y=%0d) got=%04x want=%04x",
                             pix_n, bpu_x, bpu_y, bpu_pixel, exp565(pix_n));
            end
            pix_n = pix_n + 1;
        end
    end

    // Single-cycle pulses: latch them so checks after the fact are meaningful.
    reg idx_done_lat = 1'b0;
    reg bmp_cd_lat   = 1'b0;
    always @(posedge clk) begin
        if (rst_n && idx_done)       idx_done_lat <= 1'b1;
        if (rst_n && bmp_check_done) bmp_cd_lat   <= 1'b1;
    end

    // ========================================================================
    // Progress + watchdog
    // ========================================================================
    initial begin
        forever begin
            #50_000_000;
            $display("[PROG] t=%0t phase=%0d st_got=%0d st_mism=%0d pix=%0d pix_bad=%0d",
                     $time, phase, fst_got, fst_mism, pix_n, pix_bad);
        end
    end

    initial begin
        #1_500_000_000;
        $display("[FAIL] watchdog: no completion (phase=%0d st_got=%0d pix=%0d rd_state=%0d rd_to=%0b)",
                 phase, fst_got, pix_n, u_rd.dbg_state, rd_to);
        $display("[TB] mbr has=%0b base=%08x  boot done=%0b err=%0b  scan done=%0b dir_bad=%0b",
                 mp_has, mp_vol_base, bp_done, bp_err, scan_done, dir_bad);
        $display("[TB] idx_done=%0b file_cnt=%0d sel_valid=%0b  fst done=%0b err=%0b bytes=%0d",
                 idx_done, file_cnt, sel_valid, fst_done, fst_error, fst_bytes);
        $finish;
    end

    // ========================================================================
    // Main sequence
    // ========================================================================
    integer wait_cnt;
    reg     stop_after_scan;
    initial begin
        errors = 0;
        rst_n = 1'b0;
        init_start = 1'b0; mp_start = 1'b0; bp_start = 1'b0;
        scan_en = 1'b0; idx_clear = 1'b0; idx_commit = 1'b0;
        fst_start = 1'b0; fst_first_clus = 32'd0; fst_file_size = 32'd0;
        phase = PH_MBR;
        stop_after_scan = 1'b0;
        if ($test$plusargs("STOP_AFTER_SCAN")) stop_after_scan = 1'b1;

        // Build the card contents after the card model's initial block has run
        #500;
        build_volume;
        #100;
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        // ---- 1) SD initialization -----------------------------------------
        @(posedge clk); init_start = 1'b1;
        @(posedge clk); init_start = 1'b0;
        wait_cnt = 0;
        while (!(init_done || init_error) && wait_cnt < 4_000_000) begin
            @(posedge clk); wait_cnt = wait_cnt + 1;
        end
        repeat (5) @(posedge clk);
        check(init_done === 1'b1, "1) SD 初始化成功（CMD0/CMD8/ACMD41/CMD58）");

        // ---- 2) MBR -------------------------------------------------------
        phase = PH_MBR;
        @(posedge clk); mp_start = 1'b1;
        @(posedge clk); mp_start = 1'b0;
        wait_cnt = 0;
        while (!mp_done && wait_cnt < 4_000_000) begin @(posedge clk); wait_cnt = wait_cnt + 1; end
        repeat (5) @(posedge clk);
        check(mp_done === 1'b1,               "2) mbr_parser 完成");
        check(mp_ec   === `ERR_NONE,          "3) mbr_parser 无错");
        check(mp_has  === 1'b1,               "4) MBR 有效（分区表 + 签名）");
        check(mp_vol_base === VOL_BASE,       "5) 卷基址 = 分区起始 LBA = 16");
        check(u_card.o_arg === 32'd0,         "6) mbr_parser 读的是卡 0 号扇区");

        // ---- 3) FAT32 mount ----------------------------------------------
        phase = PH_BOOT;
        @(posedge clk); bp_start = 1'b1;
        @(posedge clk); bp_start = 1'b0;
        wait_cnt = 0;
        while (!(bp_done || bp_err) && wait_cnt < 4_000_000) begin @(posedge clk); wait_cnt = wait_cnt + 1; end
        repeat (5) @(posedge clk);
        check(bp_done === 1'b1,               "7) fat32_boot_parser 挂载完成");
        check(bp_err  === 1'b0,               "8) 挂载无错");
        check(bp_bps  === 16'd512,            "9) BPB BytsPerSec = 512");
        check(bp_spc  === SPC,                "10) BPB SecPerClus = 32");
        check(bp_nfat === NFAT,               "11) BPB NumFATs = 1");
        check(bp_fat_lba  === 32'd1,          "12) FAT 起始（卷内 LBA）= 1");
        check(bp_data_lba === 32'd2,          "13) 数据区起始 = 2");
        check(bp_root_lba === 32'd2,          "14) 根目录起始 = 2（RootClus=2）");
        check(bp_tot_clus === 32'd63,         "15) total_clus = (2048-2)/32 = 63");

        // ---- 4) root directory scan + file_index --------------------------
        phase = PH_SCAN;
        @(posedge clk); idx_clear = 1'b1;
        @(posedge clk); idx_clear = 1'b0;
        @(posedge clk); scan_en = 1'b1;
        @(posedge clk); scan_en = 1'b0;
        wait_cnt = 0;
        while (!scan_done && wait_cnt < 8_000_000) begin @(posedge clk); wait_cnt = wait_cnt + 1; end
        repeat (5) @(posedge clk);
        check(scan_done === 1'b1,             "16) 根目录扫描完成");
        check(dir_bad   === 1'b0,             "17) 目录结构正常");
        check(dn_ec     === `ERR_NONE,        "18) 扫描无错");
        check(ent_count === 4,                "19) 扫描抛出 4 条目录项");
        check(ent0_name === "SV0001  BMP",    "20) 第 0 条名字 = SV0001.BMP");
        check(ent0_attr === 8'h20,            "21) 第 0 条属性 = 0x20（归档）");
        check(ent0_clus === FILE_CLUS,        "22) 第 0 条首簇 = 3");
        check(ent0_size === FILE_SIZE,        "23) 第 0 条文件大小 = 921654");

        @(posedge clk); idx_commit = 1'b1;
        @(posedge clk); idx_commit = 1'b0;
        wait_cnt = 0;
        while (!idx_done && wait_cnt < 100_000) begin @(posedge clk); wait_cnt = wait_cnt + 1; end
        repeat (5) @(posedge clk);
        check(idx_done_lat === 1'b1,          "24) file_index 提交完成");
        check(file_cnt  === 4'd4,             "25) 索引表里有 4 幅 BMP");
        check(file_valid=== 4'b1111,          "26) 四槽全部有效");
        check(insufficient === 1'b0,          "27) 文件数足够（不是 insufficient）");
        check(sel_valid === 1'b1,             "28) 槽 0 有效");
        check(sel_first_clus === FILE_CLUS,   "29) 槽 0 首簇 = 3");
        check(sel_size === FILE_SIZE,         "30) 槽 0 大小 = 921654");
        check(bmp_seen === 16'd4,             "31) bmp_seen = 4");

        if (stop_after_scan) begin
            $display("[TB] STOP_AFTER_SCAN set: front half verified, skipping stream.");
            report;
            $finish;
        end

        // ---- 5) file_streamer -> bmp_parser -> bmp_unpack -----------------
        phase = PH_STREAM;
        @(posedge clk);
        fst_first_clus = sel_first_clus;
        fst_file_size  = sel_size;
        fst_start      = 1'b1;
        @(posedge clk);
        fst_start      = 1'b0;

        wait_cnt = 0;
        while (!(pix_n >= PIX_TOTAL && fst_done) && !bpu_error && !fst_error && !bmp_check_error
               && wait_cnt < 200_000_000) begin
            @(posedge clk); wait_cnt = wait_cnt + 1;
        end
        repeat (20) @(posedge clk);

        // stream bytes
        check(fst_got  === FILE_SIZE,         "32) file_streamer 恰好输出 921654 字节");
        check(fst_mism === 0,                 "33) ★ 921654 字节逐字节与卡上文件一致（0 错）");
        check(fst_sof_n === 1,                "34) sof 恰好 1 次");
        check(fst_eof_n === 1,                "35) eof 恰好 1 次");
        check(fst_done === 1'b1,              "36) file_streamer 结束");
        check(fst_error === 1'b0,             "37) file_streamer 无错");

        // BMP header
        check(bmp_cd_lat === 1'b1,            "38) bmp_parser 头解析完成");
        check(bmp_check_error === 1'b0,       "39) BMP 头校验通过");
        check(bmp_width  === 16'd640,         "40) 解析宽度 = 640");
        check(bmp_top_down === 1'b1,          "41) top-down（负高度）");
        check(bmp_bpp === 8'd24,              "42) 位深 = 24");

        // pixels
        check(bpu_error === 1'b0,             "43) bmp_unpack 无错");
        check(pix_n === PIX_TOTAL,            "44) 输出像素数 = 307200");
        check(pix_bad === 0,                  "45) ★ 307200 个 RGB565 像素逐个与卡上文件一致（0 错）");
        check(pix_sof_n === 1,                "46) img_sof 恰好 1 次");

        report;
        $finish;
    end

    task report;
        begin
            $display("============================================");
            if (errors == 0) $display("  ALL PASS (stream=%0d bytes, pix=%0d)", fst_got, pix_n);
            else             $display("  FAILED: %0d check(s)", errors);
            $display("  stream bytes=%0d mismatch=%0d first_bad=%0d", fst_got, fst_mism, fst_first_bad);
            $display("  pixels=%0d bad=%0d", pix_n, pix_bad);
            $display("============================================");
        end
    endtask

endmodule
