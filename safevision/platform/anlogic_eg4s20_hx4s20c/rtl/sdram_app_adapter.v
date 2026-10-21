// Word transaction boundary for the official packaged SDRAM controller.
// Board22/28: write starts align to4;1..16 real words plus MASKED leading
// and trailing words form4/8/12/16/20 physical commands. Byte masks survive.
// Board30/33: reads also start at4-word boundaries. Filter physical leading
// and trailing responses BEFORE the16-word cache; publish logical words only.
// Clip speculative reads at2M words. Preserve >=16 quiet command clocks,
// timeout fencing, cache invalidation and the unchanged encrypted vendor IP.
// Accepted writes are buffered. write_idle is the completion barrier used by
// the board's frame publisher; CRC of the input stream is not SDRAM readback.
// req/wr/addr/wdata/wstrb must be held until ready accepts the transaction.
// Writes have one registered address-check cycle before their acceptance.
module sdram_app_adapter #(
    parameter [31:0] READ_TIMEOUT=32'd4096,
    parameter integer FAST_READ=0,
    parameter integer PREFETCH_READ=0,
    // MEM50/+8ns hardware trace26101701: data leads read-valid by one edge.
    // Default0 preserves the aligned interface used by other board profiles.
    parameter integer READ_DATA_LEADS_VALID=0
) (
    input wire clk,rst_n,req,wr,
    input wire [31:0] addr,wdata,input wire [3:0] wstrb,
    output wire [31:0] rdata,output reg rdata_valid,
    output wire ready,init_done,
    input wire Sdr_init_done,Sdr_init_ref_vld,Sdr_busy,
    output reg App_wr_en,output reg [20:0] App_wr_addr,
    output reg [3:0] App_wr_dm,output reg [31:0] App_wr_din,
    output reg App_rd_en,output reg [20:0] App_rd_addr,
    input wire Sdr_rd_en,input wire [31:0] Sdr_rd_dout,
    output wire write_idle,
    output reg protocol_fault
);
    wire [31:0] captured_read_data;
    generate if(READ_DATA_LEADS_VALID!=0)begin: g_read_alignment
      reg [31:0] previous_data;
      // Unconditional sampling retains the first word, which is present while
      // Sdr_rd_en is still LOW. Gating this register by valid would lose it.
      always @(posedge clk or negedge rst_n)
        if(!rst_n)previous_data<=0;else previous_data<=Sdr_rd_dout;
      assign captured_read_data=previous_data;
    end else begin: g_aligned_read
      assign captured_read_data=Sdr_rd_dout;
    end endgenerate
    localparam integer WB=16,RB=16;
    localparam [2:0] H_IDLE=0,H_WRITE=1,H_WGAP=2,H_READ=3,H_WAIT=4,H_RGAP=5;
    reg [2:0] state;

    reg [31:0] wbase,wnext;
    reg [4:0] wcnt,wi,physical_words;
    reg [1:0] write_lead;
    wire [5:0] write_span={1'b0,wcnt}+{4'b0,wbase[1:0]};
    reg [5:0] widle;
    reg w_checked,w_contiguous;
    reg [4:0] gap;

    reg[20:0] rfbase;reg[31:0] rexp;
    // Only the physical low21 bits and the next-prefetch range decision use
    // rfbase. Preserve ALL32-bit request semantics, including wrap atFFFFFFFF:
    // adding at most64 to its low21 bits produces at most one carry. The high
    // prefix becomes zero iff it was zero without carry, or all ones with carry.
    reg rfbase_high_zero,rfbase_high_ones;reg prefetch_in_range;
    // Physical read commands are four-word aligned. Retain only logical
    // words in the16-word bank; leading/trailing responses are never visible.
    // Clip at the2M-word physical end, avoiding speculative address wrap.
    function [4:0] read_size;input[31:0] base;begin
      read_size=(&base[20:4])?(5'd16-{1'b0,base[3:0]}):5'd16;
    end endfunction
    function [4:0] read_span_size;input[31:0] base;reg[5:0] span;begin
      span={1'b0,read_size(base)}+{4'b0,base[1:0]};
      read_span_size={span[4:2],2'b00}+(|span[1:0]?5'd4:5'd0);
    end endfunction
    reg[1:0] read_lead;reg[4:0] read_words,read_physical_words;
    reg [5:0] rcnt;
    reg [4:0] rhead,rcmd_i,rcv_i;
    reg fill_bank,next_fill_bank,contiguous_refill;
    reg[20:0] prefetch_addr;
    wire[21:0] prefetch_sum={1'b0,rfbase}+{15'd0,read_words};
    wire next_prefetch_in_range=prefetch_sum[21]?rfbase_high_ones:rfbase_high_zero;
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

    // Inferred9k SDP memories. Payload is not reset; existing cache/write
    // counters gate eligibility, and read_seen preserves the public reset value.
    // The synchronous read edge is the same edge as the previous register read.
    wire read_pop=rst_n&&!protocol_fault&&(FAST_READ?r_fast_fire:(r_go&&req&&!wr));
    wire read_fill=rst_n&&!protocol_fault&&(state==H_READ||state==H_WAIT)&&Sdr_rd_en&&(rcv_i>={3'b000,read_lead})&&(rcv_i<read_words+{3'b000,read_lead});
    wire[4:0] logical_rcv_index=rcv_i-{3'b000,read_lead};
    wire[4:0] fill_address=PREFETCH_READ?{fill_bank,logical_rcv_index[3:0]}:logical_rcv_index;
    // Read refill and accepted host write use disjoint controller states.
    // The two payload queues share one 36-bit SDP memory without changing
    // either queue's capacity, read edge, byte masks or public bus waveforms.
    // Read words occupy [0,2*RB); write words occupy [2*RB,2*RB+WB).
    wire preload_first=rst_n&&!protocol_fault&&idle_hw&&Sdr_init_done&&need_flush&&!w_accept;
    wire preload_next=rst_n&&!protocol_fault&&(state==H_WRITE);
    wire[3:0] write_read_address=preload_first?4'd0:((wi[3:0]+4'd1)-{2'b00,write_lead});
    localparam integer PAYLOAD_AW=$clog2(2*RB+WB);
    wire payload_we=read_fill||(rst_n&&!protocol_fault&&w_accept);
    wire payload_re=read_pop||preload_first||preload_next;
    wire[PAYLOAD_AW-1:0] payload_wa=read_fill?fill_address:(2*RB+wcnt[3:0]);
    wire[PAYLOAD_AW-1:0] payload_ra=read_pop?rhead:(2*RB+write_read_address);
    wire[35:0] payload_din=read_fill?{4'd0,captured_read_data}:{~wstrb,wdata};
    //synthesis force_ram
    reg[35:0] payload_mem[0:(1<<PAYLOAD_AW)-1]; //synthesis ram_style = bram_9k
    reg[35:0] payload_q;
    always @(posedge clk)begin
      if(payload_we)payload_mem[payload_wa]<=payload_din;
      if(payload_re)payload_q<=payload_mem[payload_ra];
    end
    // Preserve the old public rdata even when rdata_valid is low: switching
    // the RAM port to write preloads must not overwrite the last read word.
    reg read_seen,read_port_selected;
    reg[31:0] read_hold;
    always @(posedge clk or negedge rst_n)begin
      if(!rst_n)begin read_seen<=0;read_port_selected<=0;read_hold<=0;end
      else if(read_pop)begin read_seen<=1;read_port_selected<=1;end
      else if(preload_first||preload_next)begin
        if(read_port_selected)read_hold<=payload_q[31:0];
        read_port_selected<=0;
      end
    end
    wire[31:0] read_payload=read_port_selected?payload_q[31:0]:read_hold;
    wire[35:0] write_payload=payload_q;
    assign rdata=read_seen?read_payload:32'd0;
    // synthesis translate_off
    always @(posedge clk)begin
      if(read_fill&&w_accept)$fatal(1,"shared payload write-port overlap");
      if(read_pop&&(preload_first||preload_next))$fatal(1,"shared payload read-port overlap");
    end
    // synthesis translate_on
    // synthesis translate_off
    always @(posedge clk)if(read_pop&&read_fill&&rhead==fill_address)
      $fatal(1,"read-cache live-word collision");
    // synthesis translate_on

    always @(posedge clk or negedge rst_n)begin
      if(!rst_n)begin
        state<=H_IDLE;write_lead<=0;wbase<=0;wnext<=0;wcnt<=0;wi<=0;physical_words<=0;widle<=0;gap<=0;
        w_checked<=0;w_contiguous<=0;
        read_lead<=0;read_words<=0;read_physical_words<=0;rfbase<=0;rexp<=0;rcnt<=0;rhead<=0;rcmd_i<=0;rcv_i<=0;r_go<=0;r_sv<=0;
        fill_bank<=0;next_fill_bank<=0;contiguous_refill<=0;prefetch_addr<=0;read_quiet<=0;rfbase_high_zero<=1;rfbase_high_ones<=0;prefetch_in_range<=1;
        rdata_valid<=0;App_wr_en<=0;App_wr_addr<=0;App_wr_dm<=15;App_wr_din<=0;
        App_rd_en<=0;App_rd_addr<=0;
        read_wait<=0;protocol_fault<=0;
      end else if(protocol_fault)begin
        // A lost vendor response makes the transaction/slot epoch ambiguous.
        // Fence the client until common reset; never serve a partial cache.
        App_wr_en<=0;App_rd_en<=0;rdata_valid<=0;r_go<=0;r_sv<=0;
      end else begin
        App_wr_en<=0;App_rd_en<=0;rdata_valid<=0;
        // DQM (SDRAM write-mask) handling - board-verified behaviour.
        //
        //  (1) The vendor controller keeps piping App_wr_dm to the SDRAM DQM even
        //      while App_wr_en is LOW, and DQM also suppresses the READ output.
        //      Leaving the mask at 4'hf after a write burst therefore makes the
        //      next read return pull-up ones (0xFFFFFFFF) - the root cause the
        //      board showed as EXP=00000000 / GOT=FFFFFFFF on block 0
        //      (ported from the board team's fix, commit 7fb219c).
        //  (2) Releasing the mask on the very first idle cycle is NOT sufficient:
        //      the write enable is pipelined by the controller too, so the beat
        //      right after a burst is still issued - and with dm already 0 that
        //      flush word would be written into the neighbouring address (one
        //      corrupted word per burst = a garbled frame).
        //      So hold 4'hf for the first 6 quiet cycles, then release to 0.
        //      The write->read minimum gap is 16 cycles (H_WGAP) and the DQM
        //      pipeline is ~9 stages, so by the earliest possible read (cycle 17)
        //      dm has been 0 for 11 cycles - reads are not masked either.
        App_wr_dm <= (read_quiet>=5'd6) ? 4'h0 : App_wr_dm;
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
            rdata_valid<=1;rhead<=rhead+1'b1;
            rcnt<=rcnt-1'b1;rexp<=rexp+1'b1;
          end
        end else begin
          r_go<=Sdr_init_done&&r_serve&&!r_go;
          if(r_go&&req&&!wr)begin
            r_sv<=1;rhead<=rhead+1'b1;
            rcnt<=rcnt-1'b1;rexp<=rexp+1'b1;
          end else if(r_sv)begin rdata_valid<=1;r_sv<=0;end
        end

        if(w_accept)begin
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
              wi<=0;write_lead<=wbase[1:0];physical_words<={write_span[4:2],2'b00}+(|write_span[1:0]?5'd4:5'd0);state<=H_WRITE;
            end else if(Sdr_init_done&&req&&!wr&&!r_hit&&(wcnt==0)&&!r_sv&&!r_go)begin
              // No cache acceptance is possible in H_READ/H_WAIT.
              // Keep the old count until the complete replacement block is
              // received. Clearing here is redundant and puts addr==rexp
              // through a wide comparator into the counter's update cone.
              rfbase<=addr[20:0];rfbase_high_zero<=!(|addr[31:21]);rfbase_high_ones<=&addr[31:21];read_lead<=addr[1:0];read_words<=read_size(addr);read_physical_words<=read_span_size(addr);rcmd_i<=0;rcv_i<=0;state<=H_READ;
              fill_bank<=0;contiguous_refill<=0;
              if(PREFETCH_READ)rcnt<=0;
            end else if(PREFETCH_READ&&FAST_READ&&Sdr_init_done&&req&&!wr&&r_hit&&
                        wcnt==0&&rcnt<=RB&&prefetch_in_range)begin
              // Refill the FREE bank while the client drains completed words
              // in the other bank. This is read-only speculation; arbitrary
              // jumps replace the cache and every presented write invalidates
              // it. Never expose a partially received physical block.
              rfbase<=prefetch_addr;rfbase_high_zero<=1;rfbase_high_ones<=0;read_lead<=prefetch_addr[1:0];read_words<=read_size(prefetch_addr);read_physical_words<=read_span_size(prefetch_addr);fill_bank<=next_fill_bank;contiguous_refill<=1;
              rcmd_i<=0;rcv_i<=0;state<=H_READ;
            end
          end
          H_WRITE:begin
            App_wr_en<=1;App_wr_addr<={wbase[20:2],2'b00}+wi;
            if(wi>={3'b000,write_lead}&&wi<(wcnt+{3'b000,write_lead}))begin App_wr_din<=write_payload[31:0];App_wr_dm<=write_payload[35:32];end
            else begin App_wr_din<=0;App_wr_dm<=4'hf;end
            if(wi==physical_words-1'b1)begin
              wcnt<=0;widle<=0;gap<=16;state<=H_WGAP;
            end else wi<=wi+1'b1;
          end
          H_WGAP:begin
            if(gap==0)state<=H_IDLE;else gap<=gap-1'b1;
          end
          H_READ:begin
            App_rd_en<=1;App_rd_addr<={rfbase[20:2],2'b00}+rcmd_i;
            if(rcmd_i==read_physical_words-1'b1)state<=H_WAIT;else rcmd_i<=rcmd_i+1'b1;
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
          if(rcv_i==read_physical_words-1'b1)begin
            if(PREFETCH_READ&&contiguous_refill&&!(req&&wr))
              rcnt<=rcnt+read_words-(r_fast_fire?1'b1:1'b0);
            else begin
              rexp<=rfbase;rcnt<=read_words;
              rhead<=PREFETCH_READ?{fill_bank,4'b0}:5'd0;
            end
            prefetch_addr<=prefetch_sum[20:0];prefetch_in_range<=next_prefetch_in_range;next_fill_bank<=~fill_bank;
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
