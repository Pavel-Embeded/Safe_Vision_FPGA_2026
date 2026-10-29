`timescale 1ns/1ps
module tb_emergency_command_adapter;
    reg clk=0;always #5 clk=~clk;reg rn=0,toggle=0,ready=0;
    reg [4:0] payload=0;wire ack,valid,active;wire [1:0] direction,level;
    emergency_command_adapter dut(.clk(clk),.rst_n(rn),.commit_toggle(toggle),
        .emergency_active(payload[4]),.direction(payload[3:2]),.warning_level(payload[1:0]),
        .commit_ack_toggle(ack),.ctrl_valid(valid),.ctrl_ready(ready),
        .ctrl_active(active),.ctrl_direction(direction),.ctrl_level(level));
    integer received=0,n,epoch,cycles;reg [4:0] expected;
    always @(posedge clk)if(rn&&valid&&ready)begin
        if({active,direction,level}!==expected)begin $display("[FAIL] C adapter payload mismatch"); $finish; end 
        received=received+1;
    end
    initial begin
        for(epoch=0;epoch<2;epoch=epoch+1)begin
            @(negedge clk);rn=0;toggle=0;ready=0;payload=0;
            repeat(3)@(negedge clk);rn=1;
            for(n=0;n<256;n=n+1)begin
                @(negedge clk);expected=(n*13+epoch)%32;payload=expected;toggle=~toggle;
                wait(valid);
                repeat(n%7+1)begin
                    @(negedge clk);
                    if(!valid||{active,direction,level}!==expected||ack==toggle)
                        begin $display("[FAIL] C adapter unstable/early ack while blocked"); $finish; end 
                end
                ready=1;wait(ack==toggle);@(negedge clk);ready=0;
                if(valid)begin $display("[FAIL] C adapter duplicate valid after acceptance"); $finish; end 
            end
        end
        if(received!=512)begin $display("[FAIL] C adapter count mismatch %0d",received); $finish; end 
        $display("PASS tb_emergency_command_adapter accepted=512 all32payloads stalls reset");$finish;
    end
    initial begin #1000000;begin $display("[FAIL] adapter watchdog"); $finish; end end
endmodule
