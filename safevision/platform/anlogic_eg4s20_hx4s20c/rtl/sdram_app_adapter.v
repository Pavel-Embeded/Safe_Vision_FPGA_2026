// Word transaction boundary for the official packaged SDRAM controller.
// The physical side follows the M-11 observed shape: consecutive addresses,
// >=2 write-enable beats and >=16 quiet clocks between hardware bursts.
// A single buffered word is followed by a fully MASKED neighbour beat. Never
// invent or overwrite the neighbour's data. The encrypted vendor IP is intact.
// Accepted writes are buffered. write_idle is the completion barrier used by
// the board's frame publisher; CRC of the input stream is not SDRAM readback.
// req/wr/addr/wdata/wstrb must be held until ready accepts the transaction.
// Writes have one registered address-check cycle before their acceptance.
module sdram_app_adapter #(
    parameter [31:0] READ_TIMEOUT=32'd4096,
    parameter integer FAST_READ=0,
    parameter integer PREFETCH_READ=0
) (
    input wire clk,rst_n,req,wr,
    input wire [31:0] addr,wdata,input wire [3:0] wstrb,
    output reg [31:0] rdata,output reg rdata_valid,
    output wire ready,init_done,
    input wire Sdr_init_done,Sdr_init_ref_vld,Sdr_busy,
    output reg App_wr_en,output reg [20:0] App_wr_addr,
    output reg [3:0] App_wr_dm,output reg [31:0] App_wr_din,
    output reg App_rd_en,output reg [20:0] App_rd_addr,
    input wire Sdr_rd_en,input wire [31:0] Sdr_rd_dout,
    output wire write_idle,
    output reg protocol_fault
);
    localparam integer WB=16,RB=16;
    localparam [2:0] H_IDLE=0,H_WRITE=1,H_WGAP=2,H_READ=3,H_WAIT=4,H_RGAP=5;
    reg [2:0] state;
    reg [31:0] wbuf[0:WB-1];reg [3:0] wdm[0:WB-1];
    reg [31:0] wbase,wnext;
    reg [4:0] wcnt,wi,physical_words;
    reg [5:0] widle;
    reg w_checked,w_contiguous;
    reg [4:0] gap;
    reg [31:0] rbuf[0:2*RB-1];
    reg [31:0] rfbase,rexp;
    reg [5:0] rcnt;
    reg [4:0] rhead,rcmd_i,rcv_i;
    reg fill_bank,next_fill_bank,contiguous_refill;
    reg [31:0] prefetch_addr;
    reg [4:0] read_quiet;
    reg r_go,r_sv;
    reg [31:0] read_wait;
    wire idle_hw=(state==H_IDLE);
    wire w_can=Sdr_init_done&&idle_hw&&(wcnt<WB)&&w_checked&&w_contiguous&&!r_go&&!r_sv;
    wire w_accept=req&&wr&&w_can;
    // ★ 2026-10-11：地址比较只用低 21 位 —— 恰好等于 SDRAM 容量（ADDR_WIDTH=21，
    //   2M word），所以**语义完全等价**，但把 32 位比较器缩短 11 位。
    //   动机：125MHz 档 MEM 域最差路径就是
    //     core/arbiter/cur_addr → adapter/contiguous_refill（8.516ns，含 2 个 ADDER）
    //   把 `addr==rexp` 从 32 位缩到 21 位，给 125MHz 让出余量。
    wire r_hit=(rcnt!=0)&&(addr[20:0]==rexp[20:0]);
    wire r_serve=req&&!wr&&idle_hw&&(wcnt==0)&&r_hit&&!r_sv;
    // Completed cache words are independent of the physical command bus.
    // Drain them during the mandatory read quiet interval too. No new SDRAM
    // command can start until H_RGAP expires; this preserves all 16 quiet
    // clocks while avoiding a second, unnecessary 16-clock host stall.
    wire r_fast_can=(idle_hw||state==H_RGAP||
                    (PREFETCH_READ&&(state==H_READ||state==H_WAIT)))&&(wcnt==0)&&r_hit;
    wire r_fast_fire=req&&!wr&&r_fast_can&&Sdr_init_done;
    wire need_flush=(wcnt!=0)&&((wcnt==WB)||(widle>=48)||
                    (req&&(!wr||(w_checked&&!w_contiguous))));
    assign init_done=Sdr_init_done&&!protocol_fault;
    assign ready=rst_n&&Sdr_init_done&&!protocol_fault&&(wr?w_can:(FAST_READ?r_fast_can:r_go));
    assign write_idle=rst_n&&Sdr_init_done&&!protocol_fault&&idle_hw&&(wcnt==0)&&!App_wr_en;

    always @(posedge clk or negedge rst_n)begin
      if(!rst_n)begin
        state<=H_IDLE;wbase<=0;wnext<=0;wcnt<=0;wi<=0;physical_words<=0;widle<=0;gap<=0;
        w_checked<=0;w_contiguous<=0;
        rfbase<=0;rexp<=0;rcnt<=0;rhead<=0;rcmd_i<=0;rcv_i<=0;r_go<=0;r_sv<=0;
        fill_bank<=0;next_fill_bank<=0;contiguous_refill<=0;prefetch_addr<=0;read_quiet<=0;
        rdata<=0;rdata_valid<=0;App_wr_en<=0;App_wr_addr<=0;App_wr_dm<=15;App_wr_din<=0;
        App_rd_en<=0;App_rd_addr<=0;
        read_wait<=0;protocol_fault<=0;
      end else if(protocol_fault)begin
        // A lost vendor response makes the transaction/slot epoch ambiguous.
        // Fence the client until common reset; never serve a partial cache.
        App_wr_en<=0;App_rd_en<=0;rdata_valid<=0;r_go<=0;r_sv<=0;
      end else begin
        App_wr_en<=0;App_rd_en<=0;rdata_valid<=0;
