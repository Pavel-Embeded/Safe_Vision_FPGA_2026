`timescale 1ns/1ps
module tb_v3_control_argument296;
 reg clk=0,rst=0;always #5 clk=~clk;reg[31:0]value=0,rng=32'h91f389ab;integer errors=0,comparisons=0,low,p,k;reg[22:0]high;
 reg signed[31:0]signed_value;reg br,by,bi,vo;reg[6:0]pct;reg signed[8:0]offset;
 v3_user_controls #(.CLK_HZ(10),.DEBOUNCE(2),.BOARD_CATALOG(1),.HANDBOOK_PROFILE(1)) dut(
 .clk(clk),.rst_n(rst),.config_rst_n(rst),.next_async(1'b1),.auto_async(1'b1),.emergency_async(1'b1),
 .command_valid(1'b0),.command_target(8'd65),.command_name(96'd0),.command_value(value),.command_query(1'b0),.catalog_id(7'd5),
 .cached(1'b0),.transition_busy(1'b0),.frame_commit(1'b0),.system_safe(1'b0));
 task check(input[31:0]input_value);begin
  @(negedge clk);value=input_value;signed_value=$signed(input_value);
  // Independent ORIGINAL32-bit acceptance predicates; no clipped9-bit
  // argument or implementation flags are used by this reference.
  br=signed_value>=-128&&signed_value<=127;by=input_value<=255;
  bi=input_value==0||input_value==1;vo=input_value<=100;
  pct=signed_value< -100?0:signed_value>100?100:(signed_value+100)/2;
  offset=2*input_value-100;
  @(posedge clk);#1;comparisons+=4;
  if({dut.value_bright_qualified,dut.value_byte_qualified,dut.value_bit_qualified,dut.value_volume_qualified}!=={br,by,bi,vo})begin
   errors++;if(errors<8)$display("[FAIL] full32-bit validity changed input%h",input_value);
  end
  if(br)begin comparisons++;if(dut.bright_percent_eff!==pct)begin errors++;$display("[FAIL] signed offset-to-percent changed");end end
  if(vo)begin comparisons++;if(dut.percent_offset_eff!==offset)begin errors++;$display("[FAIL] percent-to-offset changed");end end
 end endtask
 initial begin
  #31;rst=1;
  // All512 low-word encodings. Original validity depends on whether the
  // high23-bit prefix is all0,all1,or another value. Exercise both legal
  // prefixes and every one-hot/one-cold illegal prefix, plus random words.
  for(low=0;low<512;low++)for(p=0;p<48;p++)begin
   high=p==0?23'd0:p==1?23'h7fffff:p<25?23'(1<<(p-2)):23'h7fffff^23'(1<<(p-25));
   check({high,9'(low)});
  end
  for(k=0;k<100000;k++)begin rng=rng*1664525+1013904223;check(rng);end
  if(!errors)$display("[PASS] clipped argument validity vs original32-bit classes,all512 low words,48 prefix patterns,100000 random words and exact percent conversion");
  $display("[TB] tb_v3_control_argument296 done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
endmodule
