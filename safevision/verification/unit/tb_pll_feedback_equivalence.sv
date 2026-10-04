`timescale 1ns/1ps

// Compile the pre-change wrappers as *_before with the same official TD models.
// The runner extracts them from an explicit Git ref; no copied vendor IP here.
module pll_equiv_monitor #(
    parameter integer ID=0,
    parameter real PERIOD_NS=10.0
)(
    input wire before_clk,
    input wire after_clk,
    input wire ready,
    output integer checks=0
);
    real last_edge=-1.0;
    real delta;
    function automatic real absr(input real v);
        absr=(v<0.0)?-v:v;
    endfunction
    always @(before_clk or after_clk) begin
        #0.001; // Let both zero-delay wrapper connections settle.
        if (ready) begin
            if(before_clk !== after_clk)
                $fatal(1,"PLL edge equivalence id=%0d at %0t",ID,$time);
            if(last_edge>=0.0) begin
                delta=$realtime-last_edge;
                if(absr(delta-PERIOD_NS/2.0)>0.010)
                    $fatal(1,"PLL half period id=%0d got=%0.6f expected=%0.6f",ID,delta,PERIOD_NS/2.0);
            end
            last_edge=$realtime;
            checks=checks+1;
        end else last_edge=-1.0;
    end
endmodule

module tb_pll_feedback_equivalence;
    reg refclk=0;
    reg reset=1;
    reg ready=0;
    wire [10:0] old_clk,new_clk;
    wire [3:0] old_lock,new_lock;
    integer counts[0:10];
    integer i,total=0;
    always #10 refclk=~refclk;
    sv_system_pll_before o0(.refclk(refclk),.reset(reset),.extlock(old_lock[0]),.clk0_out(old_clk[0]),.clk1_out(old_clk[1]),.clk2_out(old_clk[2]));
    sv_system_pll n0(.refclk(refclk),.reset(reset),.extlock(new_lock[0]),.clk0_out(new_clk[0]),.clk1_out(new_clk[1]),.clk2_out(new_clk[2]));
    sv_video_vga_pll_before o1(.refclk(refclk),.reset(reset),.extlock(old_lock[1]),.clk0_out(old_clk[3]),.clk1_out(old_clk[4]),.clk2_out(old_clk[5]));
    sv_video_vga_pll n1(.refclk(refclk),.reset(reset),.extlock(new_lock[1]),.clk0_out(new_clk[3]),.clk1_out(new_clk[4]),.clk2_out(new_clk[5]));
    sv_video_hd_pll_before o2(.refclk(refclk),.reset(reset),.extlock(old_lock[2]),.clk0_out(old_clk[6]),.clk1_out(old_clk[7]),.clk2_out(old_clk[8]));
    sv_video_hd_pll n2(.refclk(refclk),.reset(reset),.extlock(new_lock[2]),.clk0_out(new_clk[6]),.clk1_out(new_clk[7]),.clk2_out(new_clk[8]));
    sv_audio_pll_before o3(.refclk(refclk),.reset(reset),.extlock(old_lock[3]),.clk0_out(old_clk[9]),.clk1_out(old_clk[10]));
    sv_audio_pll n3(.refclk(refclk),.reset(reset),.extlock(new_lock[3]),.clk0_out(new_clk[9]),.clk1_out(new_clk[10]));
    generate for(genvar k=0;k<11;k=k+1) begin : measure
        localparam real P=(k==0)?10.0:(k==1||k==2)?8.0:
            (k==3)?3.529411765:(k==4)?39.705882353:(k==5)?7.941176471:
            (k==6)?80.0:(k==7)?13.483146067:(k==8)?2.696629213:
            (k==9)?40.0:81.377868852;
        pll_equiv_monitor #(.ID(k),.PERIOD_NS(P)) m(.before_clk(old_clk[k]),.after_clk(new_clk[k]),.ready(ready),.checks(counts[k]));
    end endgenerate
    always @(old_lock or new_lock) begin
        #0.001;
        if(old_lock !== new_lock) $fatal(1,"PLL lock/reset equivalence at %0t",$time);
    end
    // C1 and C2 of the system PLL must retain their 180 degree separation.
    always @(new_clk[1] or new_clk[2]) begin
        #0.001;
        if(ready && (new_clk[1]^new_clk[2]) !== 1'b1)
            $fatal(1,"System PLL memory phase no longer 180 degrees");
    end
    task automatic exercise;
        begin
            repeat(10) @(negedge refclk);
            reset=0;
            wait(old_lock==4'b1111 && new_lock==4'b1111);
            #200;
            ready=1;
            #30000;
            ready=0;
            reset=1;
            #100;
            if(old_lock!==4'b0000 || new_lock!==4'b0000)
                $fatal(1,"PLL locks did not drop during reset");
        end
    endtask
    initial begin
        exercise();
        exercise(); // A complete reset/relock cycle as well as power-up.
        for(i=0;i<11;i=i+1) begin
            if(counts[i]<500) $fatal(1,"Insufficient clock coverage id=%0d count=%0d",i,counts[i]);
            total=total+counts[i];
        end
        $display("PASS tb_pll_feedback_equivalence: 4 PLLs, 11 clocks, %0d edge/half-period checks, 180-degree memory phase, two lock/reset cycles",total);
        $finish;
    end
    initial begin
        #200000;
        $fatal(1,"PLL equivalence watchdog");
    end
endmodule
