`timescale 1ns/1ps
module tb_font8x16_rom;
    reg clk=0; always #5 clk=~clk;
    reg [11:0] addr=0;wire [7:0] bits;
    font8x16_rom #(.FONT_FILE("font8x16.mem")) dut(.clk(clk),.addr(addr),.row_bits(bits));
    reg [7:0] golden [0:4095];
    integer checks=0,i,r;reg [7:0] old_bits;
    reg [7:0] idx=0;reg [1:0] mode=0;reg [3:0] tens=6,ones=0;reg ok=1;
    wire [7:0] code;
    reg [11:0] cx=0,cy=0;wire [7:0] coordinate_code;reg [87:0] coordinate_ref;
    osd_coordinate_text coords(.char_index(idx),.x_value(cx),.y_value(cy),.char_code(coordinate_code));
    osd_status_text text(.char_index(idx),.mode(mode),.fps_tens(tens),.fps_ones(ones),.sd_ok(ok),.char_code(code));
    reg [303:0] ref_text;
    task check(input  yes,input [4095:0] why);
        begin  yes = (yes === 1'b1); checks = checks + 1;if(!yes) begin $display("[FAIL] font/status: %s",why); $finish; end
     end endtask
    initial begin
        $readmemh("font8x16.mem",golden);

        check(golden["F"*16+1]===8'h7c && golden["F"*16+7]===8'h78 &&
              golden["F"*16+13]===8'h40,"F geometry");
        check(golden["R"*16+9]===8'h50 && golden["R"*16+11]===8'h48,"R geometry");
        check(golden["6"*16+1]===8'h38 && golden[":"*16+3]===8'h10,"digits/symbols");
        for(i=0;i<4096;i = i + 1) begin
            @(negedge clk); old_bits=bits;addr=i;#1;
            if(i>0) check(bits===old_bits,"no combinational read");
            @(posedge clk);#1;check(bits===golden[i] && !((^(bits)) === 1'bx),"synchronous read/complete init");
        end
        for(r=0;r<4;r = r + 1) begin
            mode=r;
            case(r)
                0:ref_text="SAFEVISION MODE:IDLE      FPS:60 SD:OK";
                1:ref_text="SAFEVISION MODE:NORMAL    FPS:60 SD:OK";
                2:ref_text="SAFEVISION MODE:WARNING   FPS:60 SD:OK";
                3:ref_text="SAFEVISION MODE:EMERGENCY FPS:60 SD:OK";
            endcase
            for(i=0;i<38;i = i + 1) begin idx=i;#1;check(code===ref_text[(37-i)*8 +: 8],"status mode text");end
        end
        idx=36;ok=0;#1;check(code=="-","SD failure text");idx=37;#1;check(code=="-","SD failure tail");
        idx=30;tens=15;#1;check(code=="?","invalid BCD");idx=31;ones=10;#1;check(code=="?","invalid BCD ones");
        idx=255;#1;check(code==" ","index outside text");
        for(r=0;r<4096;r = r + 1) begin
            cx=r;cy=4095-r;
            $sformat(coordinate_ref,"X:%03h Y:%03h",cx,cy);
            for(i=0;i<11;i = i + 1) if(coordinate_ref[i*8 +: 8]>=8'h61 && coordinate_ref[i*8 +: 8]<=8'h66)
                coordinate_ref[i*8 +: 8]=coordinate_ref[i*8 +: 8]-8'd32;
            for(i=0;i<11;i = i + 1) begin idx=i;#1;check(coordinate_code===coordinate_ref[(10-i)*8 +: 8],"coordinate hex");end
        end
        $display("PASS tb_font8x16_rom: %0d checks",checks);$finish;
    end
    initial begin #150000; begin $display("[FAIL] tb_font8x16_rom watchdog"); $finish; end end
endmodule
