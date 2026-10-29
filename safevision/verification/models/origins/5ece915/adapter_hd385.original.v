


module sdram_app_adapter #(
    parameter [31:0] READ_TIMEOUT=32'd4096,
    parameter integer FAST_READ=0,
    parameter integer PREFETCH_READ=0,


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


      always @(posedge clk or negedge rst_n)
        if(!rst_n)previous_data<=0;else previous_data<=Sdr_rd_dout;
      assign captured_read_data=previous_data;
    end else begin: g_aligned_read
      assign captured_read_data=Sdr_rd_dout;
    end endgenerate
    localparam integer WB=16,RB=64;
    localparam [2:0] H_IDLE=0,H_WRITE=1,H_WGAP=2,H_READ=3,H_WAIT=4,H_RGAP=5;
    reg [2:0] state;

    reg [31:0] wbase,wnext;
    reg [4:0] wcnt,wi,physical_words;
    reg [1:0] write_lead;
    wire [5:0] write_span={1'b0,wcnt}+{4'b0,wbase[1:0]};
    reg [5:0] widle;
    reg w_checked,w_contiguous;
    reg [4:0] gap;

    reg [31:0] rfbase,rexp;


    function [6:0] read_size;input[31:0] base;begin
      read_size=(&base[20:6])?(7'd64-{1'b0,base[5:0]}):7'd64;
    end endfunction
    function [6:0] read_span_size;input[31:0] base;reg[7:0] span;begin
      span={1'b0,read_size(base)}+{6'b0,base[1:0]};
      read_span_size={span[6:2],2'b00}+(|span[1:0]?7'd4:7'd0);
    end endfunction
    reg[1:0] read_lead;reg[6:0] read_words,read_physical_words;
    reg [7:0] rcnt;
    reg [6:0] rhead,rcmd_i,rcv_i;
    reg fill_bank,next_fill_bank,contiguous_refill;
    reg [31:0] prefetch_addr;
    reg [4:0] read_quiet;
    reg r_go,r_sv;
    reg [31:0] read_wait;
    wire idle_hw=(state==H_IDLE);
    wire w_can=Sdr_init_done&&idle_hw&&(wcnt<WB)&&w_checked&&w_contiguous&&!r_go&&!r_sv;
    wire w_accept=req&&wr&&w_can;


    wire r_hit=(rcnt!=0)&&(addr[20:0]==rexp[20:0]);
    wire r_serve=req&&!wr&&idle_hw&&(wcnt==0)&&r_hit&&!r_sv;


    wire r_fast_can=(idle_hw||state==H_RGAP||
                    (PREFETCH_READ&&(state==H_READ||state==H_WAIT)))&&(wcnt==0)&&r_hit;
    wire r_fast_fire=req&&!wr&&r_fast_can&&Sdr_init_done;
    wire need_flush=(wcnt!=0)&&((wcnt==WB)||(widle>=48)||
                    (req&&(!wr||(w_checked&&!w_contiguous))));
    assign init_done=Sdr_init_done&&!protocol_fault;
    assign ready=rst_n&&Sdr_init_done&&!protocol_fault&&(wr?w_can:(FAST_READ?r_fast_can:r_go));
    assign write_idle=rst_n&&Sdr_init_done&&!protocol_fault&&idle_hw&&(wcnt==0)&&!App_wr_en;


    wire read_pop=rst_n&&!protocol_fault&&(FAST_READ?r_fast_fire:(r_go&&req&&!wr));
    wire read_fill=rst_n&&!protocol_fault&&(state==H_READ||state==H_WAIT)&&Sdr_rd_en&&(rcv_i>={5'b00000,read_lead})&&(rcv_i<read_words+{5'b00000,read_lead});
    wire[6:0] logical_rcv_index=rcv_i-{5'b00000,read_lead};
    wire[6:0] fill_address=PREFETCH_READ?{fill_bank,logical_rcv_index[5:0]}:logical_rcv_index;
    //synthesis force_ram
    reg[31:0] rbuf[0:2*RB-1]; //synthesis ram_style = bram_9k
    reg[31:0] read_payload;
    reg read_seen;
    always @(posedge clk)begin
      if(read_fill)rbuf[fill_address]<=captured_read_data;
      if(read_pop)read_payload<=rbuf[rhead];
    end
    always @(posedge clk or negedge rst_n)
      if(!rst_n)read_seen<=0;else if(read_pop)read_seen<=1;
    assign rdata=read_seen?read_payload:32'd0;


    wire preload_first=rst_n&&!protocol_fault&&idle_hw&&Sdr_init_done&&need_flush&&!w_accept;
    wire preload_next=rst_n&&!protocol_fault&&(state==H_WRITE);
    wire[3:0] write_read_address=preload_first?4'd0:((wi[3:0]+4'd1)-{2'b00,write_lead});


    (* ram_style="bram_9k" *) reg[35:0] wbuf[0:WB-1];
    reg[35:0] write_payload;
    always @(posedge clk)begin
      if(rst_n&&!protocol_fault&&w_accept)wbuf[wcnt[3:0]]<={~wstrb,wdata};
      if(preload_first||preload_next)write_payload<=wbuf[write_read_address];
    end
    // synthesis translate_off
    always @(posedge clk)if(read_pop&&read_fill&&rhead==fill_address)
      $fatal(1,"read-cache live-word collision");
    // synthesis translate_on

    always @(posedge clk or negedge rst_n)begin
      if(!rst_n)begin
        state<=H_IDLE;write_lead<=0;wbase<=0;wnext<=0;wcnt<=0;wi<=0;physical_words<=0;widle<=0;gap<=0;
        w_checked<=0;w_contiguous<=0;
        read_lead<=0;read_words<=0;read_physical_words<=0;rfbase<=0;rexp<=0;rcnt<=0;rhead<=0;rcmd_i<=0;rcv_i<=0;r_go<=0;r_sv<=0;
        fill_bank<=0;next_fill_bank<=0;contiguous_refill<=0;prefetch_addr<=0;read_quiet<=0;
        rdata_valid<=0;App_wr_en<=0;App_wr_addr<=0;App_wr_dm<=15;App_wr_din<=0;
        App_rd_en<=0;App_rd_addr<=0;
        read_wait<=0;protocol_fault<=0;
      end else if(protocol_fault)begin


        App_wr_en<=0;App_rd_en<=0;rdata_valid<=0;r_go<=0;r_sv<=0;
      end else begin
        App_wr_en<=0;App_rd_en<=0;rdata_valid<=0;


        App_wr_dm <= (read_quiet>=5'd6) ? 4'h0 : App_wr_dm;


        if(App_rd_en||App_wr_en)read_quiet<=0;
        else if(read_quiet<16)read_quiet<=read_quiet+1'b1;
        if(state==H_READ||state==H_WAIT)begin
          if(Sdr_rd_en)read_wait<=0;
          else if(read_wait>=READ_TIMEOUT)protocol_fault<=1;
          else read_wait<=read_wait+1'b1;
        end else read_wait<=0;


        if(!Sdr_init_done||!idle_hw||!req||!wr||w_accept)w_checked<=0;
        else if(!w_checked)begin
          w_checked<=1;w_contiguous<=(wcnt==0)||(addr[20:0]==wnext[20:0]);
        end

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


        if(req&&wr)begin
          rcnt<=0;r_go<=0;


          contiguous_refill<=0;
        end

        case(state)
          H_IDLE:begin
            if(Sdr_init_done&&need_flush&&!w_accept)begin
              wi<=0;write_lead<=wbase[1:0];physical_words<={write_span[4:2],2'b00}+(|write_span[1:0]?5'd4:5'd0);state<=H_WRITE;
            end else if(Sdr_init_done&&req&&!wr&&!r_hit&&(wcnt==0)&&!r_sv&&!r_go)begin


              rfbase<=addr;read_lead<=addr[1:0];read_words<=read_size(addr);read_physical_words<=read_span_size(addr);rcmd_i<=0;rcv_i<=0;state<=H_READ;
              fill_bank<=0;contiguous_refill<=0;
              if(PREFETCH_READ)rcnt<=0;
            end else if(PREFETCH_READ&&FAST_READ&&Sdr_init_done&&req&&!wr&&r_hit&&
                        wcnt==0&&rcnt<=RB&&prefetch_addr<32'h00200000)begin


              rfbase<=prefetch_addr;read_lead<=prefetch_addr[1:0];read_words<=read_size(prefetch_addr);read_physical_words<=read_span_size(prefetch_addr);fill_bank<=next_fill_bank;contiguous_refill<=1;
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


        if((state==H_READ||state==H_WAIT)&&Sdr_rd_en)begin
          if(rcv_i==read_physical_words-1'b1)begin
            if(PREFETCH_READ&&contiguous_refill&&!(req&&wr))
              rcnt<=rcnt+read_words-(r_fast_fire?1'b1:1'b0);
            else begin
              rexp<=rfbase;rcnt<=read_words;
              rhead<=PREFETCH_READ?{fill_bank,6'b0}:7'd0;
            end
            prefetch_addr<=rfbase+read_words;next_fill_bank<=~fill_bank;
            rcv_i<=0;
            gap<=PREFETCH_READ?(read_quiet>=16?5'd0:5'd16-read_quiet):5'd16;
            state<=H_RGAP;
          end else rcv_i<=rcv_i+1'b1;
        end
      end
    end


    // synthesis translate_off
    initial if(PREFETCH_READ&&!FAST_READ)$fatal(1,"read prefetch requires FAST_READ");
    // synthesis translate_on
endmodule
