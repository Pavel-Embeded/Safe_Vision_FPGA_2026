`timescale 1ns/1ps


module tb_v3_progress_wide_independent;
 localparam integer SW=16384,SH=51,DATA_BYTES=SW*SH*4,FILE_BYTES=54+DATA_BYTES;
 localparam integer RAW_PERIOD=16,GAP=4096,FRAME_DEADLINE=262144;
 reg refclk=0,memclk=0,rst_n=0,active=0,sending=0;
 always #10 refclk=~refclk;
 initial begin #7;forever #10 memclk=~memclk;end
 integer errors=0,comparisons=0;
 task ck(input bit ok,input string why);begin comparisons++;
  if(!ok)begin errors++;if(errors<20)$display("[FAIL] %s at %t",why,$time);end
 end endtask

 function automatic[7:0] file_byte(input integer index);
  integer offset,sx,sy;
  begin
   file_byte=0;
   if(index<54)case(index)
    0:file_byte=8'h42;1:file_byte=8'h4d;
    2,3,4,5:file_byte=FILE_BYTES>>(8*(index-2));
    10:file_byte=54;14:file_byte=40;
    18,19,20,21:file_byte=SW>>(8*(index-18));
    22,23,24,25:file_byte=SH>>(8*(index-22));
    26:file_byte=1;28:file_byte=32;
    34,35,36,37:file_byte=DATA_BYTES>>(8*(index-34));
    default:file_byte=0;
   endcase else begin
    offset=index-54;sx=(offset>>2)&16383;sy=offset>>16;
    case(offset&3)
     0:file_byte=(sx*7+sy*13+47)&255;
     1:file_byte=(sx*5+sy*7+31)&255;
     2:file_byte=(sx*3+sy*11+17)&255;
     3:file_byte=8'hc3;
    endcase
   end
  end
 endfunction


 function automatic[15:0] expected_pixel(input integer x,y);
  integer sx;reg[7:0]r,g,b;
  begin
   expected_pixel=0;
   if(y==239)begin
    sx=(x*SW)/640;
    r=(sx*3+50*11+17)&255;g=(sx*5+50*7+31)&255;b=(sx*7+50*13+47)&255;
    expected_pixel={r[7:3],g[7:2],b[7:3]};
   end
  end
 endfunction

 integer input_index=0,cooldown=0,ref_cycles=0;
 wire input_valid=sending&&input_index<FILE_BYTES&&cooldown==0;
 wire input_ready;wire[7:0] input_data=file_byte(input_index);
 wire input_eof=input_index==FILE_BYTES-1;
 reg[31:0] raw_count=0;
 always @(posedge refclk)begin
  if(!rst_n)begin input_index<=0;cooldown<=0;raw_count<=0;ref_cycles<=0;end
  else begin
   ref_cycles<=ref_cycles+1;
   if(input_valid&&input_ready)begin
    input_index<=input_index+1;raw_count<=raw_count+1'b1;cooldown<=RAW_PERIOD-1;
   end else if(cooldown!=0)cooldown<=cooldown-1;
  end
 end
 wire checked,header_error,td;wire[15:0] width,height;wire[7:0]bpp;
 wire[7:0] parsed_data;wire parsed_valid,parsed_ready,parsed_sof,parsed_eof;
 wire[31:0]offbits;integer checked_count=0;
 bmp_parser #(.VARIABLE_SIZE(1),.FLEX_PIXELS(1)) parser(
  .clk(refclk),.rst_n(rst_n),.data(input_data),.valid(input_valid),.ready(input_ready),.eof(input_eof),.file_size(32'(FILE_BYTES)),
  .check_done(checked),.check_error(header_error),.err_code(),.err_detail(),.width(width),.height(height),.top_down(td),.bpp(bpp),
  .compression(),.pixel_off(offbits),.file_size_o(),.dbg_state(),
  .out_data(parsed_data),.out_valid(parsed_valid),.out_ready(parsed_ready),.out_sof(parsed_sof),.out_eof(parsed_eof));
 wire[15:0] pixel;wire pixel_valid,pixel_ready,norm_done,norm_error;
 wire[9:0] pixel_x,pixel_y;wire image_sof,image_eof;
 v3_bmp_normalizer #(.FLEX_PIXELS(1)) normalizer(
  .clk(refclk),.rst_n(rst_n),.din(parsed_data),.din_valid(parsed_valid),.din_ready(parsed_ready),.din_sof(parsed_sof),.din_eof(parsed_eof),
  .width(width),.height(height),.top_down(td),.bpp(bpp),.pixel(pixel),.pixel_valid(pixel_valid),.pixel_ready(pixel_ready),
  .x(pixel_x),.y(pixel_y),.img_sof(image_sof),.img_eof(image_eof),.done(norm_done),.error(norm_error),.err_code(),.err_detail(),.dbg_state());
 integer pixel_count=0,last_pixel_cycle=0,max_pixel_gap=0,norm_done_count=0;
 reg[15:0]lo_pixel=0;reg have_lo=0;reg[31:0]packed_word=0;reg packed_valid=0;
 wire packed_ready;
 assign pixel_ready=!packed_valid||packed_ready;
 always @(posedge refclk)begin
  if(!rst_n)begin lo_pixel<=0;have_lo<=0;packed_word<=0;packed_valid<=0;pixel_count<=0;last_pixel_cycle<=0;max_pixel_gap<=0;checked_count<=0;norm_done_count<=0;end
  else begin
   if(checked)begin
    checked_count<=checked_count+1;
    ck(!header_error&&width==SW&&height==SH&&!td&&bpp==32&&offbits==54,"actual parser accepts the exact legal bottom-up BGRX header");
   end
   if(norm_done)norm_done_count<=norm_done_count+1;
   if(packed_valid&&packed_ready)packed_valid<=0;
   if(pixel_valid&&pixel_ready)begin
    ck(pixel_count<307200,"no extra normalized pixel");
    ck(pixel_x==pixel_count%640&&pixel_y==479-pixel_count/640,"independent full-frame raster order");
    ck(pixel===expected_pixel(pixel_count%640,479-pixel_count/640),"independent exact RGB565 pixel and letterbox");
    ck(image_sof==(pixel_count==0)&&image_eof==(pixel_count==307199),"exact normalized frame markers");
    if(pixel_count!=0&&ref_cycles-last_pixel_cycle>max_pixel_gap)max_pixel_gap<=ref_cycles-last_pixel_cycle;
    last_pixel_cycle<=ref_cycles;pixel_count<=pixel_count+1;
    if(!have_lo)begin lo_pixel<=pixel;have_lo<=1;end
    else begin packed_word<={pixel,lo_pixel};packed_valid<=1;have_lo<=0;end
   end
  end
 end


 reg[2:0] progress_sync=0;
 always @(posedge memclk or negedge rst_n)
  if(!rst_n)progress_sync<=0;else progress_sync<={progress_sync[1:0],raw_count[0]};
 wire source_tick=progress_sync[2]^progress_sync[1];

 wire req,ack;wire[31:0]addr,data;wire[15:0]len;wire ready,done,ok;
 wire[3:0]sink_state;wire[7:0]sink_error;
 wire begin_frame,source_td;wire[1:0]source_slot;wire verify_done,verify_pass,guard_fault;
 wire write_drained;
 bmp_frame_sink #(.FIFO_AW(8),.GAP_TIMEOUT(GAP),.WRITE_TO_N(FRAME_DEADLINE),.SWAP_TO_N(GAP),
  .REQUIRE_WRITE_DRAIN(1),.REQUIRE_READBACK(1),.RESIDENT_LOAD(1),.SOURCE_PROGRESS_AWARE(1)) sink(
  .clk(memclk),.rst_n(rst_n),.wr_clk(refclk),.px_word(packed_word),.px_word_valid(packed_valid),.px_word_ready(packed_ready),
  .frame_active(active),.top_down(td),.slot(2'd0),.mem_ready(ready),.frame_done(done),.last_frame_ok(ok),
  .wr_req(req),.wr_addr(addr),.wr_data(data),.wr_len(len),.wr_ready(ack),.swap_toggle(),.swap_slot(),.swap_generation(),.swap_crc_ok(),.swap_busy(1'b0),
  .state_o(sink_state),.err_code(sink_error),.err_detail(),.frame_cnt(),.px_written(),
  .write_drained(write_drained),.verify_done(verify_done),.verify_pass(verify_pass),.source_begin(begin_frame),.source_slot(source_slot),.source_top_down(source_td),.source_progress(source_tick));
 wire old_ready,old_done,old_ok,old_req;wire[3:0]old_state;wire[7:0]old_error;


 bmp_frame_sink #(.FIFO_AW(8),.GAP_TIMEOUT(GAP),.WRITE_TO_N(FRAME_DEADLINE),.SWAP_TO_N(GAP),
  .REQUIRE_WRITE_DRAIN(1),.REQUIRE_READBACK(0),.RESIDENT_LOAD(1),.SOURCE_PROGRESS_AWARE(0)) legacy(
  .clk(memclk),.rst_n(rst_n),.wr_clk(refclk),.px_word(packed_word),.px_word_valid(packed_valid&&packed_ready),.px_word_ready(),
  .frame_active(active),.top_down(td),.slot(2'd0),.mem_ready(old_ready),.frame_done(old_done),.last_frame_ok(old_ok),
  .wr_req(old_req),.wr_addr(),.wr_data(),.wr_len(),.wr_ready(1'b1),.swap_toggle(),.swap_slot(),.swap_generation(),.swap_crc_ok(),.swap_busy(1'b0),
  .state_o(old_state),.err_code(old_error),.err_detail(),.frame_cnt(),.px_written(),
  .write_drained(1'b1),.verify_done(1'b0),.verify_pass(1'b0),.source_begin(),.source_slot(),.source_top_down(),.source_progress(1'bx));

 reg[31:0] memory[0:153599];integer tail=0,write_count=0,mem_cycles=0;
 reg external_read_busy=0,busy_armed=0;integer busy_left=0;
 reg previous_read_busy=0;integer blocked_hint_count=0,saved_credit_count=0,stale_checks=0,credits=0,uncovered_bytes=0;
 reg legacy_error_seen=0,normalizer_error_seen=0;
 wire vreq,vbusy,vvalid,vack;wire[31:0]vaddr,vdata;wire[15:0]vlen;
 assign ack=!external_read_busy&&tail==0&&!vbusy;
 assign write_drained=!external_read_busy&&tail==0&&!vbusy;
 always @(negedge memclk)begin
  if(!rst_n)begin external_read_busy<=0;busy_armed<=0;busy_left<=0;end
  else if(!busy_armed&&pixel_count==153600&&input_index>65590&&source_tick&&sink_state==1&&sink.fifo_empty&&!sink.sk_valid&&!req&&tail==0)begin
   external_read_busy<=1;busy_armed<=1;busy_left<=6;
  end else if(external_read_busy)begin
   if(busy_left==0)external_read_busy<=0;else busy_left<=busy_left-1;
  end
 end
 integer xx,yy;reg[31:0]wanted_word;
 always @(posedge memclk)begin
  if(!rst_n)begin tail<=0;write_count<=0;mem_cycles<=0;previous_read_busy<=0;blocked_hint_count<=0;saved_credit_count<=0;stale_checks<=0;credits<=0;uncovered_bytes<=0;legacy_error_seen<=0;normalizer_error_seen<=0;end
  else begin
   mem_cycles<=mem_cycles+1;if(tail!=0)tail<=tail-1;
   if(req&&ack)begin
    xx=(write_count%320)*2;yy=479-write_count/320;
    wanted_word={expected_pixel(xx+1,yy),expected_pixel(xx,yy)};
    ck(write_count<153600&&len==1,"every write is one bounded canonical word");
    ck(addr===32'(yy*1280+xx*2),"all write addresses follow independent bottom-up raster mapping");
    ck(data===wanted_word,"all accepted write payloads match independent complete-frame pixels");
    if(addr<614400&&addr[1:0]==0)memory[addr>>2]<=data;
    write_count<=write_count+1;tail<=2;
   end
   if(old_error!=0)legacy_error_seen<=1;
   if(norm_error)normalizer_error_seen<=1;
   if(source_tick&&external_read_busy)blocked_hint_count<=blocked_hint_count+1;
   if(previous_read_busy&&!external_read_busy)begin
    ck(sink.source_wait_credit,"a raw byte coincident with healthy read activity remains available at first drain");
    if(sink.source_wait_credit)saved_credit_count<=saved_credit_count+1;
   end
   previous_read_busy<=external_read_busy;


   if(sink_state!=1||!sink.fa_sync[2])uncovered_bytes<=0;
   else if(sink.source_wait_credit)begin
    ck(uncovered_bytes>0,"wait credit has a preceding real source event");
    ck(!external_read_busy&&tail==0&&!req&&!sink.sk_valid&&sink.fifo_empty,"wait credit never covers queued pixel or adapter work");
    credits<=credits+1;uncovered_bytes<=source_tick?1:0;
   end else if(sink.br_px_cnt!=sink.px_d||(req&&ack))uncovered_bytes<=source_tick?1:0;
   else if(source_tick)uncovered_bytes<=uncovered_bytes+1;
   if(busy_armed&&!external_read_busy&&uncovered_bytes==0&&!source_tick&&sink_state==1&&!req&&!sink.sk_valid&&sink.fifo_empty)begin
    ck(!sink.source_wait_credit,"consumed source event cannot become a free-running heartbeat");stale_checks<=stale_checks+1;
   end
   if(sink_error!=0)begin
    ck(0,"healthy wide BMP unexpectedly trips the sink watchdog");
    $display("[FAIL] sink error=%h state=%0d input=%0d pixel=%0d writes=%0d",sink_error,sink_state,input_index,pixel_count,write_count);
    $display("PASS tb_v3_progress_wide_independent errors=%0d comparisons=%0d",errors,comparisons);$finish;
   end
  end
 end
 reg verify_started=0;wire verify_start=sink_state==4&&write_drained&&!verify_started;
 always @(posedge memclk)if(!rst_n)verify_started<=0;else if(verify_start)verify_started<=1;
 v3_row_integrity #(.TIMEOUT(GAP)) guard(
  .clk(memclk),.rst_n(rst_n),.frame_begin(begin_frame),.frame_slot(source_slot),.top_down(source_td),
  .accepted(req&&ack),.write_addr(addr),.write_data(data),.verify_start(verify_start),.verify_allow(write_drained),
  .verify_done(verify_done),.verify_pass(verify_pass),.fault(guard_fault),.approved(),
  .rd_req(vreq),.rd_addr(vaddr),.rd_len(vlen),.rd_ack(vack),.rd_busy(vbusy),.rd_valid(vvalid),.rd_data(vdata),
  .lookup_addr(32'd0),.lookup_crc(),.lookup_valid(),.bad_addr(),.bad_expected(),.bad_actual(),.source_words(),.checked_rows());
 reg read_busy=0,read_ack=0,read_valid=0;reg[31:0]read_data=0;integer read_index=0,read_remaining=0,read_count=0;
 assign vbusy=read_busy;assign vack=read_ack;assign vvalid=read_valid;assign vdata=read_data;
 always @(posedge memclk)begin
  if(!rst_n)begin read_busy<=0;read_ack<=0;read_valid<=0;read_data<=0;read_index<=0;read_remaining<=0;read_count<=0;end
  else begin
   read_ack<=0;read_valid<=0;
   if(vreq&&!read_busy)begin
    ck(vlen==64&&vaddr[1:0]==0&&vaddr<614400,"real row verifier issues bounded aligned reads");
    read_ack<=1;read_busy<=1;read_index<=vaddr>>2;read_remaining<=64;
   end else if(read_busy)begin
    read_valid<=1;read_data<=memory[read_index];read_index<=read_index+1;read_remaining<=read_remaining-1;read_count<=read_count+1;
    if(read_remaining==1)read_busy<=0;
   end
  end
 end
 initial begin
  repeat(20)@(negedge refclk);rst_n=1;
  wait(ready&&old_ready);@(negedge refclk);active=1;
  repeat(10)@(negedge refclk);sending=1;
  wait(done);@(negedge refclk);active=0;
  repeat(20)@(negedge memclk);
  ck(checked_count==1&&!header_error,"one valid complete BMP header");
  ck(input_index==FILE_BYTES&&raw_count==FILE_BYTES,"every header and raw pixel byte was actually consumed");
  ck(pixel_count==307200&&write_count==153600&&!have_lo,"all canonical pixels and paired writes complete exactly once");
  ck(max_pixel_gap>FRAME_DEADLINE&&max_pixel_gap>GAP,"legal discarded source rows create a genuinely long no-pixel interval");
  ck(norm_done_count==1&&!normalizer_error_seen,"actual normalizer completes without data or geometry errors");
  ck(ok&&verify_done&&verify_pass&&!guard_fault&&read_count==153600,"real full-frame row CRC readback and sink completion pass");
  ck(legacy_error_seen&&!old_ok,"legacy pixel-only watchdog control rejects the same legal stream");
  ck(busy_armed&&blocked_hint_count>0&&saved_credit_count==1&&stale_checks>0,"healthy-read collision and stale-event coverage both execute");
  ck(credits>1000,"raw source activity repeatedly extends only source-wait intervals");
  $display("[PASS] raw_bytes=%0d pixels=%0d writes=%0d reads=%0d max_pixel_gap_cycles=%0d credits=%0d busy_saved=%0d stale_checks=%0d legacy_rejected=%0d",raw_count,pixel_count,write_count,read_count,max_pixel_gap,credits,saved_credit_count,stale_checks,legacy_error_seen);
  $display("PASS tb_v3_progress_wide_independent errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #1500000000;
  $display("[FAIL] independent wide source-gap watchdog input=%0d pixels=%0d writes=%0d errors=1",input_index,pixel_count,write_count);
  $display("PASS tb_v3_progress_wide_independent errors=1 comparisons=%0d",comparisons);$finish;
 end
endmodule
