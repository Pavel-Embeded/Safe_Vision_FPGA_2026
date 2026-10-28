`include "safevision_defs.vh"
// BGR24 byte stream -> canonical640x480 RGB565, aspect fit, black letterbox.
// FLEX_PIXELS supports BGR24/BGRX32 source1..16384 on each axis; either orientation. No frame RAM:
// a selected row is horizontally resampled, then replayed for upscaling.
// Rational DDA gives exact floor(x*source/dest) without a divider/DSP.
// Bottom-up Y uses ceil((j+1)*H/dh)-1 so its canonical pixels are identical
// to top-down, including odd padding and noninteger downscaling ratios.
// Backpressure is propagated; output remains stable until accepted.
// Relative skips and pixel countdowns remove redundant full byte/target counters.
// Reuse row DDA/skip/column registers as geometry scratch before the row epoch.
module v3_bmp_normalizer #(parameter integer FLEX_PIXELS=0)(
 input wire clk,rst_n,input wire[7:0] din,input wire din_valid,
 output wire din_ready,input wire din_sof,din_eof,
 input wire[15:0] width,height,input wire top_down,
 output reg[15:0] pixel,output reg pixel_valid,input wire pixel_ready,
 output wire[9:0] x,y,output wire img_sof,img_eof,
 output reg done,error,output reg[7:0] err_code,err_detail,output wire[3:0] dbg_state,input wire[7:0] bpp);
 localparam IDLE=0,GEOM=1,SETUP=2,YADV=3,READ=4,STORE=5,XADV=6,ROWEND=7,
  EWAIT=8,EPUSH=9,EHOLD=10,DRAIN=11,FINISH=12,FAILED=13,GEOM_DECIDE=14;
 reg geometry_ge_q;
 localparam SB=FLEX_PIXELS?15:11,XB=FLEX_PIXELS?15:12;
 // Complete aspect-fit domain1..16384: ceil(W/dw)<=68 and
 // ceil(H/dh)<=51, including the clamped one-pixel minor dimension.
 // These are DDA advances, not source coordinates. GEOM's full-width
 // divisor temporarily occupies src_row and is cleared before source rows.
 localparam SX=FLEX_PIXELS?7:SB,SY=FLEX_PIXELS?6:SB;
 localparam DH=FLEX_PIXELS?9:10,PX=FLEX_PIXELS?9:10,PY=FLEX_PIXELS?8:10;
 reg[3:0] state;reg[SB-1:0] w,h;reg orientation,wide;
 reg[9:0] dw;reg[DH-1:0] dh;reg[PX-1:0] pad_x;reg[PY-1:0] pad_before;
 reg[SB-1:0] src_row,cols_left;reg[SX-1:0] skip_x;reg[SY-1:0] skip_y,y_steps;
 reg[XB-1:0] x_error;reg[SB-1:0] y_error;reg[9:0] store_x,out_x;reg[DH-1:0]out_row;
 reg[7:0] blue,green;reg[1:0] phase,padding_left;reg[15:0] captured;
 reg after_row,eof_seen,have_row,initial_y,line_full;
 // FLEX selects N=min(480*W,640*H). Accepted W<=16384 gives
 // N<=7,864,320<2^23; nonnegative subtractions preserve this bound.
 // GEOM reads omit seven unused high tuple bits. Row registers and both
 // original25-bit products retain their full widths.
 localparam GB=FLEX_PIXELS?SB+8:SB+XB;
 wire[GB-1:0] geometry_scratch={y_error,x_error};
 wire[SB-1:0] geometry_divisor=FLEX_PIXELS?src_row:skip_x;
 // Canonical line uses two native RAM9K tiles; no distributed tail.
 // Pixel precision and the existing synchronous read latency are unchanged.
 (* ram_style="bram" *) reg[15:0] row_pixels[0:639];
 // The store cursor is dead between selected source-row construction
 // epochs. Reuse it as the synchronous read cursor while emitting pixels;
 // x_error likewise holds the precomputed right edge during emission.
 // Source DDA initialization restores both before the next input row.
 wire[9:0] row_index=store_x;
 reg[15:0] read_pixel;
 always @(posedge clk)begin
  read_pixel<=row_pixels[row_index];
  if(state==STORE)row_pixels[store_x]<=captured;
 end
 wire row_black=out_row<pad_before||out_row>=pad_before+dh;
 wire col_black=out_x<pad_x||out_x>=x_error[9:0];
 wire bytes4=FLEX_PIXELS&&bpp==32;
 wire last_row_byte=bytes4?(phase==3&&cols_left==0):((phase==2&&cols_left==1&&w[1:0]==0)||(phase==3&&padding_left==1));
 assign din_ready=state==READ||state==DRAIN;
 assign x=out_x;assign y=orientation?out_row:10'd479-out_row;
 assign img_sof=pixel_valid&&out_x==0&&out_row==0;
 assign img_eof=pixel_valid&&out_x==639&&out_row==479;
 assign dbg_state=state;
 wire[15:0] abs_height=top_down?(~height+16'd1):height;
 wire[SB+9:0] width480=width[SB-1:0]*10'd480,height640=abs_height[SB-1:0]*10'd640;
 // All accepted dimensions are positive. Cancel the common factor160:
 // 480*W >=640*H iff3*W >=4*H. SB+2 bits cover both products exactly,
 // including FLEX H=16384 ->65536. Keep full numerators for the DDA.
 wire[SB+1:0] shape_width3={1'b0,width[SB-1:0],1'b0}+{2'b0,width[SB-1:0]};
 wire shape_wide=shape_width3>={abs_height[SB-1:0],2'b0};
 // FLEX captures dimensions on SOF, then separates the decision and
 // numerator/divisor load. Reuse initial_y before the actual row epoch.
 wire[SB+1:0] saved_width3={1'b0,w,1'b0}+{2'b0,w};
 wire saved_shape_wide=saved_width3>={h,2'b0};
 wire[SB+9:0] saved_width480=w*10'd480,saved_height640=h*10'd640;
 task begin_input_row;begin cols_left<=w;phase<=0;padding_left<=w[1:0];skip_x<=0;x_error<=0;store_x<=0;line_full<=0;end endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;orientation<=0;out_x<=0;out_row<=0;pixel<=0;pixel_valid<=0;done<=0;error<=0;err_code<=0;err_detail<=0;
   // FLEX private working state is fully overwritten by IDLE/GEOM/SETUP
   // before any output is eligible. Public reset values stay exact.
   if(!FLEX_PIXELS)begin
    w<=0;h<=0;wide<=0;dw<=0;dh<=0;pad_x<=0;pad_before<=0;src_row<=0;cols_left<=0;skip_x<=0;skip_y<=0;y_steps<=0;padding_left<=0;line_full<=0;
    x_error<=0;y_error<=0;store_x<=0;blue<=0;green<=0;phase<=0;captured<=0;after_row<=0;eof_seen<=0;have_row<=0;initial_y<=0;
   end
  end else begin
   done<=0;
   case(state)
    IDLE:if(din_valid&&din_sof)begin
     error<=0;err_code<=0;err_detail<=0;pixel_valid<=0;
     if(width==0||width>(FLEX_PIXELS?16384:1920)||abs_height==0||abs_height>(FLEX_PIXELS?16384:1080))begin
      error<=1;err_code<=`ERR_MEDIA_INVALID;err_detail<=`DET_BMP_SIZE;done<=1;state<=FAILED;
     end else begin
      w<=width[SB-1:0];h<=abs_height[SB-1:0];cols_left<=width[SB-1:0];padding_left<=width[1:0];orientation<=top_down;
      // FLEX consumes these fields only after GEOM overwrites them.
      if(!FLEX_PIXELS)wide<=shape_wide;
      if(!FLEX_PIXELS){y_error,x_error}<=shape_wide?height640:width480;
      skip_x<=FLEX_PIXELS?0:(shape_wide?width[SB-1:0]:abs_height[SB-1:0]);store_x<=0;
      if(!FLEX_PIXELS)src_row<=0;initial_y<=FLEX_PIXELS;skip_y<=0;y_steps<=0;line_full<=0;
      store_x<=0;out_x<=0;out_row<=0;phase<=0;after_row<=0;eof_seen<=0;have_row<=0;state<=GEOM;
     end
    end
    // Geometry is private until SETUP. Split wide compare from dimension
    // selection in FLEX mode; at most642 extra REF edges per image, with
    // identical integer division, aspect fit and output pixel order.
    GEOM:if(FLEX_PIXELS)begin
      if(initial_y)wide<=saved_shape_wide;else geometry_ge_q<=geometry_scratch>=geometry_divisor;
      state<=GEOM_DECIDE;end
     else if(geometry_scratch>=geometry_divisor)begin {y_error,x_error}<=geometry_scratch-geometry_divisor;store_x<=store_x+1'b1;end
     else begin dw<=wide?10'd640:store_x==0?10'd1:store_x;dh<=wide?(store_x==0?10'd1:store_x):10'd480;state<=SETUP;end
    GEOM_DECIDE:if(initial_y)begin
      {y_error,x_error}<=wide?saved_height640:saved_width480;src_row<=wide?w:h;
      initial_y<=0;state<=GEOM;
     end else if(geometry_ge_q)begin {y_error,x_error}<=geometry_scratch-geometry_divisor;store_x<=store_x+1'b1;state<=GEOM;end
     else begin dw<=wide?10'd640:store_x==0?10'd1:store_x;dh<=wide?(store_x==0?10'd1:store_x):10'd480;state<=SETUP;end
    SETUP:begin x_error<=((10'd640-dw)>>1)+dw;skip_x<=0;store_x<=0;
     if(FLEX_PIXELS)src_row<=0;
     pad_x<=(10'd640-dw)>>1;
     pad_before<=orientation?((10'd480-dh)>>1):(10'd480-dh-((10'd480-dh)>>1));
     y_steps<=0;y_error<=orientation?11'd0:h-1'b1;initial_y<=1;state<=YADV;
    end
    YADV:if(y_error>=dh)begin y_error<=y_error-dh;y_steps<=y_steps+1'b1;end
     else if(initial_y)begin skip_y<=y_steps;initial_y<=0;if(pad_before==0)x_error<=0;state<=pad_before!=0?EWAIT:READ;end
     else if(y_steps==0)state<=EWAIT;
     else begin skip_y<=y_steps-1'b1;src_row<=src_row+1'b1;begin_input_row();state<=READ;end
    READ:if(din_valid)begin
     if(last_row_byte)state<=ROWEND;
     case(phase)
      0:begin blue<=din;phase<=1;end
      1:begin green<=din;phase<=2;end
      2:begin
       phase<=bytes4||(cols_left==1&&w[1:0]!=0)?2'd3:2'd0;cols_left<=cols_left-1'b1;
       if(skip_y==0&&!line_full)begin
        if(skip_x>1)skip_x<=skip_x-1'b1;
        else begin captured<={din[7:3],green[7:2],blue[7:3]};after_row<=last_row_byte;state<=STORE;end
       end
      end
      3:if(bytes4)phase<=0;else padding_left<=padding_left-1'b1;
     endcase
     if(din_eof)begin
      eof_seen<=1;
      if(!last_row_byte||src_row!=h-1'b1)begin error<=1;err_code<=`ERR_MEDIA_INVALID;err_detail<=`DET_BMP_TRUNC;done<=1;state<=FAILED;end
     end
    end
    STORE:if(store_x==dw-1'b1)begin line_full<=1;state<=after_row?ROWEND:READ;end
     else begin store_x<=store_x+1'b1;x_error<=x_error+w;skip_x<=0;state<=XADV;end
    XADV:if(x_error>=dw)begin x_error<=x_error-dw;skip_x<=skip_x+1'b1;end
     else if(skip_x==0)state<=STORE;else state<=after_row?ROWEND:READ;
    ROWEND:if(skip_y==0)begin have_row<=1;out_x<=0;store_x<=0;x_error<=pad_x+dw;state<=EWAIT;end
     else begin skip_y<=skip_y-1'b1;src_row<=src_row+1'b1;begin_input_row();state<=READ;end
    EWAIT:state<=EPUSH;
    EPUSH:begin pixel<=row_black||col_black?16'd0:read_pixel;pixel_valid<=1;state<=EHOLD;end
    EHOLD:if(pixel_ready)begin
     pixel_valid<=0;if(!col_black)store_x<=store_x+1'b1;
     if(out_x!=639)begin out_x<=out_x+1'b1;state<=EWAIT;end
     else if(out_row==479)begin
      state<=eof_seen?FINISH:DRAIN;
      // Downscaling can finish the visible frame before the source's last
      // rows. Keep checking the unselected tail instead of accepting an
      // arbitrary early EOF after the final sampled row.
      if(!eof_seen)begin src_row<=src_row+1'b1;begin_input_row();end
     end
     else begin
      out_x<=0;store_x<=0;out_row<=out_row+1'b1;
      if(out_row+1'b1<pad_before||out_row+1'b1>=pad_before+dh)state<=EWAIT;
      else if(!have_row)begin x_error<=0;state<=READ;end
      else begin y_error<=y_error+h;y_steps<=0;state<=YADV;end
     end
    end
    DRAIN:if(din_valid)begin
     case(phase)
      0:phase<=1;
      1:phase<=2;
      2:begin phase<=bytes4||(cols_left==1&&w[1:0]!=0)?2'd3:2'd0;cols_left<=cols_left-1'b1;end
      3:if(bytes4)phase<=0;else padding_left<=padding_left-1'b1;
     endcase
     if(last_row_byte && src_row!=h-1'b1)begin src_row<=src_row+1'b1;begin_input_row();end
     if(din_eof)begin
      eof_seen<=1;
      if(last_row_byte && src_row==h-1'b1)state<=FINISH;
      else begin error<=1;err_code<=`ERR_MEDIA_INVALID;err_detail<=`DET_BMP_TRUNC;done<=1;state<=FAILED;end
     end
    end
    FINISH:begin done<=1;state<=IDLE;end
    FAILED:begin pixel_valid<=0;state<=IDLE;end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
