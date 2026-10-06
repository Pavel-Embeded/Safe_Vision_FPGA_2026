// Pixel vblank -> stable base mailbox -> mem DMA -> official async pixel FIFO.
// Each new frame discards old prefetched pixels. Quiesce the external B read
// channel BEFORE resetting FIFO/DMA; shared arbiter and SDRAM are not reset.
module a_frame_fetch_bridge #(parameter integer FIFO_AW=10,BURST_WORDS=64)(
    input wire pixel_clk,pixel_rst_n,mem_clk,mem_rst_n,
    input wire frame_start,frame_enable,input wire [31:0] frame_base,
    output wire rd_req,output wire [31:0] rd_addr,output wire [15:0] rd_len,
    input wire rd_ack,rd_busy,input wire [31:0] rd_data,input wire rd_data_valid,
    input wire fifo_rd_en,output wire [15:0] fifo_data,output wire fifo_valid,fifo_empty,
    output wire fifo_almost_empty,output wire [FIFO_AW:0] fifo_rd_pixels,
    output wire stream_armed,output wire [15:0] fifo_mem_pixels,
    output reg [31:0] missed_frame_count,overflow_count,output wire [31:0] dma_bytes,
    output wire dma_active,dma_done,output wire [2:0] fetch_state
);
    localparam integer CAPACITY=2*((1<<FIFO_AW)-1);
    localparam integer LOW_WATER=CAPACITY/2;
    localparam [2:0] IDLE=0,QUIET=1,CLEAR=2,RELEASE=3,LAUNCH=4,RUN=5;
    reg [2:0] state;reg [3:0] phase_count;reg [1:0] quiet_count;
    reg [31:0] requested_base,mem_base;reg begin_pending;
    wire begin_ready,begin_valid,begin_accept;
    wire [31:0] begin_base;
    wire common_reset_n=pixel_rst_n&&mem_rst_n;
    wire pixel_local_reset_n,mem_local_reset_n;
    // Register the complete B response beat before the DMA landing RAM. The
    // external interface is non-backpressured; valid and all 32 data bits get
    // the SAME one-cycle delay. This removes arbiter response-count logic from
    // the RAM write enable path without changing a word or its ordering.
    reg [31:0] response_data;
    reg response_valid;
    always @(posedge mem_clk or negedge mem_local_reset_n)begin
        if(!mem_local_reset_n)begin response_data<=0;response_valid<=0;end
        else begin response_data<=rd_data;response_valid<=rd_data_valid;end
    end
    // Joining reset permissions only forms an ASYNC assertion source. Its
    // release must be synchronized again in EACH domain, never used as data CE.
    reset_sync fetch_pixel_reset(.clk(pixel_clk),.async_rst_n(common_reset_n),.rst_n(pixel_local_reset_n));
    reset_sync fetch_mem_reset(.clk(mem_clk),.async_rst_n(common_reset_n),.rst_n(mem_local_reset_n));
    always @(posedge pixel_clk or negedge pixel_local_reset_n)begin
        if(!pixel_local_reset_n)begin requested_base<=0;begin_pending<=0;missed_frame_count<=0;end
        else begin
            if(begin_pending&&begin_ready)begin_pending<=0;
            if(frame_start&&frame_enable)begin
                if(!begin_pending||begin_ready)begin requested_base<=frame_base;begin_pending<=1;end
                else if(missed_frame_count!=32'hffffffff)missed_frame_count<=missed_frame_count+1'b1;
            end
        end
    end
    video_cdc_mailbox #(.WIDTH(32)) frame_request(
      .src_clk(pixel_clk),.src_rst_n(pixel_local_reset_n),.src_data(requested_base),
      .src_valid(begin_pending),.src_ready(begin_ready),
      .dst_clk(mem_clk),.dst_rst_n(mem_local_reset_n),.dst_data(begin_base),
      .dst_valid(begin_valid),.dst_ready(state==IDLE||state==RUN));
    assign begin_accept=begin_valid&&(state==IDLE||state==RUN);
    always @(posedge mem_clk or negedge mem_local_reset_n)begin
        if(!mem_local_reset_n)begin state<=IDLE;phase_count<=0;quiet_count<=0;mem_base<=0;end
        else if(begin_accept)begin
            mem_base<=begin_base;state<=QUIET;quiet_count<=0;phase_count<=0;
        end else case(state)
            IDLE: ;
            QUIET:begin
                if(rd_busy||rd_ack||rd_data_valid||response_valid)quiet_count<=0;
                else if(quiet_count==2)begin state<=CLEAR;phase_count<=0;end
                else quiet_count<=quiet_count+1'b1;
            end
            CLEAR:if(phase_count==7)begin state<=RELEASE;phase_count<=0;end
                  else phase_count<=phase_count+1'b1;
            RELEASE:if(phase_count==3)begin state<=LAUNCH;phase_count<=0;end
                    else phase_count<=phase_count+1'b1;
            LAUNCH:state<=RUN;
            RUN: ;
            default:state<=IDLE;
        endcase
    end
    // mem_local_reset_n already asserts immediately if EITHER upstream domain
    // resets. Use its local release only; pixel release must not feed mem CEs.
    wire fifo_reset=!mem_local_reset_n || state==IDLE || state==CLEAR;
    wire dma_reset_n=mem_local_reset_n && state!=IDLE && state!=CLEAR;
    wire dma_req,dma_we;wire [15:0] dma_pixel;
    wire [31:0] packed_word;wire packed_valid,packer_ready,half_pending;
    wire fifo_ready,fifo_full,fifo_afull;wire [FIFO_AW-1:0] fifo_words;
    // Level is REGISTERED one mem_clk before use: cuts the wr_addr_diff ->
    // arbiter cur_addr/consec_cnt comb chain (mem->mem budget). Consumers
    // (video_read_dma V_CHECK watermark, arbiter video_fifo_level) are
    // heuristics with huge slack (FIFO 2*(2^AW-1), burst BURST_WORDS,
    // +4 guard), so one cycle of lag is inside the margin.
    wire [15:0] guarded_level_next=({{(15-FIFO_AW){1'b0}},fifo_words,1'b0})+
                               (half_pending?16'd1:16'd0)+16'd4;
    reg [15:0] guarded_level;
    always @(posedge mem_clk or negedge mem_local_reset_n)begin
        if(!mem_local_reset_n)guarded_level<=16'd0;
        else guarded_level<=guarded_level_next;
    end
    assign fifo_mem_pixels=guarded_level;
    assign fetch_state=state;
    assign rd_req=dma_req && state==RUN;
    video_read_dma #(.BURST_WORDS(BURST_WORDS),.PIX_DEPTH(CAPACITY),.LOW_WATER(LOW_WATER)) dma(
      .clk(mem_clk),.rst_n(dma_reset_n),.start(state==LAUNCH),.frame_base(mem_base),
      .pix_fifo_level(guarded_level),.rd_req(dma_req),.rd_addr(rd_addr),.rd_len(rd_len),
      .rd_ack(rd_ack),.rd_busy(rd_busy),.rd_data(response_data),.rd_data_valid(response_valid),
      .fifo_wr_data(dma_pixel),.fifo_wr_en(dma_we),.rd_bytes_cnt(dma_bytes),
      .active(dma_active),.done(dma_done));
    pixel_word_packer packer(.clk(mem_clk),.rst_n(mem_local_reset_n&&!fifo_reset),
      .pixel(dma_pixel),.valid(dma_we&&state==RUN),.ready(packer_ready),
      .word_data(packed_word),.word_valid(packed_valid),.word_ready(fifo_ready),.pending(half_pending));
    a_pixel_fifo #(.AW(FIFO_AW)) fifo(.rst(fifo_reset),.wr_clk(mem_clk),.rd_clk(pixel_clk),
      .wr_data(packed_word),.wr_en(packed_valid&&fifo_ready),.full(fifo_full),.almost_full(fifo_afull),
      .wr_words(fifo_words),.wr_ready(fifo_ready),.rd_en(fifo_rd_en),.rd_data(fifo_data),
      .rd_valid(fifo_valid),.empty(fifo_empty),.almost_empty(fifo_almost_empty),.rd_pixels(fifo_rd_pixels));
    video_level_sync arm_sync(.clk(pixel_clk),.rst_n(pixel_local_reset_n),.async_level(state==RUN),.level(stream_armed));
    always @(posedge mem_clk or negedge mem_local_reset_n)begin
        if(!mem_local_reset_n)overflow_count<=0;
        else if(dma_we&&state==RUN&&!packer_ready&&overflow_count!=32'hffffffff)
            overflow_count<=overflow_count+1'b1;
    end
    // synthesis translate_off
    initial if(FIFO_AW<6||FIFO_AW>14||BURST_WORDS<1||2*BURST_WORDS>CAPACITY-4)
        $fatal(1,"a_frame_fetch_bridge invalid FIFO/burst configuration");
    // synthesis translate_on
endmodule
