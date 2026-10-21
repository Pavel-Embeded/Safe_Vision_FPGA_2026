module v3_progress_original161(input wire sys_clk,sys_media_rst_n,input wire[47:0] mem_status_sys,input wire mem_status_valid,
input wire[203:0] ref_status_sys,input wire ref_status_valid,output wire mem_progress,media_progress);
 reg[31:0] observed_transactions,observed_bytes;reg[3:0] observed_state;
 assign mem_progress=mem_status_valid && observed_transactions!=mem_status_sys[47:16];
 assign media_progress=ref_status_valid && (observed_bytes!=ref_status_sys[79:48] || observed_state!=ref_status_sys[15:12]);
 always @(posedge sys_clk or negedge sys_media_rst_n)if(!sys_media_rst_n)begin observed_transactions<=0;observed_bytes<=0;observed_state<=0;end
 else begin
 if(mem_status_valid)observed_transactions<=mem_status_sys[47:16];
 if(ref_status_valid)begin observed_bytes<=ref_status_sys[79:48];observed_state<=ref_status_sys[15:12];end
 end
endmodule

module v3_progress_reduced161(input wire sys_clk,sys_media_rst_n,input wire[47:0] mem_status_sys,input wire mem_status_valid,
input wire[203:0] ref_status_sys,input wire ref_status_valid,output wire mem_progress,media_progress);
 reg[31:0] observed_transactions,observed_bytes;reg[3:0] observed_state;
 assign mem_progress=observed_transactions!=mem_status_sys[47:16];
 assign media_progress=(observed_bytes!=ref_status_sys[79:48] || observed_state!=ref_status_sys[15:12]);
 always @(posedge sys_clk or negedge sys_media_rst_n)if(!sys_media_rst_n)begin observed_transactions<=0;observed_bytes<=0;observed_state<=0;end
 else begin
 observed_transactions<=mem_status_sys[47:16];
 observed_bytes<=ref_status_sys[79:48];observed_state<=ref_status_sys[15:12];
 end
endmodule
