`timescale 1ns/1ps
module tb_memory_arbiter_protocol;
    reg clk=0;
    always #4 clk=~clk;
    reg rst_n=0,rd_req=0,wr_req=0,sd_req=0,sd_wr=0,zero_latency=0;
    reg [31:0] rd_addr=0,wr_addr=0,sd_addr=0,wr_data=0,sd_wdata=0;
    reg [15:0] rd_len=0,wr_len=0,sd_len=0;
    wire rd_ack,wr_ack,sd_ack,rd_busy,wr_busy,sd_busy,rd_valid,sd_valid;
    wire mem_req,mem_wr;
    wire [31:0] mem_addr,mem_wdata,rd_data,sd_rdata;
    wire [3:0] mem_wstrb;
    reg [3:0] valid_pipe=0;
    reg [31:0] data_pipe[0:3];
    reg [15:0] cycle=0;
    wire mem_ready=(cycle%5!=1 && cycle%5!=2);
    wire fire=mem_req&&mem_ready;
    function automatic [31:0] golden(input [31:0] addr);
        golden=addr ^ 32'ha5c37812;
    endfunction
    wire mem_valid=zero_latency ? (fire&&!mem_wr) : valid_pipe[3];
    wire [31:0] mem_rdata=zero_latency ? golden(mem_addr) : data_pipe[3];
    memory_arbiter dut(
        .clk(clk),.rst_n(rst_n),.video_fifo_level(16'd0),
        .rd_req(rd_req),.rd_addr(rd_addr),.rd_len(rd_len),.rd_ack(rd_ack),.rd_busy(rd_busy),.rd_data(rd_data),.rd_data_valid(rd_valid),
        .wr_req(wr_req),.wr_addr(wr_addr),.wr_data(wr_data),.wr_len(wr_len),.wr_ack(wr_ack),.wr_busy(wr_busy),
        .sd_req(sd_req),.sd_wr(sd_wr),.sd_addr(sd_addr),.sd_wdata(sd_wdata),.sd_len(sd_len),.sd_ack(sd_ack),.sd_busy(sd_busy),
        .sd_rdata(sd_rdata),.sd_rdata_valid(sd_valid),.mem_req(mem_req),.mem_wr(mem_wr),.mem_addr(mem_addr),
        .mem_wdata(mem_wdata),.mem_wstrb(mem_wstrb),.mem_ready(mem_ready),.mem_rdata(mem_rdata),.mem_rdata_valid(mem_valid),
        .wr_starve_cnt(),.rd_starve_cnt());
    integer expected_ch=0,expected_len=0,commands=0,responses=0,bursts=0,checks=0,i;
    reg running=0,expected_write=0,stalled=0;
    reg [31:0] base=0,held_addr=0,held_data=0;
    reg held_wr=0;
    reg [3:0] held_strb=0;
    always @(posedge clk) begin
        if(!rst_n) begin
            cycle<=0;valid_pipe<=0;stalled<=0;
            for(i=0;i<4;i=i+1) data_pipe[i]<=0;
        end else begin
            cycle<=cycle+1'b1;
            valid_pipe<={valid_pipe[2:0],fire&&!mem_wr&&!zero_latency};
            data_pipe[0]<=golden(mem_addr);
            for(i=1;i<4;i=i+1) data_pipe[i]<=data_pipe[i-1];
            if(stalled && (mem_req!==1'b1 || mem_addr!==held_addr || mem_wdata!==held_data || mem_wr!==held_wr || mem_wstrb!==held_strb))
                $fatal(1,"request changed while memory applied backpressure");
            stalled<=mem_req&&!mem_ready;
            held_addr<=mem_addr;held_data<=mem_wdata;held_wr<=mem_wr;held_strb<=mem_wstrb;
            if(fire) begin
                if(!running || commands>=expected_len || mem_addr!==base+commands*4 || mem_wr!==expected_write)
                    $fatal(1,"accepted request count/address/mode mismatch: cmd=%0d addr=%08h",commands,mem_addr);
                if(expected_write && (mem_wdata!==golden(base+commands*4) || mem_wstrb!==4'hf))
                    $fatal(1,"write word corrupted/repeated under backpressure");
                if(!expected_write && mem_wstrb!==0) $fatal(1,"read has write strobes");
                commands=commands+1;checks=checks+1;
            end
            if(rd_valid||sd_valid) begin
                if(!running || expected_write || responses>=expected_len ||
                   (expected_ch==1 && (!rd_valid||sd_valid||rd_data!==golden(base+responses*4))) ||
                   (expected_ch==3 && (!sd_valid||rd_valid||sd_rdata!==golden(base+responses*4))))
                    $fatal(1,"response data/order/channel mismatch");
                responses=responses+1;checks=checks+1;
            end
            if(mem_valid && !(rd_valid||sd_valid)) $fatal(1,"a legitimate memory response was lost");
        end
    end

    always @(negedge clk) if(running) begin
        wr_data=golden(base+commands*4);
        sd_wdata=golden(base+commands*4);
    end
    task automatic burst(input integer ch,input bit iswrite,input integer len,input [31:0] addr,input bit instant);
        integer watchdog;
        begin
            @(negedge clk);
            expected_ch=ch;expected_write=iswrite;expected_len=(len==0)?1:len;
            base=addr;commands=0;responses=0;running=1;zero_latency=instant;
            wr_data=golden(addr);sd_wdata=golden(addr);
            case(ch)
                1:begin rd_addr=addr;rd_len=len;rd_req=1;end
                2:begin wr_addr=addr;wr_len=len;wr_req=1;end
                3:begin sd_addr=addr;sd_len=len;sd_wr=iswrite;sd_req=1;end
            endcase
            wait((ch==1&&rd_ack)||(ch==2&&wr_ack)||(ch==3&&sd_ack));
            @(negedge clk);rd_req=0;wr_req=0;sd_req=0;
            if(ch==3) sd_wr=!iswrite;
            watchdog=0;
            while((ch==1&&rd_busy)||(ch==2&&wr_busy)||(ch==3&&sd_busy)) begin
                @(negedge clk);watchdog=watchdog+1;
                if(watchdog>2000) $fatal(1,"burst failed to complete");
            end
            if(commands!=expected_len || responses!=(iswrite?0:expected_len))
                $fatal(1,"wrong exact burst length: commands=%0d responses=%0d",commands,responses);
            running=0;bursts=bursts+1;
            repeat(5) @(negedge clk);
        end
    endtask
    initial begin
        repeat(5) @(negedge clk);rst_n=1;
        burst(1,0,0,32'h1000,0);burst(1,0,1,32'h2000,0);burst(1,0,2,32'h3000,0);
        burst(1,0,16,32'h4000,0);burst(1,0,32,32'h5000,0);
        burst(2,1,1,32'h6000,0);burst(2,1,7,32'h7000,0);burst(2,1,16,32'h8000,0);
        burst(3,0,1,32'h9000,0);burst(3,0,7,32'ha000,0);
        burst(3,1,1,32'hb000,0);burst(3,1,16,32'hc000,0);
        burst(1,0,2,32'hd000,1);burst(3,0,16,32'he000,1);

        @(negedge clk);rd_addr=32'hf000;rd_len=32;rd_req=1;
        wait(rd_ack);
        @(negedge clk);rd_req=0;rst_n=0;
        repeat(3) @(negedge clk);rst_n=1;
        burst(1,0,7,32'h10000,0);
        $display("PASS tb_memory_arbiter_protocol: bursts=%0d ordered command/response checks=%0d; stalls, both readers/writers, zero/delayed responses, SD mode latch, reset",bursts,checks);
        $finish;
    end
    initial begin #200000; $fatal(1,"protocol TB timeout"); end
endmodule