`ifdef SAFEVISION_DIAG_D10R
        // ★★ 2026-10-11 细化版（D10R）：把"释放 DQM"推迟到写流水排空之后。
        //
        //   队友原版（7fb219c）是 idle 立刻 `App_wr_dm<=0`。但按他们自己的说明，
        //   官方控制器把 App_wr_dm **连续**打到 SDRAM DQM；而本适配器在写突发末尾
        //   会发**填充拍**（第 163/164 行：`wi>=wcnt ⇒ App_wr_dm<=4'hf`）。
        //   如果控制器把写使能也流水 1~2 拍，那么突发结束后紧跟的那一拍会**再打一次写**
        //   —— 此时 dm 已被原版改成 0 ⇒ **把填充字真写进邻字**（本该被掩）。
        //   后果：每写完一个突发就坏掉一个字 ⇒ 帧内散布错字 = 花屏。
        //
        //   ⇒ 现在：前 6 个静默拍保持 15（邻字仍被掩住），之后才释放成 0。
        //     写→读的最小静默间隔是 16 拍（H_WGAP），DQM 流水约 9 级
        //     （7 级 app/IO + 2 拍 SDRAM）⇒ 读命令最早在第 17 拍发出时，
        //     dm 已经 0 满 11 拍 ⇒ 读**不会**被掩。两个约束同时满足。
        App_wr_dm <= (read_quiet>=5'd6) ? 4'h0 : App_wr_dm;
`else
        App_wr_dm<=0;
        // ★ 2026-10-11 从队友提交 7fb219c 移植（DQM 读掩码真根因修复）：
        //   The official controller continuously pipelines App_wr_dm to SDRAM
        //   DQM, even with App_wr_en LOW. DQM also disables READ output after
        //   two SDRAM clocks. A single-word flush ends with a masked neighbour;
        //   retaining 4'hf afterwards makes the next read return pull-up ones.
        //   Mask only the corresponding physical write beat. The existing
        //   >=16-clock write/read quiet interval drains the DQM pipeline before
        //   any read; never mask reads or unmask the neighbour's write beat.
`endif
        // Count quiet bus edges from the LAST physical command, not from the
        // last response. Response collection and the legal 16-edge gap overlap.
        if(App_rd_en||App_wr_en)read_quiet<=0;
        else if(read_quiet<16)read_quiet<=read_quiet+1'b1;
        if(state==H_READ||state==H_WAIT)begin
          if(Sdr_rd_en)read_wait<=0;
          else if(read_wait>=READ_TIMEOUT)protocol_fault<=1;
          else read_wait<=read_wait+1'b1;
        end else read_wait<=0;
        // The arbiter holds the complete word transaction while ready is low.
        // Capture its continuity check separately from the acceptance/CE cone.
        // Never reuse a check after acceptance, cancellation or a HW burst.
        if(!Sdr_init_done||!idle_hw||!req||!wr||w_accept)w_checked<=0;
        else if(!w_checked)begin
          w_checked<=1;w_contiguous<=(wcnt==0)||(addr[20:0]==wnext[20:0]);
        end
        // Only the externally observed ready/req edge consumes a cached word.
        if(FAST_READ)begin
          r_go<=0;r_sv<=0;
          if(r_fast_fire)begin
            rdata<=rbuf[rhead];rdata_valid<=1;rhead<=rhead+1'b1;
            rcnt<=rcnt-1'b1;rexp<=rexp+1'b1;
          end
        end else begin
          r_go<=Sdr_init_done&&r_serve&&!r_go;
          if(r_go&&req&&!wr)begin
            rdata<=rbuf[rhead];r_sv<=1;rhead<=rhead+1'b1;
            rcnt<=rcnt-1'b1;rexp<=rexp+1'b1;
          end else if(r_sv)begin rdata_valid<=1;r_sv<=0;end
        end

        if(w_accept)begin
          wbuf[wcnt]<=wdata;wdm[wcnt]<=~wstrb;
          if(wcnt==0)wbase<=addr;
          wnext<=addr+1'b1;wcnt<=wcnt+1'b1;widle<=0;
        end else if(idle_hw&&wcnt!=0&&widle!=63)widle<=widle+1'b1;

        // Invalidate eagerly on a presented write, before its acceptance.
        // This is conservative (a later read simply refetches) and removes
        // the 32-bit contiguous-address comparator from the cache-counter
        // update path. No write can coexist with a cached read acceptance.
        if(req&&wr)begin
          rcnt<=0;r_go<=0;
          // If an unaccepted write is later cancelled, the in-flight refill
          // must publish a fresh bank/head, not append to an invalidated FIFO.
          contiguous_refill<=0;
        end

        case(state)
          H_IDLE:begin
            if(Sdr_init_done&&need_flush&&!w_accept)begin
              wi<=0;physical_words<=(wcnt==1)?5'd2:wcnt;state<=H_WRITE;
            end else if(Sdr_init_done&&req&&!wr&&!r_hit&&(wcnt==0)&&!r_sv&&!r_go)begin
              // No cache acceptance is possible in H_READ/H_WAIT.
              // Keep the old count until the complete replacement block is
              // received. Clearing here is redundant and puts addr==rexp
              // through a wide comparator into the counter's update cone.
              rfbase<=addr;rcmd_i<=0;rcv_i<=0;state<=H_READ;
              fill_bank<=0;contiguous_refill<=0;
              if(PREFETCH_READ)rcnt<=0;
            end else if(PREFETCH_READ&&FAST_READ&&Sdr_init_done&&req&&!wr&&r_hit&&
                        wcnt==0&&rcnt<=RB&&prefetch_addr<32'h00200000)begin
              // Refill the FREE bank while the client drains completed words
              // in the other bank. This is read-only speculation; arbitrary
              // jumps replace the cache and every presented write invalidates
              // it. Never expose a partially received physical block.
              rfbase<=prefetch_addr;fill_bank<=next_fill_bank;contiguous_refill<=1;
              rcmd_i<=0;rcv_i<=0;state<=H_READ;
            end
          end
          H_WRITE:begin
            App_wr_en<=1;App_wr_addr<=wbase[20:0]+wi;
            if(wi<wcnt)begin App_wr_din<=wbuf[wi];App_wr_dm<=wdm[wi];end
            else begin App_wr_din<=0;App_wr_dm<=4'hf;end
            if(wi==physical_words-1'b1)begin
              wcnt<=0;widle<=0;gap<=16;state<=H_WGAP;
            end else wi<=wi+1'b1;
          end
          H_WGAP:begin
            if(gap==0)state<=H_IDLE;else gap<=gap-1'b1;
          end
          H_READ:begin
            App_rd_en<=1;App_rd_addr<=rfbase[20:0]+rcmd_i;
            if(rcmd_i==RB-1)state<=H_WAIT;else rcmd_i<=rcmd_i+1'b1;
          end
          H_WAIT:;
          H_RGAP:begin
            if(gap==0)state<=H_IDLE;else gap<=gap-1'b1;
          end
          default:state<=H_IDLE;
        endcase
        // Receive independently of the command counter; preserve all beats
        // for either short or long vendor response latency.
        if((state==H_READ||state==H_WAIT)&&Sdr_rd_en)begin
          rbuf[PREFETCH_READ?{fill_bank,rcv_i[3:0]}:rcv_i]<=Sdr_rd_dout;
          if(rcv_i==RB-1)begin
            if(PREFETCH_READ&&contiguous_refill&&!(req&&wr))
              rcnt<=rcnt+RB-(r_fast_fire?1'b1:1'b0);
            else begin
              rexp<=rfbase;rcnt<=RB;
              rhead<=PREFETCH_READ?{fill_bank,4'b0}:5'd0;
            end
            prefetch_addr<=rfbase+RB;next_fill_bank<=~fill_bank;
            rcv_i<=0;
            gap<=PREFETCH_READ?(read_quiet>=16?5'd0:5'd16-read_quiet):5'd16;
            state<=H_RGAP;
          end else rcv_i<=rcv_i+1'b1;
        end
      end
    end
    // Sdr_busy/ref_vld are retained vendor diagnostic ports. This controller
    // interface has no per-beat ready handshake; do not reinterpret them as
    // permission to interrupt a consecutive burst mid-way.
    // synthesis translate_off
    initial if(PREFETCH_READ&&!FAST_READ)$fatal(1,"read prefetch requires FAST_READ");
    // synthesis translate_on
endmodule
