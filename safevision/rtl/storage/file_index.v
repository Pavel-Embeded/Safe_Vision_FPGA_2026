


`include "safevision_defs.vh"

module file_index #(parameter integer CURSOR_MODE=0,CANDIDATE_SLOTS=4) (
    input  wire        clk,
    input  wire        rst_n,


    input  wire [87:0] ent_name,
    input  wire [7:0]  ent_attr,
    input  wire [31:0] ent_first_clus,
    input  wire [31:0] ent_size,
    input  wire [15:0] ent_index,
    input  wire        ent_valid,
    output wire        ent_ready,


    input  wire        idx_clear,
    input  wire        idx_commit,
    output reg         idx_done,
    output reg  [3:0]  file_cnt,
    output reg  [3:0]  file_valid,
    output reg         insufficient,
    output reg  [7:0]  err_code,
    output reg  [7:0]  err_detail,


    input wire [15:0] cursor_key,
    output wire [15:0] sel_key,

    input  wire [1:0]  sel_slot,
    output wire [31:0] sel_first_clus,
    output wire [31:0] sel_size,
    output wire        sel_valid,


    output wire [31:0] sel_wav_first_clus,
    output wire [31:0] sel_wav_size,
    output wire        sel_wav_valid,


    output reg  [15:0] bmp_seen,
    output reg  [15:0] wav_seen
);


    // synthesis translate_off
    initial if(CANDIDATE_SLOTS<1 || CANDIDATE_SLOTS>4)
        $fatal(1,"invalid candidate capacity");
    // synthesis translate_on
    localparam integer NSLOT = 4;
    localparam integer NWAV  = 8;

    reg collecting;


    wire [7:0] nb0 = ent_name[87:80];
    wire [7:0] nb1 = ent_name[79:72];
    wire [7:0] nd0 = ent_name[71:64];
    wire [7:0] nd1 = ent_name[63:56];
    wire [7:0] nd2 = ent_name[55:48];
    wire [7:0] nd3 = ent_name[47:40];
    wire [7:0] nsp0= ent_name[39:32];
    wire [7:0] nsp1= ent_name[31:24];
    wire [7:0] ne0 = ent_name[23:16];
    wire [7:0] ne1 = ent_name[15:8];
    wire [7:0] ne2 = ent_name[7:0];

    wire d0_ok = (nd0 >= 8'h30) && (nd0 <= 8'h39);
    wire d1_ok = (nd1 >= 8'h30) && (nd1 <= 8'h39);
    wire d2_ok = (nd2 >= 8'h30) && (nd2 <= 8'h39);
    wire d3_ok = (nd3 >= 8'h30) && (nd3 <= 8'h39);

    wire name_ok = (nb0 == 8'h53) && (nb1 == 8'h56) &&
                   d0_ok && d1_ok && d2_ok && d3_ok &&
                   (nsp0 == 8'h20) && (nsp1 == 8'h20);
    wire ext_bmp = (ne0 == 8'h42) && (ne1 == 8'h4D) && (ne2 == 8'h50);
    wire ext_wav = (ne0 == 8'h57) && (ne1 == 8'h41) && (ne2 == 8'h56);


    wire [3:0]  nk0 = nd0 - 8'h30;
    wire [3:0]  nk1 = nd1 - 8'h30;
    wire [3:0]  nk2 = nd2 - 8'h30;
    wire [3:0]  nk3 = nd3 - 8'h30;
    wire [15:0] ent_key = { nk0, nk1, nk2, nk3 };
    wire num_ok = (ent_key != 16'd0);

    wire is_bmp_c = collecting && !idx_clear && ent_valid && name_ok && num_ok && ext_bmp && (!CURSOR_MODE || ent_key>cursor_key);
    wire is_wav_c = collecting && !idx_clear && ent_valid && name_ok && num_ok && ext_wav && (!CURSOR_MODE || ent_key>cursor_key);


    reg        is_bmp_d, is_wav_d;
    reg [15:0] key_d;
    reg [31:0] clus_d, size_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            is_bmp_d <= 1'b0; is_wav_d <= 1'b0; key_d <= 16'd0;
            clus_d <= 32'd0; size_d <= 32'd0;
        end else begin
            is_bmp_d <= is_bmp_c;
            is_wav_d <= is_wav_c;
            key_d    <= ent_key;
            clus_d   <= ent_first_clus;
            size_d   <= ent_size;
        end
    end

    wire is_bmp = is_bmp_d;
    wire is_wav = is_wav_d;


    reg [2:0] cmit_pipe;
    reg       cmit_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin cmit_pipe <= 3'd0; cmit_d <= 1'b0; end
        else begin
            cmit_pipe <= {cmit_pipe[1:0], idx_commit};
            cmit_d    <= cmit_pipe[2];
        end
    end

    assign ent_ready = 1'b1;


    reg [15:0] s_key [0:NSLOT-1];
    reg [31:0] s_clus[0:NSLOT-1];
    reg [31:0] s_size[0:NSLOT-1];
    reg        s_val [0:NSLOT-1];

    reg [15:0] w_key [0:NWAV-1];
    reg [31:0] w_clus[0:NWAV-1];
    reg [31:0] w_size[0:NWAV-1];
    reg        w_val [0:NWAV-1];


    reg [31:0] m_clus[0:NSLOT-1];
    reg [31:0] m_size[0:NSLOT-1];
    reg        m_val [0:NSLOT-1];

    integer i, j;
    integer ins_pos;
    reg     is_dup;
    reg     ins_keep;


    always @(*) begin
        ins_pos = 0;
        for (i = 0; i < CANDIDATE_SLOTS; i = i + 1)
            if (s_val[i] && (s_key[i] < key_d)) ins_pos = i + 1;
        is_dup = 1'b0;
        for (i = 0; i < CANDIDATE_SLOTS; i = i + 1)
            if (s_val[i] && (s_key[i] == key_d)) is_dup = 1'b1;

        ins_keep = (ins_pos < CANDIDATE_SLOTS) && !is_dup;
    end


    reg [15:0] bcnt_bmp, bcnt_wav;
    integer    k;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NSLOT; i = i + 1) begin
                s_key[i]  <= 16'd0;
                s_clus[i] <= 32'd0;
                s_size[i] <= 32'd0;
                s_val[i]  <= 1'b0;
                m_clus[i] <= 32'd0;
                m_size[i] <= 32'd0;
                m_val[i]  <= 1'b0;
            end
            for (i = 0; i < NWAV; i = i + 1) begin
                w_key[i]  <= 16'd0;
                w_clus[i] <= 32'd0;
                w_size[i] <= 32'd0;
                w_val[i]  <= 1'b0;
            end
            idx_done     <= 1'b0;
            file_cnt     <= 4'd0;
            file_valid   <= 4'd0;
            insufficient <= 1'b0;
            err_code     <= `ERR_NONE;
            err_detail   <= `DET_NONE;
            bcnt_bmp     <= 16'd0;
            bcnt_wav     <= 16'd0;
            bmp_seen     <= 16'd0;
            wav_seen     <= 16'd0;
            collecting   <= 1'b1;
        end else begin
            idx_done <= 1'b0;


            if (idx_clear) begin
                collecting<=1'b1;
                for (i = 0; i < NSLOT; i = i + 1) begin
                    s_key[i]  <= 16'd0;
                    s_clus[i] <= 32'd0;
                    s_size[i] <= 32'd0;
                    s_val[i]  <= 1'b0;
                    m_clus[i] <= 32'd0;
                    m_size[i] <= 32'd0;
                    m_val[i]  <= 1'b0;
                end
                for (i = 0; i < NWAV; i = i + 1) begin
                    w_key[i]  <= 16'd0;
                    w_clus[i] <= 32'd0;
                    w_size[i] <= 32'd0;
                    w_val[i]  <= 1'b0;
                end
                bcnt_bmp     <= 16'd0;
                bcnt_wav     <= 16'd0;
                bmp_seen     <= 16'd0;
                wav_seen     <= 16'd0;
                file_cnt     <= 4'd0;
                file_valid   <= 4'd0;
                insufficient <= 1'b0;
                err_code     <= `ERR_NONE;
                err_detail   <= `DET_NONE;
            end


            if (is_bmp && collecting && !idx_clear) begin
                bcnt_bmp <= bcnt_bmp + 16'd1;
                bmp_seen <= bcnt_bmp + 16'd1;
                if (ins_keep) begin
                    for (j = CANDIDATE_SLOTS - 1; j > 0; j = j - 1) begin
                        if (j > ins_pos) begin
                            s_key[j]  <= s_key[j-1];
                            s_clus[j] <= s_clus[j-1];
                            s_size[j] <= s_size[j-1];
                            s_val[j]  <= s_val[j-1];
                        end
                    end
                    s_key [ins_pos] <= key_d;
                    s_clus[ins_pos] <= clus_d;
                    s_size[ins_pos] <= size_d;
                    s_val [ins_pos] <= 1'b1;
                end
            end else if (is_wav && collecting && !idx_clear) begin
                bcnt_wav <= bcnt_wav + 16'd1;
                wav_seen <= bcnt_wav + 16'd1;

                begin : wav_ins
                    integer wi;
                    integer wpos;
                    reg     wdup;
                    reg     wkeep;
                    wpos = 0;
                    for (wi = 0; wi < NWAV; wi = wi + 1)
                        if (w_val[wi] && (w_key[wi] < key_d)) wpos = wi + 1;
                    wdup = 1'b0;
                    for (wi = 0; wi < NWAV; wi = wi + 1)
                        if (w_val[wi] && (w_key[wi] == key_d)) wdup = 1'b1;
                    wkeep = (wpos < NWAV) && !wdup;
                    if (wkeep) begin
                        for (wi = NWAV - 1; wi > 0; wi = wi - 1) begin
                            if (wi > wpos) begin
                                w_key[wi]  <= w_key[wi-1];
                                w_clus[wi] <= w_clus[wi-1];
                                w_size[wi] <= w_size[wi-1];
                                w_val[wi]  <= w_val[wi-1];
                            end
                        end
                        w_key [wpos] <= key_d;
                        w_clus[wpos] <= clus_d;
                        w_size[wpos] <= size_d;
                        w_val [wpos] <= 1'b1;
                    end
                end
            end


            if (cmit_d) begin
                collecting<=1'b0;
                file_valid <= {s_val[3], s_val[2], s_val[1], s_val[0]};
                file_cnt   <= {2'b00, s_val[3]} + {2'b00, s_val[2]} +
                              {2'b00, s_val[1]} + {2'b00, s_val[0]};
                if (!(s_val[0] && s_val[1] && s_val[2] && s_val[3])) begin
                    insufficient <= 1'b1;
                    err_code     <= `ERR_MEDIA_INVALID;
                    err_detail   <= `DET_BMP_COUNT;
                end else begin
                    insufficient <= 1'b0;
                    err_code     <= `ERR_NONE;
                    err_detail   <= `DET_NONE;
                end


                for (i = 0; i < NSLOT; i = i + 1) begin
                    m_clus[i] <= 32'd0;
                    m_size[i] <= 32'd0;
                    m_val[i]  <= 1'b0;
                    if (s_val[i]) begin
                        for (k = 0; k < NWAV; k = k + 1) begin
                            if (w_val[k] && (w_key[k] == s_key[i])) begin
                                m_clus[i] <= w_clus[k];
                                m_size[i] <= w_size[k];
                                m_val[i]  <= 1'b1;
                            end
                        end
                    end
                end
                idx_done <= 1'b1;
            end
        end
    end


    assign sel_key = s_key[sel_slot];
    assign sel_first_clus     = s_clus[sel_slot];
    assign sel_size           = s_size[sel_slot];
    assign sel_valid          = s_val[sel_slot];
    assign sel_wav_first_clus = m_clus[sel_slot];
    assign sel_wav_size       = m_size[sel_slot];
    assign sel_wav_valid      = m_val[sel_slot];

endmodule
