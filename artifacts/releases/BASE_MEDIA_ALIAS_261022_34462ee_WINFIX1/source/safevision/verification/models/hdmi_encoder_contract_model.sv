// EXPLICIT PORT/STREAM CONTRACT MODEL ONLY. Not HDMI/TMDS/audio packet encoding.
// Select only in run_hdmi_output_contract_sim.ps1; never compile in TD hardware.
`ifdef SAFEVISION_HDMI_CONTRACT_MODEL
module hdmi_1_4b_transmitter_core_wrapper #(
 parameter DEVICE="EG",HTOTAL=800,HSA=96,HFP=16,HBP=48,HACTIVE=640,
 VTOTAL=525,VSA=2,VFP=10,VBP=33,VACTIVE=480,VIDEO_VIC=1,
 VIDEO_TPG="Disable",VIDEO_FORMAT="RGB",AUDIO_SAMPLE_RATE="48K",IIC_SCL_DIV=250
)(
 input wire I_pixel_clk,I_rst,I_edid_read_trig,
 output reg O_edid_read_valid,output reg [7:0] O_edid_read_data,
 input wire I_axis_s_user,I_axis_s_valid,I_axis_s_last,input wire [23:0] I_axis_s_data,
 output reg O_axis_s_ready,input wire I_audio_valid,
 input wire [23:0] I_audio_left_data,I_audio_right_data,
 input wire I_acr_valid,input wire [19:0] I_acr_cts,I_acr_n,
 output reg O_video_locked,output wire O_ddc_scl,inout wire IO_ddc_sda,
 output wire [9:0] O_ch0_tmds_data,O_ch1_tmds_data,O_ch2_tmds_data,O_clk_tmds_data
);
 assign O_ddc_scl=1;assign IO_ddc_sda=1'bz;
 assign O_ch0_tmds_data={2'b0,I_axis_s_data[7:0]};
 assign O_ch1_tmds_data={2'b0,I_axis_s_data[15:8]};
 assign O_ch2_tmds_data={2'b0,I_axis_s_data[23:16]};
 assign O_clk_tmds_data=10'b1111100000;
 integer col=0,row=0,gap=0,edid=-1,completed=0,accepted=0;
 reg frame_open=0,line_open=0;reg [23:0] expected;
 always @(posedge I_pixel_clk)begin
  if(I_rst)begin
   O_axis_s_ready<=1;O_video_locked<=0;O_edid_read_valid<=0;O_edid_read_data<=0;
   col=0;row=0;gap=0;edid=-1;completed=0;accepted=0;frame_open=0;line_open=0;
  end else begin
   O_edid_read_valid<=0;
   if(I_edid_read_trig)edid=0;
   if(edid>=0)begin
    O_edid_read_valid<=1;O_edid_read_data<=edid;
    if(edid==127)edid=-1;else edid=edid+1;
   end
   if(!O_axis_s_ready)begin
    if(gap==0)O_axis_s_ready<=1;else gap=gap-1;
   end
   if(line_open&&O_axis_s_ready&&!I_axis_s_valid)$fatal(1,"vendor contract: bubble within a line");
   if(I_axis_s_valid&&O_axis_s_ready)begin
    if(I_axis_s_user)begin
     if(frame_open)$fatal(1,"duplicate SOF");
     col=0;row=0;frame_open=1;
    end
    if(!frame_open)$fatal(1,"data before SOF");
    expected={col[7:0],row[7:0],8'(col+row)};
    if(I_axis_s_data!==expected)$fatal(1,"HDMI port RGB mismatch col=%0d row=%0d",col,row);
    if(I_axis_s_last!==(col==HACTIVE-1))$fatal(1,"HDMI EOL wrong");
    accepted=accepted+1;
    if(I_axis_s_last)begin
     col=0;row=row+1;line_open=0;O_axis_s_ready<=0;gap=HTOTAL-HACTIVE-1;
     if(row==VACTIVE)begin frame_open=0;completed=completed+1;O_video_locked<=1;end
    end else begin col=col+1;line_open=1;end
   end
  end
 end
endmodule
`endif
