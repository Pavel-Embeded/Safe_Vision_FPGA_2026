


`include "safevision_defs.vh"

module frame_swap_cdc (

    input  wire       clk_b,
    input  wire       rst_b_n,
    input  wire       swap_req_b,
    input  wire       mb_frame_index_b,
    input  wire [1:0] mb_slot_id_b,
    input  wire [7:0] mb_generation_b,
    input  wire       mb_crc_ok_b,
    output wire       frame_start_evt_b,
    output wire       swap_ack_evt_b,


    input  wire       clk_a,
    input  wire       rst_a_n,
    output wire       swap_req_evt_a,
    output wire       swap_req_lvl_a,
    output wire       mb_frame_index_a,
    output wire [1:0] mb_slot_id_a,
    output wire [7:0] mb_generation_a,
    output wire       mb_crc_ok_a,
    output wire       mb_valid_a,
    input  wire       frame_start_a,
    input  wire       swap_ack_a
);


    reg [2:0] req_sync;
    always @(posedge clk_a or negedge rst_a_n) begin
        if (!rst_a_n) req_sync <= 3'b000;
        else          req_sync <= {req_sync[1:0], swap_req_b};
    end
    assign swap_req_lvl_a = req_sync[1];
    assign swap_req_evt_a = req_sync[2] ^ req_sync[1];


    reg [1:0] mb_slot_id_a_r;
    reg [7:0] mb_generation_a_r;
    reg       mb_frame_index_a_r;
    reg       mb_crc_ok_a_r;
    reg       mb_valid_a_r;

    always @(posedge clk_a or negedge rst_a_n) begin
        if (!rst_a_n) begin
            mb_slot_id_a_r    <= 2'd0;
            mb_generation_a_r <= 8'd0;
            mb_frame_index_a_r<= 1'b0;
            mb_crc_ok_a_r     <= 1'b0;
            mb_valid_a_r      <= 1'b0;
        end else if (swap_req_evt_a) begin

            mb_slot_id_a_r     <= mb_slot_id_b;
            mb_generation_a_r  <= mb_generation_b;
            mb_frame_index_a_r <= mb_frame_index_b;
            mb_crc_ok_a_r      <= mb_crc_ok_b;
            mb_valid_a_r       <= 1'b1;
        end
    end

    assign mb_slot_id_a     = mb_slot_id_a_r;
    assign mb_generation_a  = mb_generation_a_r;
    assign mb_frame_index_a = mb_frame_index_a_r;
    assign mb_crc_ok_a      = mb_crc_ok_a_r;
    assign mb_valid_a       = mb_valid_a_r;


    reg fs_tgl_a;
    always @(posedge clk_a or negedge rst_a_n) begin
        if (!rst_a_n) fs_tgl_a <= 1'b0;
        else if (frame_start_a) fs_tgl_a <= ~fs_tgl_a;
    end

    reg [2:0] fs_sync;
    always @(posedge clk_b or negedge rst_b_n) begin
        if (!rst_b_n) fs_sync <= 3'b000;
        else          fs_sync <= {fs_sync[1:0], fs_tgl_a};
    end
    assign frame_start_evt_b = fs_sync[2] ^ fs_sync[1];


    reg [2:0] ack_sync;
    always @(posedge clk_b or negedge rst_b_n) begin
        if (!rst_b_n) ack_sync <= 3'b000;
        else          ack_sync <= {ack_sync[1:0], swap_ack_a};
    end
    assign swap_ack_evt_b = ack_sync[2] ^ ack_sync[1];

endmodule
