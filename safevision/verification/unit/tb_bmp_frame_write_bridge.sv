`timescale 1ns/1ps
`include "pixel_format_defs.vh"
module tb_bmp_frame_write_bridge;
    reg clk=0;always #4 clk=~clk;
    reg rst_n=0,start=0,top_down=0,valid=0;
    reg [1:0] slot=0;reg [31:0] base=0;reg [15:0] pixel=0;
    wire ready,req,done,crc,error;wire [31:0] addr,data;wire [15:0] len;
    wire [3:0] slots;wire [18:0] count;
    reg ack=0;integer words=0,checks=0;integer direction=0;
    bmp_frame_write_bridge #(.GAP_TIMEOUT(32'd100000)) dut(
      .clk(clk),.rst_n(rst_n),.start(start),.top_down(top_down),.slot_sel(slot),.slot_base(base),
      .din(pixel),.din_valid(valid),.din_ready(ready),.wr_req(req),.wr_addr(addr),
      .wr_data(data),.wr_len(len),.wr_ready(ack),.wr_done(done),.slot_valid(slots),
      .crc_ok(crc),.crc_value(),.px_cnt(count),.wr_error(error),.err_code(),.err_detail());
    function [15:0] source(input integer n);source=(n*29)^16'h5ac3;endfunction
    integer row,col;reg [31:0] expected_addr;
    always @(posedge clk)begin
      ack<=0;
      if(rst_n && req && !ack)begin
        row=words/320;col=(words%320)*2;
        expected_addr=base+((direction ? row : 479-row)*640+col)*2;
        if(addr!==expected_addr || data!=={source(words*2+1),source(words*2)} || len!==1)
          $fatal(1,"row/pack/address mismatch word=%0d addr=%h want=%h data=%h",words,addr,expected_addr,data);
        words=words+1;checks=checks+1;ack<=1;
      end
      if(rst_n && error)$fatal(1,"unexpected write timeout/error");
    end
    task send(input integer n);
      @(negedge clk);pixel=source(n);valid=1;
      do @(posedge clk);while(!ready);
      @(negedge clk);valid=0;
    endtask
    integer d,n;
    initial begin
      #80;@(negedge clk);rst_n=1;
      for(d=0;d<2;d=d+1)begin
        direction=d;words=0;base=d?`SV_IMG3_BASE:`SV_IMG0_BASE;slot=d?3:0;
        // Parser metadata can change after start and before its first pixel.
        top_down=!d;@(negedge clk);start=1;@(negedge clk);start=0;top_down=d;
        for(n=0;n<307200;n=n+1)begin
          send(n);
          if(n==63)begin
            // Match native frame_writer: a stray start during an active frame
            // must not reset only the adapter's address/packing state.
            @(negedge clk);start=1;@(negedge clk);start=0;
            repeat(70000)@(negedge clk);
          end
        end
        wait(done);#1;
        if(words!=153600 || count!=307200 || !crc || !slots[slot])$fatal(1,"incomplete frame/CRC");
        $display("[PASS] BMP direction=%0d slot=%0d words=%0d gap=70000",d,slot,words);
        repeat(4)@(negedge clk);
      end
      $display("PASS tb_bmp_frame_write_bridge: checks=%0d",checks);$finish;
    end
    initial begin #100_000_000;$fatal(1,"bridge watchdog");end
endmodule
