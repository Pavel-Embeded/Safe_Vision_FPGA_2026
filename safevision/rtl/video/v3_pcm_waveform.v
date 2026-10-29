


module v3_pcm_waveform #(parameter WIDTH=640,HEIGHT=480)(
 input wire clk,rst_n,frame_start,pcm_valid,input wire[23:0] pcm_left,
 input wire[11:0] x,y,input wire de,
 output wire trace_pixel,grid_pixel,output reg ready);
 (* ram_style="bram" *) reg[15:0] samples[0:255];
 reg capture_bank,display_bank,pending;reg[6:0] wr_index;reg[7:0] previous;
 localparam[7:0] ORIGIN_X=WIDTH-272;localparam signed[12:0] CENTER=HEIGHT-96;
 reg[15:0] read_pair;wire[7:0] rd_index=x[7:0]-ORIGIN_X;
 wire[7:0] rd_address={display_bank,rd_index[7:1]};
 wire region=de&&x>=WIDTH-272&&x<WIDTH-16&&y>=HEIGHT-130&&y<HEIGHT-62;
 reg region1;reg[11:0] y1,x1;
 wire signed[7:0] a=$signed(read_pair[15:8])>>>2,b=$signed(read_pair[7:0])>>>2;
 wire signed[12:0] ya=CENTER-{{5{a[7]}},a};
 wire signed[12:0] yb=CENTER-{{5{b[7]}},b};
 assign trace_pixel=region1&&ready&&({1'b0,y1}>=(ya<yb?ya:yb))&&({1'b0,y1}<=(ya>yb?ya:yb));
 assign grid_pixel=region1&&(y1==HEIGHT-96||y1==HEIGHT-130||y1==HEIGHT-63||x1==WIDTH-272||x1==WIDTH-17);
 always @(posedge clk)read_pair<=samples[rd_address];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin capture_bank<=0;display_bank<=1;pending<=0;wr_index<=0;previous<=0;ready<=0;region1<=0;y1<=0;x1<=0;end
  else begin
   region1<=region;y1<=y;x1<=x;
   if(frame_start&&pending)begin display_bank<=capture_bank;capture_bank<=display_bank;pending<=0;wr_index<=0;ready<=1;end
   else if(pcm_valid&&!pending)begin
    samples[{capture_bank,wr_index}]<={wr_index==0?pcm_left[23:16]:previous,pcm_left[23:16]};
    previous<=pcm_left[23:16];
    if(wr_index==127)pending<=1;else wr_index<=wr_index+1'b1;
   end
  end
 end
endmodule
