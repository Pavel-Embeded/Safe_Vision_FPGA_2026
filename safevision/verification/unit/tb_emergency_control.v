`timescale 1ns/1ps
module emergency_control_case #(parameter integer POLICY=0,parameter real HALF=6.734)(output reg done);
 initial begin done = 0; end

    reg sclk=0,pclk=0,rst=0;
    always #5 sclk=~sclk;always #(HALF) pclk=~pclk;
    reg valid=0;reg [4:0] payload=0;wire ready;
    reg fs=0;integer phase=0;
    wire active,applied,pending;wire [1:0] dir,level;
    reg [4:0] expected[0:1023];integer put=0,get=0,total=0;
    emergency_control_bridge #(.IMMEDIATE(POLICY)) dut(
      .sys_clk(sclk),.sys_rst_n(rst),.pixel_clk(pclk),.pixel_rst_n(rst),
      .ctrl_valid(valid),.ctrl_ready(ready),.emergency_active(payload[4]),
      .direction(payload[3:2]),.warning_level(payload[1:0]),.frame_start(fs),
      .active(active),.active_direction(dir),.active_level(level),.applied(applied),.pending_o(pending));
    always @(negedge pclk)begin
        if(!rst)begin phase=0;fs=0;end
        else begin phase=(phase+1)%19;fs=(phase==0);end
    end
    always @(posedge sclk or negedge rst)begin
        if(!rst)put=0;
        else if(valid&&ready)begin expected[put]=payload;put=put+1;end
    end
    reg edge_fs;reg [4:0] previous;
    always @(posedge pclk or negedge rst)begin
        if(!rst)begin get=0;previous=0;end
        else begin
            edge_fs=fs;#0.1;
            if(applied)begin
                if(get>=put||{active,dir,level}!==expected[get])begin $display("[FAIL] atomic/order POLICY=%0d got=%0d put=%0d",POLICY,get,put); $finish; end
                if(POLICY==0&&!edge_fs)begin $display("[FAIL] frame policy changed outside vblank"); $finish; end
                get=get+1;total=total+1;
            end else if({active,dir,level}!==previous)begin $display("[FAIL] control changed without apply"); $finish; end
            previous={active,dir,level};
        end
    end
    task send(input [4:0] value);
      begin
        @(negedge sclk);payload=value;valid=1;
        begin begin @(posedge sclk); end while(!ready)begin @(posedge sclk); end end
        @(negedge sclk);valid=0;

     end endtask
    integer i,epoch;
    initial begin
      #37;rst=1;

      for(i=0;i<7;i=i+1)send(i*13+5);
      #1.7;rst=0;valid=0;#39;rst=1;
      for(epoch=0;epoch<2;epoch=epoch+1)begin
        for(i=0;i<256;i=i+1)send(i*13+epoch*7);
        wait(get==put&&!pending);repeat(8)@(posedge pclk);
        if(put!=256||get!=256)begin $display("[FAIL] missing/duplicate emergency request"); $finish; end
        if(epoch==0)begin #2.1;rst=0;#41;rst=1;end
      end
      $display("PASS emergency control policy=%0d half=%0.3f accepted/applied=%0d/%0d two epochs all 32 payloads",POLICY,HALF,put,get);
      done=1;
    end
endmodule
module tb_emergency_control;
 wire [3:0] done;
 emergency_control_case #(.POLICY(0),.HALF(6.734)) a(done[0]);
 emergency_control_case #(.POLICY(1),.HALF(6.734)) b(done[1]);
 emergency_control_case #(.POLICY(0),.HALF(19.861)) c(done[2]);
 emergency_control_case #(.POLICY(1),.HALF(19.861)) d(done[3]);
 initial begin wait(&done);$display("PASS tb_emergency_control");$finish;end
 initial begin #3000000;begin $display("[FAIL] emergency control watchdog"); $finish; end end
endmodule
