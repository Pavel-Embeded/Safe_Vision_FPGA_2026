`timescale 1ns/1ps
module tb_a_basics;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,enable=0,key=0,sig=0,start=0,warning=0,emergency=0,clear=0;
    wire [9:0] count; wire tick,tick1; wire [0:0] count1;
    wire level,level1,level_idle1,rise,fall; wire [1:0] mode;
    a_counter counter(.clk(clk),.rst_n(rst_n),.enable(enable),.count(count),.tick(tick));
    a_counter #(.MODULO(1),.WIDTH(1)) single(.clk(clk),.rst_n(rst_n),.enable(enable),.count(count1),.tick(tick1));
    a_debounce #(.STABLE_CYCLES(4)) db(.clk(clk),.rst_n(rst_n),.key_async(key),.key_level(level));
    a_debounce #(.STABLE_CYCLES(1)) db1(.clk(clk),.rst_n(rst_n),.key_async(key),.key_level(level1));
    a_debounce #(.STABLE_CYCLES(4),.RESET_LEVEL(1)) dbi(.clk(clk),.rst_n(rst_n),.key_async(key),.key_level(level_idle1));
    a_edge_detect edges(.clk(clk),.rst_n(rst_n),.sig(sig),.rise(rise),.fall(fall));
    a_mode_fsm fsm(.clk(clk),.rst_n(rst_n),.start(start),.warning(warning),.emergency(emergency),.clear(clear),.mode(mode));
    integer checks=0,rc=0,rm=0,stable=0,stablei=0;
    reg meta=0,sync=0,meta_i=1,sync_i=1,last=0,rl=0,rli=1;
    reg et=0,er=0,ef=0,el1=0;
    task check(input  ok,input [4095:0] why);
        begin  ok = (ok === 1'b1); checks = checks + 1; if(!ok) begin $display("[FAIL] tb_a_basics: %s",why); $finish; end
     end endtask
    task cycle;
        begin
            @(posedge clk);
            if(!rst_n) begin rc=0;rm=0;et=0;er=0;ef=0;last=0;meta=0;sync=0;meta_i=1;sync_i=1;rl=0;rli=1;el1=0;stable=0;stablei=0; end
            else begin
                et=enable && rc==999;
                if(enable) rc=(rc+1)%1000;
                er=sig && !last; ef=!sig && last; last=sig;

                if(sync==rl) stable=0;
                else begin stable = stable + 1; if(stable==4) begin rl=sync;stable=0;end end
                if(sync_i==rli) stablei=0;
                else begin stablei = stablei + 1; if(stablei==4) begin rli=sync_i;stablei=0;end end
                el1=sync;
                sync=meta;meta=key;
                sync_i=meta_i;meta_i=key;
                if(emergency) rm=3;
                else if(rm==3) begin if(clear && !warning) rm=0; end
                else if(warning) rm=2;
                else if(clear) rm=0;
                else if(rm==0 && start) rm=1;
            end
            #1;
            check(count===rc[9:0] && tick===et,"counter threshold/count/tick");
            check(count1===1'b0 && tick1===(rst_n && enable),"MODULO=1");
            check({rise,fall}==={er,ef},"edge pulse");
            check({level,level1,level_idle1}==={rl,el1,rli},"debounce synchronization/run length");
            check(mode===rm[1:0],"FSM priority/latching");

     end endtask
    integer i;
    initial begin
        cycle(); @(negedge clk);rst_n=1;enable=1;cycle();
        for(i=0;i<2100;i = i + 1) begin

            @(negedge clk);
            key=(i<40) ? i[0]:(i/8)%2;sig=(i%7)<3;
            start=(i%17)==1;warning=(i%17)==5;emergency=(i%17)==9;clear=(i%17)==13;
            cycle();
        end
        for(i=0;i<1200;i = i + 1) begin
            @(negedge clk);enable=(i%11)<8;key=(i/4)%2;
            {start,warning,emergency,clear}=i[3:0]; cycle();
        end
        #2 rst_n=0;#1;
        check({count,tick,level,rise,fall,mode}===0,"asynchronous reset assertion");
        cycle();@(negedge clk);rst_n=1;
        repeat(20) cycle();
        $display("PASS tb_a_basics: %0d checks",checks);$finish;
    end
    initial begin #100000; begin $display("[FAIL] tb_a_basics watchdog"); $finish; end  end
endmodule
