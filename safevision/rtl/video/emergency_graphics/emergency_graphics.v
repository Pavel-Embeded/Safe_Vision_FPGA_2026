// Four pixel-clock stages, aligned with the existing four-stage OSD layer.
// Hardware-only geometry plus the shared BRAM font; no external frame memory.
// Whole DE region remains Emergency even when arrows blink off.
module emergency_graphics #(
    parameter integer HD=0,FLASH_FRAMES=30,
    parameter FONT_FILE="../../../assets/fonts/font8x16.mem"
)(
    input wire clk,rst_n,de,frame_start,input wire [11:0] x,y,
    input wire active,input wire [1:0] direction,warning_level,
    output wire [23:0] rgb,output wire valid
);
    localparam integer WIDTH=HD?1280:640,HEIGHT=HD?720:480;
    localparam [11:0] CX=WIDTH/2,CY=HEIGHT/2,TX=WIDTH/2-16,TY=HEIGHT/4;
    wire [12:0] dy=(y>=CY)?{1'b0,y}-{1'b0,CY}:{1'b0,CY}-{1'b0,y};
    wire left_head=x>=CX-96&&x<=CX-32&&dy<=((x-(CX-96))>>1);
    wire right_head=x>=CX+32&&x<=CX+96&&dy<=(((CX+96)-x)>>1);
    wire left_shape=left_head||(x>=CX-32&&x<=CX+96&&dy<=12);
    wire right_shape=right_head||(x>=CX-96&&x<=CX+32&&dy<=12);
    wire both_shape=left_head||right_head||(x>=CX-32&&x<=CX+32&&dy<=12);
    wire arrow=(direction==0)?left_shape:(direction==1)?right_shape:both_shape;
    wire border=x<4||x>=WIDTH-4||y<4||y>=HEIGHT-4;
    reg [15:0] flash_count;reg flash_on;
    wire [15:0] period=(warning_level<2)?FLASH_FRAMES:
        (warning_level==2)?((FLASH_FRAMES/2)>0?FLASH_FRAMES/2:1):
        ((FLASH_FRAMES/4)>0?FLASH_FRAMES/4:1);
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin flash_count<=0;flash_on<=1;end
        else if(!active||warning_level==0)begin flash_count<=0;flash_on<=1;end
        else if(frame_start)begin
            if(flash_count>=period-1'b1)begin flash_count<=0;flash_on<=~flash_on;end
            else flash_count<=flash_count+1'b1;
        end
    end
    wire [23:0] color=(warning_level==0)?24'h00ff00:
        (warning_level==1)?24'hffff00:24'hff3030;
    wire [23:0] background=(warning_level<2)?24'h001008:24'h180000;
    wire [7:0] index;
    reg [7:0] code;
    always @*begin
        case(index)0:code=8'h45;1:code=8'h58;2:code=8'h49;3:code=8'h54;
            default:code=8'h20;endcase
    end
    wire [23:0] text_rgb;wire text_valid;
    osd_text_layer #(.FONT_FILE(FONT_FILE)) text(
        .clk(clk),.rst_n(rst_n),.de(de),.x(x),.y(y),.origin_x(TX),.origin_y(TY),
        .enable(active),.char_count(8'd4),.char_code(code),.foreground(color),
        .char_index(index),.rgb(text_rgb),.valid(text_valid));
    reg [23:0] c1,c2,c3,c4;reg [3:0] v;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin c1<=0;c2<=0;c3<=0;c4<=0;v<=0;end
        else begin
            c1<=(border||(arrow&&flash_on))?color:background;
            c2<=c1;c3<=c2;c4<=c3;v<={v[2:0],active&&de};
        end
    end
    assign valid=rst_n&&v[3];
    assign rgb=valid?(text_valid?text_rgb:c4):24'd0;
endmodule
