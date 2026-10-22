// Transparent four-stage font layer; coordinates refer to RAW input timing.
// Preserve the existing osd_overlay ports/behavior for earlier A stages.
module osd_text_layer #(parameter FONT_FILE="../../../assets/fonts/font8x16.mem")(
    input wire clk,rst_n,de,input wire [11:0] x,y,origin_x,origin_y,
    input wire enable,input wire [7:0] char_count,char_code,input wire [23:0] foreground,
    output wire [7:0] char_index,output wire [23:0] rgb,output wire valid
);
    wire [12:0] dx={1'b0,x}-{1'b0,origin_x},dy={1'b0,y}-{1'b0,origin_y};
    wire region=enable&&de&&x>=origin_x&&y>=origin_y&&dx<{2'b00,char_count,3'b000}&&dy<16;
    assign char_index=dx[10:3];
    reg region1,region2,region3,dot4;reg [7:0] code1;reg [3:0] row1;
    reg [2:0] col1,col2,col3;reg [11:0] addr2;reg [23:0] fg1,fg2,fg3,fg4;
    wire [7:0] row_bits;
    font8x16_rom #(.FONT_FILE(FONT_FILE)) font(.clk(clk),.addr(addr2),.row_bits(row_bits));
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            region1<=0;region2<=0;region3<=0;dot4<=0;code1<=0;row1<=0;
            col1<=0;col2<=0;col3<=0;addr2<=0;fg1<=0;fg2<=0;fg3<=0;fg4<=0;
        end else begin
            region1<=region;code1<=char_code;row1<=dy[3:0];col1<=dx[2:0];fg1<=foreground;
            region2<=region1;addr2<={code1,row1};col2<=col1;fg2<=fg1;
            region3<=region2;col3<=col2;fg3<=fg2;
            dot4<=region3&&row_bits[7-col3];fg4<=fg3;
        end
    end
    assign valid=rst_n&&dot4;assign rgb=fg4;
endmodule
