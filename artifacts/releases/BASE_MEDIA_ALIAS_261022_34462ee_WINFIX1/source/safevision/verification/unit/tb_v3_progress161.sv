`timescale 1ns/1ps
module tb_v3_progress161;
reg clk=0,rst=0;always #5 clk=~clk;
reg[47:0] mem_source=0;reg[203:0] ref_source=0;wire[47:0] md;wire[203:0] rd;wire mv,rv,a,b,c,d;
reg[31:0] rng=32'h7631d4af;integer k,q,errors=0,comparisons=0;
v3_related_status_capture #(.WIDTH(48)) mc(clk,rst,mem_source,md,mv);
v3_related_status_capture #(.WIDTH(204)) rc(clk,rst,ref_source,rd,rv);
v3_progress_original161 original(clk,rst,md,mv,rd,rv,a,b);
v3_progress_reduced161 reduced(clk,rst,md,mv,rd,rv,c,d);
always@(posedge clk or negedge clk)begin #0.001;
comparisons++;
if({a,b,original.observed_transactions,original.observed_bytes,original.observed_state}!=={c,d,reduced.observed_transactions,reduced.observed_bytes,reduced.observed_state})begin errors++;if(errors<8)$display("[FAIL] progress/observed state differs across reset and first-capture boundary");end
if(mv===0 && (md!==0 || original.observed_transactions!==0))begin errors++;$display("[FAIL] memory validity invariant");end
if(rv===0 && (rd!==0 || original.observed_bytes!==0 || original.observed_state!==0))begin errors++;$display("[FAIL] media validity invariant");end
end
initial begin
repeat(4)@(negedge clk);rst=1;
for(k=0;k<1000000;k++)begin
 for(q=0;q<7;q++)begin rng=rng*1664525+1013904223;ref_source=(ref_source<<32)|rng;end
 rng=rng*1664525+1013904223;mem_source={rng,rng[15:0]};
 if(k%197==0)begin #2;rst=0;#1;mem_source=~mem_source;#1;rst=1;end
 if(k%199==0)begin #2;rst=0;#4;rst=1;end
 @(negedge clk);
end
repeat(4)@(negedge clk);if(errors==0)$display("[PASS] extracted original/reduced progress fragments,actual capture module,1000000wide updates and async resets;first-edge state invariant");
$display("PASS tb_v3_progress161 comparisons=%0d errors=%0d",comparisons,errors);$finish;end
initial begin #20000000;$display("[FAIL] progress proof watchdog errors=1");$finish;end
endmodule
