`timescale 1ns/1ps
module tb_v3_fade_gate151;
reg clk=0,rst_n=0,valid=0,active=0;always #5 clk=~clk;
reg[15:0] front=0,back=0;reg[7:0] alpha=0;wire[15:0] pixel,gold;wire vo,go;
integer f,b,a,en,k,errors=0,comparisons=0;reg[31:0] rng=32'h5791acfe;
v3_frame_fade_blend dut(clk,rst_n,valid,active,front,back,alpha,pixel,vo);
v3_fade_reference151 reference(clk,rst_n,valid,active ? front:16'd0,back,active ? alpha:8'd0,gold,go);
always@(posedge clk)begin #1;if(rst_n)begin comparisons = comparisons + 1;
if({pixel,vo}!=={gold,go})begin errors = errors + 1;if(errors<8)$display("[FAIL] three-edge fade RGB/valid reference differs f=%h b=%h a=%h enable=%b",front,back,alpha,active);end end end
task step;begin begin @(negedge clk);end  end endtask
initial begin
repeat(4)step();rst_n=1;valid=1;

front=16'hxxxx;back=16'hf123;alpha=8'hff;active=0;valid=1;repeat(8)step();
for(f=0;f<64;f = f + 1)for(b=0;b<64;b = b + 1)for(a=0;a<256;a = a + 1)for(en=0;en<2;en = en + 1)begin
front={f[4:0],f[5:0],f[4:0]};back={b[4:0],b[5:0],b[4:0]};alpha=a;active=en;valid=(a%3!=0);step();end
for(k=0;k<200000;k = k + 1)begin rng=rng*1664525+1013904223;front=rng[15:0];back=rng[31:16];rng=rng*1664525+1013904223;alpha=rng[7:0];active=rng[8];valid=rng[9];rst_n=(k%1009!=0);step();end
rst_n=1;repeat(8)step();if(errors==0)$display("[PASS] exhaustive channel pairs/all256alphas/both enable states plus200000random reset and invalid cycles");
$display("PASS tb_v3_fade_gate151 comparisons=%0d errors=%0d",comparisons,errors);$finish;end
initial begin #30000000;$display("[FAIL] fade gate watchdog errors=1");$finish;end
endmodule
