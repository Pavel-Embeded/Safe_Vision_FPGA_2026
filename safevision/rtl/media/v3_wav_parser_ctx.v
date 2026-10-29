


`include "safevision_defs.vh"

module v3_wav_parser_ctx (
    input wire context_load,
    input wire [444:0] context_in,
    output wire [444:0] context_out,
    input wire context_enable,
    input  wire        clk,
    input  wire        rst_n,


    input  wire        start,
    input  wire [31:0] first_clus,

    input  wire [31:0] file_size,
    input  wire [7:0]  track_id,


    input  wire [7:0]  din,
    input  wire        din_valid,
    output wire        din_ready,
    input  wire        din_eof,


    output reg  [15:0] fmt_code,
    output reg  [15:0] num_channels,
    output reg  [31:0] sample_rate,
    output reg  [15:0] bits_per_sample,
    output reg  [31:0] data_offset,
    output reg  [31:0] data_size,
    output reg         header_done,


    output reg  [15:0] pcm_l,
    output reg  [15:0] pcm_r,
    output reg  [31:0] sample,
    output reg         pcm_valid,
    input  wire        pcm_ready,
    output reg         pcm_end,


    output reg  [7:0]  track_id_o,
    output reg         wav_error,
    output reg  [7:0]  err_code,
    output reg  [7:0]  err_detail,
    output reg         fallback_req,
    output reg  [31:0] samples_rd,
    output reg  [3:0]  dbg_state
);


    localparam [31:0] ID_RIFF = 32'h46464952;
    localparam [31:0] ID_WAVE = 32'h45564157;
    localparam [31:0] ID_FMT  = 32'h20746D66;
    localparam [31:0] ID_DATA = 32'h61746164;


    localparam [2:0] W_IDLE  = 3'd0,
                     W_HDR   = 3'd1,
                     W_CHUNK = 3'd2,
                     W_FMT   = 3'd3,
                     W_SKIP  = 3'd4,
                     W_DATA  = 3'd5,
                     W_END   = 3'd6,
                     W_ERR   = 3'd7;

    reg  [2:0]  state;
    reg  [31:0] byte_cnt;
    reg  [3:0]  hdr_idx;
    reg  [31:0] riff_r;
    reg  [31:0] riff_sz;
    reg  [31:0] wave_r;
    reg  [2:0]  chunk_idx;
    reg  [31:0] cid;
    reg  [31:0] csz;
    reg  [4:0]  fmt_idx;
    reg  [31:0] fmt_size;
    reg  [15:0] f_code;
    reg  [15:0] f_ch;
    reg  [31:0] f_rate;
    reg  [15:0] f_bits;
    reg         fmt_seen;
    reg  [31:0] skip_cnt;
    reg         pad_pend;
    reg  [31:0] dleft;
    reg  [1:0]  phase;
    reg  [7:0]  l_lo, l_hi, r_lo;


    wire [31:0] csz_nxt  = {din, csz[31:8]};
    wire [31:0] wave_nxt = {din, wave_r[31:8]};
    wire [15:0] f_bits_nxt = {din, f_bits[15:8]};

    wire [15:0] bits_v = (fmt_idx == 5'd15) ? f_bits_nxt : f_bits;


    wire [32:0] riff_decl_end={1'b0,riff_sz}+33'd8;
    wire [32:0] next_byte_pos={1'b0,byte_cnt}+33'd1;
    wire [33:0] chunk_extent={2'd0,byte_cnt}+34'd1+{2'd0,csz_nxt}+csz_nxt[0];
    wire fmt_valid_now=f_code==1&&f_ch==2&&f_rate==48000&&bits_v==16;
    wire terminal_chunk=(state==W_DATA&&dleft==1&&phase==3)||
     (riff_r[0]&&((state==W_SKIP&&((skip_cnt==1&&!pad_pend)||(skip_cnt==0&&pad_pend)))||
      (state==W_CHUNK&&chunk_idx==7&&csz_nxt==0&&cid!=ID_FMT&&cid!=ID_DATA)||
      (state==W_FMT&&fmt_idx==15&&fmt_size==16&&fmt_valid_now)));
    wire        byte_taken = din_valid && din_ready;

    assign din_ready = (state == W_DATA) ? !pcm_valid
                     : ((state == W_HDR) || (state == W_CHUNK) ||
                        (state == W_FMT) || (state == W_SKIP) || (state == W_END));


    assign context_out={sample,pcm_valid,wav_error,state,byte_cnt,hdr_idx,riff_r,riff_sz,wave_r,chunk_idx,cid,csz,fmt_idx,fmt_size,f_code,f_ch,f_rate,f_bits,fmt_seen,skip_cnt,pad_pend,dleft,phase,l_lo,l_hi,r_lo};
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= W_IDLE;
            byte_cnt       <= 32'd0;
            hdr_idx        <= 4'd0;
            riff_r         <= 32'd0;
            riff_sz        <= 32'd0;
            wave_r         <= 32'd0;
            chunk_idx      <= 3'd0;
            cid            <= 32'd0;
            csz            <= 32'd0;
            fmt_idx        <= 5'd0;
            fmt_size       <= 32'd0;
            f_code         <= 16'd0;
            f_ch           <= 16'd0;
            f_rate         <= 32'd0;
            f_bits         <= 16'd0;
            fmt_seen       <= 1'b0;
            skip_cnt       <= 32'd0;
            pad_pend       <= 1'b0;
            dleft          <= 32'd0;
            phase          <= 2'd0;
            l_lo           <= 8'h00;
            l_hi           <= 8'h00;
            r_lo           <= 8'h00;
            fmt_code       <= 16'd0;
            num_channels   <= 16'd0;
            sample_rate    <= 32'd0;
            bits_per_sample<= 16'd0;
            data_offset    <= 32'd0;
            data_size      <= 32'd0;
            header_done    <= 1'b0;
            pcm_l          <= 16'd0;
            pcm_r          <= 16'd0;
            sample         <= 32'd0;
            pcm_valid      <= 1'b0;
            pcm_end        <= 1'b0;
            track_id_o     <= 8'd0;
            wav_error      <= 1'b0;
            err_code       <= `ERR_NONE;
            err_detail     <= `DET_NONE;
            fallback_req   <= 1'b0;
            samples_rd     <= 32'd0;
            dbg_state      <= W_IDLE;
        end else if(context_load)begin
            {sample,pcm_valid,wav_error,state,byte_cnt,hdr_idx,riff_r,riff_sz,wave_r,chunk_idx,cid,csz,fmt_idx,fmt_size,f_code,f_ch,f_rate,f_bits,fmt_seen,skip_cnt,pad_pend,dleft,phase,l_lo,l_hi,r_lo} <= context_in;
        end else if(context_enable) begin
            dbg_state   <= state;
            header_done <= 1'b0;


            if (pcm_valid && pcm_ready) begin
                pcm_valid <= 1'b0;
                pcm_end   <= 1'b0;
            end


            if (start) begin
                state          <= W_HDR;
                byte_cnt       <= 32'd0;
                hdr_idx        <= 4'd0;
                riff_r         <= 32'd0;
                riff_sz        <= 32'd0;
                wave_r         <= 32'd0;
                chunk_idx      <= 3'd0;
                cid            <= 32'd0;
                csz            <= 32'd0;
                fmt_idx        <= 5'd0;
                fmt_size       <= 32'd0;
                f_code         <= 16'd0;
                f_ch           <= 16'd0;
                f_rate         <= 32'd0;
                f_bits         <= 16'd0;
                fmt_seen       <= 1'b0;
                skip_cnt       <= 32'd0;
                pad_pend       <= 1'b0;
                dleft          <= 32'd0;
                phase          <= 2'd0;
                l_lo           <= 8'h00;
                l_hi           <= 8'h00;
                r_lo           <= 8'h00;
                wav_error      <= 1'b0;
                err_code       <= `ERR_NONE;
                err_detail     <= `DET_NONE;
                fallback_req   <= 1'b0;
                pcm_valid      <= 1'b0;
                pcm_end        <= 1'b0;
                samples_rd     <= 32'd0;
                track_id_o     <= track_id;
            end else begin
            case (state)

            W_IDLE: ;

            W_HDR: begin
                if (byte_taken) begin
                    byte_cnt <= byte_cnt + 32'd1;
                    case (hdr_idx)
                        4'd0, 4'd1, 4'd2, 4'd3 : riff_r  <= {din, riff_r[31:8]};
                        4'd4, 4'd5, 4'd6, 4'd7 : riff_sz <= {din, riff_sz[31:8]};
                        4'd8, 4'd9, 4'd10,4'd11: wave_r  <= {din, wave_r[31:8]};
                        default: ;
                    endcase

                    if (hdr_idx == 4'd11) begin

                        if ((riff_r == ID_RIFF) && (wave_nxt == ID_WAVE) && riff_sz>=4 && !riff_decl_end[32] && ((file_size==0)||(riff_decl_end<={1'b0,file_size}))) begin
                            riff_r <= 0;
                            state     <= W_CHUNK;
                            chunk_idx <= 3'd0;
                        end else begin
                            wav_error    <= 1'b1;
                            err_code     <= `ERR_WAV;
                            err_detail   <= `DET_WAV_RIFF;
                            fallback_req <= 1'b1;
                            state        <= W_ERR;
                        end
                    end else begin
                        hdr_idx <= hdr_idx + 4'd1;
                    end
                end
            end

            W_CHUNK: begin
                if (byte_taken) begin
                    byte_cnt <= byte_cnt + 32'd1;
                    case (chunk_idx)
                        3'd0,3'd1,3'd2,3'd3 : cid <= {din, cid[31:8]};
                        3'd4,3'd5,3'd6,3'd7 : csz <= {din, csz[31:8]};
                        default: ;
                    endcase

                    if (chunk_idx == 3'd7) begin

                        if (chunk_extent>{1'b0,riff_decl_end} || ((file_size!=0)&&(chunk_extent>{2'd0,file_size}))) begin
                            wav_error<=1;err_code<=`ERR_WAV;err_detail<=`DET_WAV_RIFF;fallback_req<=1;state<=W_ERR;
                        end else if (cid == ID_FMT) begin
                            if (csz_nxt < 32'd16) begin

                                wav_error    <= 1'b1;
                                err_code     <= `ERR_WAV;
                                err_detail   <= `DET_WAV_RIFF;
                                fallback_req <= 1'b1;
                                state        <= W_ERR;
                            end else begin
                                state    <= W_FMT;
                                fmt_idx  <= 5'd0;
                                fmt_size <= csz_nxt;
                                f_code   <= 16'd0;
                                f_ch     <= 16'd0;
                                f_rate   <= 32'd0;
                                f_bits   <= 16'd0;
                            end
                        end else if (cid == ID_DATA) begin
                            if (csz_nxt==0||csz_nxt[1:0]!=0) begin
                                wav_error<=1;err_code<=`ERR_WAV;err_detail<=`DET_WAV_FMT;fallback_req<=1;state<=W_ERR;
                            end else if (!fmt_seen) begin

                                wav_error    <= 1'b1;
                                err_code     <= `ERR_WAV;
                                err_detail   <= `DET_WAV_RIFF;
                                fallback_req <= 1'b1;
                                state        <= W_ERR;
                            end else if ((file_size != 32'd0) &&
                                         (chunk_extent > {2'd0,file_size})) begin

                                wav_error    <= 1'b1;
                                err_code     <= `ERR_WAV;
                                err_detail   <= `DET_WAV_RIFF;
                                fallback_req <= 1'b1;
                                state        <= W_ERR;
                            end else begin
                                riff_r[0] <= 1;
                                data_size   <= csz_nxt;

                                data_offset <= byte_cnt + 32'd1;
                                dleft       <= csz_nxt;
                                phase       <= 2'd0;
                                state       <= W_DATA;
                            end
                        end else begin

                            if (csz_nxt == 32'd0) begin
                                chunk_idx <= 3'd0;
                            end else begin
                                skip_cnt <= csz_nxt;
                                pad_pend <= csz_nxt[0];
                                state    <= W_SKIP;
                            end
                        end
                    end else begin
                        chunk_idx <= chunk_idx + 3'd1;
                    end
                end
            end

            W_FMT: begin
                if (byte_taken) begin
                    byte_cnt <= byte_cnt + 32'd1;
                    case (fmt_idx)
                        5'd0, 5'd1           : f_code  <= {din, f_code[15:8]};
                        5'd2, 5'd3           : f_ch    <= {din, f_ch[15:8]};
                        5'd4, 5'd5, 5'd6, 5'd7  : f_rate <= {din, f_rate[31:8]};
                        5'd8, 5'd9, 5'd10,5'd11 : ;
                        5'd12,5'd13          : ;
                        5'd14,5'd15          : f_bits  <= {din, f_bits[15:8]};
                        default: ;
                    endcase

                    if (fmt_idx == 5'd15) begin

                        header_done   <= 1'b1;
                        fmt_code      <= f_code;
                        num_channels  <= f_ch;
                        sample_rate   <= f_rate;
                        bits_per_sample <= bits_v;

                        if (f_code != 16'd1) begin
                            wav_error    <= 1'b1;
                            err_code     <= `ERR_WAV;
                            err_detail   <= `DET_WAV_PCM;
                            fallback_req <= 1'b1;
                            state        <= W_ERR;
                        end else if (f_ch != 16'd2) begin
                            wav_error    <= 1'b1;
                            err_code     <= `ERR_WAV;
                            err_detail   <= `DET_WAV_FMT;
                            fallback_req <= 1'b1;
                            state        <= W_ERR;
                        end else if (f_rate != 32'd48000) begin
                            wav_error    <= 1'b1;
                            err_code     <= `ERR_WAV;
                            err_detail   <= `DET_WAV_RATE;
                            fallback_req <= 1'b1;
                            state        <= W_ERR;
                        end else if (bits_v != 16'd16) begin
                            wav_error    <= 1'b1;
                            err_code     <= `ERR_WAV;
                            err_detail   <= `DET_WAV_FMT;
                            fallback_req <= 1'b1;
                            state        <= W_ERR;
                        end else begin
                            fmt_seen  <= 1'b1;
                            if(fmt_size>16)begin
                                skip_cnt<=fmt_size-32'd16;pad_pend<=fmt_size[0];state<=W_SKIP;
                            end else begin state<=W_CHUNK;chunk_idx<=0;end
                        end
                    end else begin
                        fmt_idx <= fmt_idx + 5'd1;
                    end
                end
            end

            W_SKIP: begin
                if (byte_taken) begin
                    byte_cnt <= byte_cnt + 32'd1;
                    if (skip_cnt != 32'd0) begin
                        skip_cnt <= skip_cnt - 32'd1;
                        if ((skip_cnt == 32'd1) && !pad_pend) begin
                            state     <= W_CHUNK;
                            chunk_idx <= 3'd0;
                        end
                    end else if (pad_pend) begin
                        pad_pend <= 1'b0;
                        state    <= W_CHUNK;
                        chunk_idx <= 3'd0;
                    end
                end
            end

            W_DATA: begin
                if (byte_taken) begin
                    byte_cnt <= byte_cnt + 32'd1;
                    dleft    <= dleft - 32'd1;
                    case (phase)
                        2'd0: begin l_lo <= din;             phase <= 2'd1; end
                        2'd1: begin l_hi <= din;             phase <= 2'd2; end
                        2'd2: begin r_lo <= din;             phase <= 2'd3; end
                        2'd3: begin

                            pcm_l      <= {l_hi, l_lo};
                            pcm_r      <= {din, r_lo};
                            sample     <= {din, r_lo, l_hi, l_lo};
                            pcm_valid  <= 1'b1;
                            pcm_end    <= (dleft == 32'd1);
                            samples_rd <= samples_rd + 32'd1;
                            phase      <= 2'd0;
                        end
                    endcase

                    if (dleft == 32'd1) begin
                        state <= W_CHUNK;chunk_idx<=0;
                    end
                end
            end

            W_END: begin

            end
            W_ERR: begin
                wav_error    <= 1'b1;
                fallback_req <= 1'b1;
            end
            default: state <= W_IDLE;
            endcase


            if(byte_taken&&state!=W_HDR&&state!=W_END&&next_byte_pos==riff_decl_end)begin
                if(terminal_chunk)state<=W_END;
                else begin wav_error<=1;pcm_valid<=0;err_code<=`ERR_WAV;err_detail<=`DET_WAV_RIFF;fallback_req<=1;state<=W_ERR;end
            end
            if (byte_taken && din_eof && state!=W_END &&
                !(terminal_chunk && next_byte_pos==riff_decl_end)) begin
                pcm_valid<=0;
                wav_error    <= 1'b1;
                err_code     <= `ERR_WAV;
                err_detail   <= `DET_WAV_RIFF;
                fallback_req <= 1'b1;
                state        <= W_ERR;
            end
            end
        end
    end

endmodule
