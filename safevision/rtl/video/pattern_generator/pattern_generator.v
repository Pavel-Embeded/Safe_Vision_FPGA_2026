
module pattern_generator #(
    parameter integer H_ACTIVE=640, V_ACTIVE=480,
    parameter integer RECT_X0=100, RECT_X1=400, RECT_Y0=200, RECT_Y1=300
)(input wire rst_n, input wire de, input wire [11:0] x, y,
  input wire [2:0] pattern_select, input wire arrow_right,
  output reg [23:0] rgb);

    localparam integer CX=H_ACTIVE/2, CY=V_ACTIVE/2;
    localparam integer U=(H_ACTIVE>=320 && V_ACTIVE>=240)?16:2;
    wire shaft=(x>=CX-4*U && x<CX+U && y>=CY-U && y<CY+U);
    wire head_right=(x>=CX && x<CX+U && y>=CY-4*U && y<CY+4*U) ||
                    (x>=CX+U && x<CX+2*U && y>=CY-3*U && y<CY+3*U) ||
                    (x>=CX+2*U && x<CX+3*U && y>=CY-2*U && y<CY+2*U) ||
                    (x>=CX+3*U && x<CX+4*U && y>=CY-U && y<CY+U);
    wire shaft_left=(x>=CX-U && x<CX+4*U && y>=CY-U && y<CY+U);
    wire head_left=(x>=CX-U && x<CX && y>=CY-4*U && y<CY+4*U) ||
                   (x>=CX-2*U && x<CX-U && y>=CY-3*U && y<CY+3*U) ||
                   (x>=CX-3*U && x<CX-2*U && y>=CY-2*U && y<CY+2*U) ||
                   (x>=CX-4*U && x<CX-3*U && y>=CY-U && y<CY+U);
    always @* begin
        rgb=24'h000000;
        if (rst_n && de && x<H_ACTIVE && y<V_ACTIVE) begin
            case (pattern_select)
                0: rgb=24'hff0000;
                1: if (x<H_ACTIVE/3) rgb=24'hff0000;
                   else if (x<(2*H_ACTIVE)/3) rgb=24'h00ff00;
                   else rgb=24'h0000ff;
                2: rgb=(x[5]^y[5])?24'hffffff:24'h000000;
                3: if (x>=RECT_X0 && x<RECT_X1 && y>=RECT_Y0 && y<RECT_Y1)
                       rgb=24'h00ff00;
                4: if (arrow_right ? (shaft || head_right) : (shaft_left || head_left))
                       rgb=24'hffff00;
                5: if (x==0 || x==H_ACTIVE-1 || y==0 || y==V_ACTIVE-1)
                       rgb=24'hffffff;
                default: rgb=24'h000000;
            endcase
        end
    end
endmodule
