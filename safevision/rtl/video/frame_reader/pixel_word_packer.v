

module pixel_word_packer(
    input wire clk,rst_n,input wire [15:0] pixel,input wire valid,output wire ready,
    output wire [31:0] word_data,output wire word_valid,input wire word_ready,
    output reg pending
);
    reg [15:0] low_pixel;
    assign ready=rst_n && (!pending || word_ready);
    assign word_data={pixel,low_pixel};
    assign word_valid=rst_n && pending && valid;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin low_pixel<=0;pending<=0;end
        else if(valid&&ready)begin
            if(!pending)begin low_pixel<=pixel;pending<=1;end
            else pending<=0;
        end
    end
endmodule
