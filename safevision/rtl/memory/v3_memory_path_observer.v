


module v3_memory_path_observer #(
 parameter integer WORDS=320,
 parameter integer READ_DATA_LEADS_VALID=1
)(input wire clk,rst_n,
 input wire source_accept,input wire[31:0] source_byte_addr,source_data,
 input wire physical_write,input wire[20:0] physical_word_addr,
 input wire[3:0] physical_dm,input wire[31:0] physical_write_data,
 input wire verify_start,physical_read_valid,input wire[31:0] physical_read_data,
 input wire host_read_valid,input wire[31:0] host_read_data,
 output reg[31:0] source_or,write_or,raw_or,host_or,
 output reg[8:0] source_count,write_count,raw_count,host_count);
 reg[31:0] previous_raw;
 reg verify_started;
 wire[31:0] aligned_raw=READ_DATA_LEADS_VALID?previous_raw:physical_read_data;
 wire source_in_row=source_byte_addr<WORDS*4 && source_byte_addr[1:0]==0;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   source_or<=0;write_or<=0;raw_or<=0;host_or<=0;
   source_count<=0;write_count<=0;raw_count<=0;host_count<=0;
   previous_raw<=0;verify_started<=0;
  end else begin

   previous_raw<=physical_read_data;
   if(verify_start)verify_started<=1;
   if(source_accept && source_in_row && source_count<WORDS)begin
    source_or<=source_or|{31'd0,|source_data};source_count<=source_count+1'b1;
   end

   if(physical_write && physical_word_addr<WORDS && physical_dm==0 && write_count<WORDS)begin
    write_or<=write_or|{31'd0,|physical_write_data};write_count<=write_count+1'b1;
   end
   if(verify_started && physical_read_valid && raw_count<WORDS)begin
    raw_or<=raw_or|{31'd0,|aligned_raw};raw_count<=raw_count+1'b1;
   end
   if(verify_started && host_read_valid && host_count<WORDS)begin
    host_or<=host_or|{31'd0,|host_read_data};host_count<=host_count+1'b1;
   end
  end
 end
 // synthesis translate_off
 initial if(WORDS<1||WORDS>511)$fatal(1,"observer window outside9-bit count");
 // synthesis translate_on
endmodule
