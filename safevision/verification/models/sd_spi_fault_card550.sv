


`include "safevision_defs.vh"

module sd_spi_fault_card550 #(
    parameter [31:0] OCR_VALUE       = 32'hC0FF_8000,
    parameter [7:0]  SLOW_INIT_POLLS = 8'd0,
    parameter        CMD8_ILLEGAL    = 1'b0,


    parameter [7:0]  CMD0_R1         = 8'h01,


    parameter [2:0]  CMD0_BAD_TRIES  = 3'd0,


    parameter [31:0] VOL_BASE        = 32'd0,
    parameter integer VOL_SECTORS = 64
)(
    input  wire        sclk,
    input  wire        cs_n,
    input  wire        mosi,
    output wire        miso,


    input wire i_crc_bad,
    input  wire        i_dead,


    output reg  [5:0]  o_cmd,
    output reg  [31:0] o_arg,
    output reg  [31:0] o_acmd41_arg,
    output reg  [7:0]  o_cmd_cnt,
    output reg  [7:0]  o_acmd41_cnt,
    output reg         o_cmd_valid
);


    reg [7:0] sector [0:511];
    reg [7:0] rd_buf [0:511];
    reg [7:0] vol    [0:VOL_SECTORS*512-1];
    reg       vol_used [0:VOL_SECTORS-1];
    integer   i;
    integer   j;
    integer   kk;
    initial begin
        for (i = 0; i < 512; i = i + 1)
            sector[i] = i[7:0] + 8'h11;
        for (i = 0; i < VOL_SECTORS; i = i + 1)
            vol_used[i] = 1'b0;
    end


    task vol_zero;
        input [31:0] lba;
        begin
            if (lba < VOL_SECTORS) begin
                for (kk = 0; kk < 512; kk = kk + 1)
                    vol[lba*32'd512 + kk] = 8'h00;
                vol_used[lba] = 1'b1;
            end else begin
                $display("[card_model] vol_zero: LBA %0d 超出模型支持范围(VOL_SECTORS)", lba);
            end
        end
    endtask


    task vol_set;
        input [31:0] lba;
        input [15:0] off;
        input [7:0]  val;
        begin
            if (lba < VOL_SECTORS) begin
                vol[lba*32'd512 + off] = val;
                vol_used[lba] = 1'b1;
            end else begin
                $display("[card_model] vol_set: LBA %0d 超出模型支持范围(VOL_SECTORS)", lba);
            end
        end
    endtask


    task vol_set_le;
        input [31:0] lba;
        input [15:0] off;
        input [31:0] val;
        input [2:0]  len;
        begin
            vol_set(lba, off + 16'd0, val[7:0]);
            if (len >= 3'd2) vol_set(lba, off + 16'd1, val[15:8]);
            if (len >= 3'd4) begin
                vol_set(lba, off + 16'd2, val[23:16]);
                vol_set(lba, off + 16'd3, val[31:24]);
            end
        end
    endtask


    task mk_fat32_dbr;
        input [15:0] bytes_per_sec;
        input [7:0]  sec_per_clus;
        input [15:0] reserved_sec;
        input [7:0]  num_fats;
        input [31:0] fat_sz32;
        input [31:0] root_clus;
        input [31:0] total_sec32;
        input        as_fat32;
        begin
            vol_zero(32'd0);
            vol_set(32'd0, 16'd0, 8'hEB);
            vol_set(32'd0, 16'd1, 8'h58);
            vol_set(32'd0, 16'd2, 8'h90);
            vol_set(32'd0, 16'd3, 8'h4D);
            vol_set(32'd0, 16'd4, 8'h53);
            vol_set(32'd0, 16'd5, 8'h44);
            vol_set(32'd0, 16'd6, 8'h4F);
            vol_set(32'd0, 16'd7, 8'h53);
            vol_set(32'd0, 16'd8, 8'h35);
            vol_set(32'd0, 16'd9, 8'h2E);
            vol_set(32'd0, 16'd10, 8'h30);

            vol_set_le(32'd0, 16'd11, {16'd0, bytes_per_sec}, 3'd2);
            vol_set(32'd0, 16'd13, sec_per_clus);
            vol_set_le(32'd0, 16'd14, {16'd0, reserved_sec}, 3'd2);
            vol_set(32'd0, 16'd16, num_fats);
            vol_set_le(32'd0, 16'd17, 32'd0, 3'd2);
            vol_set_le(32'd0, 16'd19, 32'd0, 3'd2);
            vol_set(32'd0, 16'd21, 8'hF8);
            vol_set_le(32'd0, 16'd22, 32'd0, 3'd2);
            vol_set_le(32'd0, 16'd24, 32'd63,  3'd2);
            vol_set_le(32'd0, 16'd26, 32'd255, 3'd2);
            vol_set_le(32'd0, 16'd28, 32'd0,   3'd4);
            vol_set_le(32'd0, 16'd32, total_sec32, 3'd4);

            vol_set_le(32'd0, 16'd36, fat_sz32, 3'd4);
            vol_set_le(32'd0, 16'd40, 32'd0,    3'd2);
            vol_set_le(32'd0, 16'd42, 32'd0,    3'd2);
            vol_set_le(32'd0, 16'd44, root_clus, 3'd4);
            vol_set_le(32'd0, 16'd48, 32'd1,    3'd2);
            vol_set_le(32'd0, 16'd50, 32'd6,    3'd2);
            vol_set_le(32'd0, 16'd64, 32'd0,    3'd1);
            if (!as_fat32) begin

                vol_set_le(32'd0, 16'd17, 32'd512, 3'd2);
                vol_set_le(32'd0, 16'd19, 32'd256, 3'd2);
                vol_set_le(32'd0, 16'd22, 32'd64,  3'd2);
            end
            vol_set(32'd0, 16'd510, 8'h55);
            vol_set(32'd0, 16'd511, 8'hAA);
        end
    endtask


    task mk_dir_entry;
        input [31:0] lba;
        input [15:0] off;
        input [87:0] name83;
        input [7:0]  attr;
        input [31:0] first_clus;
        input [31:0] file_size;
        begin
            vol_set(lba, off + 16'd0,  name83[87:80]);
            vol_set(lba, off + 16'd1,  name83[79:72]);
            vol_set(lba, off + 16'd2,  name83[71:64]);
            vol_set(lba, off + 16'd3,  name83[63:56]);
            vol_set(lba, off + 16'd4,  name83[55:48]);
            vol_set(lba, off + 16'd5,  name83[47:40]);
            vol_set(lba, off + 16'd6,  name83[39:32]);
            vol_set(lba, off + 16'd7,  name83[31:24]);
            vol_set(lba, off + 16'd8,  name83[23:16]);
            vol_set(lba, off + 16'd9,  name83[15:8]);
            vol_set(lba, off + 16'd10, name83[7:0]);
            vol_set(lba, off + 16'd11, attr);


            vol_set(lba, off + 16'd20, first_clus[23:16]);
            vol_set(lba, off + 16'd21, first_clus[31:24]);
            vol_set(lba, off + 16'd26, first_clus[7:0]);
            vol_set(lba, off + 16'd27, first_clus[15:8]);
            vol_set(lba, off + 16'd28, file_size[7:0]);
            vol_set(lba, off + 16'd29, file_size[15:8]);
            vol_set(lba, off + 16'd30, file_size[23:16]);
            vol_set(lba, off + 16'd31, file_size[31:24]);
        end
    endtask


    task mk_dir_fill;
        input [31:0] lba;
        input [87:0] name83;
        input [7:0]  attr;
        input [31:0] first_clus;
        input [31:0] file_size;
        integer e;
        begin
            vol_zero(lba);
            for (e = 0; e < 16; e = e + 1)
                mk_dir_entry(lba, e*32, name83, attr, first_clus, file_size);
        end
    endtask


    function [15:0] crc16_of_rdbuf;
        input [15:0] len;
        integer    k;
        reg [15:0] c;
        begin
            c = 16'h0;
            for (k = 0; k < len; k = k + 1) begin
                c = c ^ {rd_buf[k], 8'h00};
                for (j = 0; j < 8; j = j + 1)
                    c = c[15] ? ((c << 1) ^ 16'h1021) : (c << 1);
            end
            crc16_of_rdbuf = c;
        end
    endfunction


    reg  [7:0]  tx_sh;
    reg  [7:0]  rx_sh;
    reg  [3:0]  bitc;

    reg  [47:0] cmd_buf;
    reg  [2:0]  cmd_cnt;
    reg  [2:0]  cmd0_seen;
    reg  [5:0]  cur_cmd;
    reg  [31:0] cur_arg;


    reg  [31:0] cur_rel;
    reg         in_resp;
    reg         skip_byte;
    reg  [15:0] rp;
    reg  [15:0] rlen;
    reg  [15:0] crc_val;

    assign miso = tx_sh[7];


    task do_resp_byte;
        output [7:0] b;
        begin
            b    = 8'hFF;
            rlen = 16'd1;

            if (i_dead) begin

                b = 8'hFF;
            end else begin
            case (cur_cmd)
                `SD_CMD0: begin
                    rlen = 16'd1;


                    if (rp == 16'd0)
                        b = (cmd0_seen <= CMD0_BAD_TRIES) ? 8'h02 : CMD0_R1;
                end
                `SD_CMD8: begin
                    rlen = 16'd5;
                    case (rp)

                        16'd0: b = CMD8_ILLEGAL ? 8'h05 : 8'h01;
                        16'd1: b = 8'h00;
                        16'd2: b = 8'h00;
                        16'd3: b = 8'h01;
                        16'd4: b = CMD8_ILLEGAL ? 8'hFF : 8'hAA;
                        default: b = 8'hFF;
                    endcase
                end
                `SD_CMD55: begin
                    rlen = 16'd1;
                    if (rp == 16'd0) b = 8'h00;
                end
                `SD_ACMD41: begin
                    rlen = 16'd1;

                    if (rp == 16'd0)
                        b = (o_acmd41_cnt <= SLOW_INIT_POLLS) ? 8'h01 : 8'h00;
                end
                `SD_CMD58: begin
                    rlen = 16'd5;
                    case (rp)
                        16'd0: b = 8'h00;
                        16'd1: b = OCR_VALUE[31:24];
                        16'd2: b = OCR_VALUE[23:16];
                        16'd3: b = OCR_VALUE[15:8];
                        16'd4: b = OCR_VALUE[7:0];
                        default: b = 8'hFF;
                    endcase
                end
                `SD_CMD17: begin
                    rlen = 16'd516;
                    if (rp == 16'd0)            b = 8'h00;
                    else if (rp == 16'd1)       b = `SD_TOKEN_DATA_START;
                    else if (rp <= 16'd513)     b = rd_buf[rp - 16'd2];
                    else if (rp == 16'd514)     b = crc_val[15:8];
                    else                        b = crc_val[7:0];
                end
                default: begin
                    rlen = 16'd1;
                    b    = 8'hFF;
                end
            endcase
            end
        end
    endtask


    always @(sclk or posedge cs_n) begin
        if (cs_n) begin

            bitc      = 4'd0;
            rx_sh     = 8'hFF;
            tx_sh     = 8'hFF;
            cmd_cnt   = 3'd0;
            cmd_buf   = 48'h0;
            in_resp   = 1'b0;
            skip_byte = 1'b1;
            rp        = 16'd0;
            rlen      = 16'd0;
            o_cmd_valid  = 1'b0;
            o_acmd41_cnt = 8'd0;
        end else if (sclk == 1'b1) begin

            rx_sh = {rx_sh[6:0], mosi};
            bitc  = bitc + 4'd1;
        end else begin

            if (bitc == 4'd8) begin

                bitc        = 4'd0;
                o_cmd_valid = 1'b0;

                if (skip_byte) begin

                    skip_byte = 1'b0;
                    tx_sh     = 8'hFF;
                end else if (!in_resp) begin

                    cmd_buf = {cmd_buf[39:0], rx_sh};
                    cmd_cnt = cmd_cnt + 3'd1;
                    if (cmd_cnt == 3'd6) begin


                        cur_cmd     = cmd_buf[45:40];
                        cur_arg     = cmd_buf[39:8];
                        cur_rel     = cur_arg - VOL_BASE;

                        if (cur_cmd == `SD_CMD0) cmd0_seen = cmd0_seen + 3'd1;
                        if (cur_cmd == `SD_CMD17) begin


                            for (kk = 0; kk < 512; kk = kk + 1)
                                rd_buf[kk] = ((cur_arg >= VOL_BASE) &&
                                              (cur_rel < VOL_SECTORS) &&
                                              vol_used[cur_rel])
                                             ? vol[cur_rel*32'd512 + kk]
                                             : sector[kk];
                            crc_val = crc16_of_rdbuf(16'd512);
                            if(i_crc_bad&&cur_rel==4)crc_val=crc_val^16'd1;
                        end
                        in_resp     = 1'b1;
                        rp          = 16'd0;
                        o_cmd       = cur_cmd;
                        o_arg       = cur_arg;
                        o_cmd_cnt   = o_cmd_cnt + 8'd1;
                        o_cmd_valid = 1'b1;
                        if (cur_cmd == `SD_ACMD41) begin
                            o_acmd41_cnt = o_acmd41_cnt + 8'd1;
                            o_acmd41_arg = cur_arg;
                        end

                        do_resp_byte(tx_sh);
                        rp = rp + 16'd1;
                    end else begin
                        tx_sh = 8'hFF;
                    end
                end else begin

                    if (rp >= rlen) begin

                        in_resp   = 1'b0;
                        cmd_cnt   = 3'd0;
                        cmd_buf   = 48'h0;
                        rp        = 16'd0;
                        skip_byte = 1'b1;
                        tx_sh     = 8'hFF;
                    end else begin
                        do_resp_byte(tx_sh);
                        rp = rp + 16'd1;
                    end
                end
            end else begin

                tx_sh = {tx_sh[6:0], 1'b1};
            end
        end
    end

    initial begin
        cmd_cnt     = 3'd0;
        cmd0_seen   = 3'd0;
        cmd_buf     = 48'h0;
        in_resp     = 1'b0;
        skip_byte   = 1'b1;
        rp          = 16'd0;
        rlen        = 16'd0;
        bitc        = 4'd0;
        rx_sh       = 8'hFF;
        tx_sh       = 8'hFF;
        cur_cmd     = 6'h0;
        cur_arg     = 32'h0;
        cur_rel     = 32'h0;
        crc_val     = 16'h0;
        o_cmd       = 6'h0;
        o_arg       = 32'h0;
        o_acmd41_arg= 32'h0;
        o_cmd_cnt   = 8'h0;
        o_acmd41_cnt= 8'h0;
        o_cmd_valid = 1'b0;
    end

endmodule
