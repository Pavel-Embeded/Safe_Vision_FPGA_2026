`include "pixel_format_defs.vh"
// B bmp_unpack emits file-order pixels. Positive-height BMP rows arrive from
// bottom to top; B's sequential frame_writer alone cannot infer that order.
// Keep its packing/CRC/handshake, and remap accepted write rows into raster
// addresses. Header orientation is captured on the FIRST accepted pixel,
// since start may precede bmp_parser's header result. All ports use mem_clk.
// 12.5M clocks = 100ms at 125MHz; choose an explicit bound for other rates.
module bmp_frame_write_bridge #(
    parameter [31:0] GAP_TIMEOUT=32'd12_500_000,
    parameter integer EXACT_SAMPLE_COMPARE=0
)(
    input wire clk,rst_n,start,top_down,input wire [1:0] slot_sel,
    input wire [31:0] slot_base,input wire [15:0] din,input wire din_valid,
    output wire din_ready,wr_req,start_ready,output reg [31:0] wr_addr,output wire [31:0] wr_data,
    output wire [15:0] wr_len,input wire wr_ready,
    output wire wr_done,output wire [3:0] slot_valid,output wire crc_ok,
    output wire [15:0] crc_value,output wire [18:0] px_cnt,
    output wire wr_error,output wire [7:0] err_code,err_detail
);
    reg [31:0] base;
    reg [9:0] column,row;
    reg orientation,have_orientation,pair_phase,running;
    wire accept_start=start && start_ready;
    assign start_ready=!running;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)running<=0;
        else if(accept_start)running<=1;
        else if(wr_done || wr_error)running<=0;
    end
    wire [31:0] address_next;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin base<=0;column<=0;row<=0;orientation<=1;have_orientation<=0;pair_phase<=0;wr_addr<=0;end
        else if(accept_start)begin
            base<=slot_base;column<=0;row<=0;have_orientation<=0;pair_phase<=0;
        end else begin
            if(din_valid && din_ready && !have_orientation)begin
                orientation<=top_down;have_orientation<=1;
                row<=top_down ? 10'd0 : (`SV_FRAME_HEIGHT-1);
            end
            if(din_valid && din_ready)begin
                pair_phase<=~pair_phase;
                // Register before native wr_req rises for the completed pair.
                // The arbiter now sees a flop output, not row-multiply+base+mux.
                if(pair_phase)wr_addr<=address_next;
            end
            if(wr_req && wr_ready)begin
                if(column==`SV_FRAME_WIDTH-2)begin
                    column<=0;row<=orientation ? row+1'b1 : row-1'b1;
                end
                else column<=column+2'd2;
            end
        end
    end
    frame_address_gen address(.slot_base(base),.x(column),.y(row),
      .byte_addr(address_next),.word_addr(),.word_phase());
    frame_writer #(.GAP_TIMEOUT(GAP_TIMEOUT),.EXACT_SAMPLE_COMPARE(EXACT_SAMPLE_COMPARE)) writer(
      .clk(clk),.rst_n(rst_n),.start(accept_start),.slot_sel(slot_sel),.slot_base(slot_base),
      .din(din),.din_valid(din_valid),.din_ready(din_ready),.wr_req(wr_req),
      .wr_addr(),.wr_data(wr_data),.wr_len(wr_len),.wr_ready(wr_ready),
      .wr_done(wr_done),.slot_valid(slot_valid),.crc_ok(crc_ok),.crc_value(crc_value),
      .px_cnt(px_cnt),.wr_error(wr_error),.err_code(err_code),.err_detail(err_detail));
endmodule
