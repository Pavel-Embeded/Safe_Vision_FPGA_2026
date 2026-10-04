// Parameterized from public TD 6.2.168116 IP templates; ASYNC/FWFT/NOREG, EG4 ERAM.
// Only names, selected compile options and parameter defaults are specialized.
// Pointer/flag/Gray/RAM behavior remains the vendor implementation.
`timescale 1ns/1ps
module a_pixel_fifo_ip 
#(
    parameter       DATA_WIDTH_W  = 32 , 
    parameter       DATA_WIDTH_R  = 16 ,  
    parameter       ADDR_WIDTH_W  = 10 ,  
    parameter       ADDR_WIDTH_R  = 11 ,
    parameter       AL_FULL_NUM   = 1000  ,
    parameter       AL_EMPTY_NUM  = 128 ,
    parameter       SHOW_AHEAD_EN = 1'b1,       //SHOWAHEAD mode enable
    parameter       OUTREG_EN     = "NOREG"     //OUTREG, NOREG
)              
(
    input                           rst,        //asynchronous port,active hight
    input                           clkw,       //write clock
    input                           clkr,       //read clock
    input                           we ,        //write enable,active hight
    input       [DATA_WIDTH_W-1:0]  di,         //write data
    input                           re ,        //read enable,active hight
    output      [DATA_WIDTH_R-1:0]  dout,       //read data
    output  reg                     valid,      //read data valid flag
    output  reg                     full_flag , //fifo full flag
    output  reg                     empty_flag, //fifo empty flag
    output  reg                     afull,      //fifo almost full flag
    output  reg                     aempty,     //fifo almost empty flag
    output      [ADDR_WIDTH_W-1:0]  wrusedw,    //stored data number in fifo
    output      [ADDR_WIDTH_R-1:0]  rdusedw,     //available data number for read 
    output                          wr_rst_done  // wrst over 
);

//--------------------------------------------------------------------------------------------
//-------------internal signals definition below---------------
//--------------------------------------------------------------------------------------------
    reg                             asy_w_rst0;
    reg                             asy_w_rst1;
    reg                             asy_r_rst0;
    reg                             asy_r_rst1;
    wire                            rd_rst;
    wire                            wr_rst;
    wire    [ADDR_WIDTH_R-1:0]      rd_to_wr_addr;  // read address synchronized to write clock domain
    wire    [ADDR_WIDTH_W-1:0]      wr_to_rd_addr;  // write address synchronized to read clock domain
    reg     [ADDR_WIDTH_W-1:0]      wr_addr;        // current write address   
    reg     [ADDR_WIDTH_W-1:0]      wr_addr_next1;   // next one write address 
    reg     [ADDR_WIDTH_W-1:0]      wr_addr_next2;   // next two write address      
    reg     [ADDR_WIDTH_R-1:0]      rd_addr;        // current write address
    wire    [ADDR_WIDTH_R-1:0]      rd_addr_mux ; 
    reg     [ADDR_WIDTH_R-1:0]      rd_addr_next1;  //  next one read address    
    wire                            wr_en_s;
    wire                            rd_en_s;
    reg     [ADDR_WIDTH_W-1:0]      shift_rdaddr;
    reg     [ADDR_WIDTH_R-1:0]      shift_wraddr;
    reg     [ADDR_WIDTH_W-1:0]      wr_addr_diff;   // the difference between read and write address(synchronized to write clock domain)
    reg     [ADDR_WIDTH_R-1:0]      rd_addr_diff;   // the difference between read and write address(synchronized to read clock domain) 
    reg                             empty_flag_r1;
    reg                             empty_flag_r2;
    reg                             re_r1;
    reg                             re_r2; 
//--------------------------------------------------------------------------------------------
//--------------------fuctional codes below---------------------------------
//--------------------------------------------------------------------------------------------

// =============================================
// reset control logic below;
// =============================================
    //Asynchronous reset synchronous release on the write side
    always @(posedge clkw,posedge rst)
    begin 
        if(rst)begin
            asy_w_rst0 <= 1'b1;
            asy_w_rst1 <= 1'b1;
        end else begin
            asy_w_rst0 <= 1'b0;
            asy_w_rst1 <= asy_w_rst0;
        end 
    end 

    //Asynchronous reset synchronous release on the read side
    always @(posedge clkr,posedge rst)
    begin
        if(rst)begin
            asy_r_rst0 <= 1'b1;
            asy_r_rst1 <= 1'b1;
        end else begin 
            asy_r_rst0 <= 1'b0;
            asy_r_rst1 <= asy_r_rst0;
        end 
    end 

    assign rd_rst = asy_r_rst1; 
    assign wr_rst = asy_w_rst1; 

    // reset over 
    assign wr_rst_done = ~wr_rst;

// =============================================
// address generate logic below;
// =============================================
    // write and read ram enable
    assign wr_en_s = !full_flag & we;
    assign rd_en_s = !empty_flag & re;


    // generate write fifo address
    always @(posedge clkw,posedge wr_rst) 
    begin
        if (wr_rst == 1'b1)
            wr_addr <= 'd0;
        else if(wr_en_s)
            wr_addr <= wr_addr + 1;
    end 

    // generate write fifo address
    always @(posedge clkw,posedge wr_rst) 
    begin
        if (wr_rst == 1'b1)
            wr_addr_next1 <= 'd1;
        else if(wr_en_s)
            wr_addr_next1 <= wr_addr_next1 + 1;
    end 

    // generate write fifo address
    always @(posedge clkw,posedge wr_rst) 
    begin
        if (wr_rst == 1'b1)
            wr_addr_next2 <= 'd2;
        else if(wr_en_s)
            wr_addr_next2 <= wr_addr_next2 + 1;
    end        

    // generate rd fifo address
    always @(posedge clkr,posedge rd_rst) 
    begin
        if (rd_rst == 1'b1)
            rd_addr <= 'd0;
        else if(rd_en_s)
            rd_addr <= rd_addr + 1;
    end

    always @(posedge clkr,posedge rd_rst) 
    begin
        if (rd_rst == 1'b1)
            rd_addr_next1 <= 'd1;
        else if(rd_en_s)
            rd_addr_next1 <= rd_addr_next1 + 1;
    end

    always @(*) 
    begin
        if(ADDR_WIDTH_R >= ADDR_WIDTH_W) begin
            shift_rdaddr = rd_to_wr_addr >> (ADDR_WIDTH_R - ADDR_WIDTH_W);
            shift_wraddr = wr_to_rd_addr  << (ADDR_WIDTH_R - ADDR_WIDTH_W);
        end else begin
            shift_rdaddr = rd_to_wr_addr << (ADDR_WIDTH_W - ADDR_WIDTH_R);
            shift_wraddr = wr_to_rd_addr >> (ADDR_WIDTH_W - ADDR_WIDTH_R);
        end
    end


    // two's complement format
    always @(posedge clkw,posedge wr_rst)
    begin
        if(wr_rst)
            wr_addr_diff <= {ADDR_WIDTH_W{1'b0}};
        else 
            wr_addr_diff <= wr_addr - shift_rdaddr; // the count of data writen to fifo
    end   


    always @(posedge clkr,posedge rd_rst)
    begin
        if(rd_rst)
            rd_addr_diff <= {ADDR_WIDTH_R{1'b0}};
        else 
            rd_addr_diff <= shift_wraddr - rd_addr;// the count of data writen to fifo
    end   


// =============================================
// generate all output flag and count below;
// ============================================= 
    // generate fifo full_flag indicator
    always@(posedge clkw,posedge wr_rst)begin
        if(wr_rst)
            full_flag<=1'b0;
        else begin 
            if(((shift_rdaddr == wr_addr_next2) && wr_en_s) || (shift_rdaddr == wr_addr_next1))      
                full_flag<=1'b1;
            else
                full_flag<=1'b0;
        end 
    end           

    // generate fifo afull indicator
    always@(posedge clkw,posedge wr_rst)begin
        if(wr_rst)
            afull<=1'b0;
        else begin 
            if(((wr_addr_diff == AL_FULL_NUM - 'd2) && wr_en_s) || (wr_addr_diff >= AL_FULL_NUM - 1'b1))
                afull<=1'b1;
            else
                afull<=1'b0;
        end 
    end           

    // generate fifo empty_flag indicator
    always@(posedge clkr,posedge rd_rst)begin
        if(rd_rst)
            empty_flag<=1'b1;
        else begin 
          if(((shift_wraddr == rd_addr_next1) && rd_en_s) || (shift_wraddr == rd_addr))
                empty_flag<=1'b1;
            else
                empty_flag<=1'b0;
        end 
    end 

    // generate fifo aempty indicator
    always@(posedge clkr,posedge rd_rst)begin
        if(rd_rst)
            aempty<=1'b1;
        else begin 
            if(((rd_addr_diff == (AL_EMPTY_NUM +'d1)) && rd_en_s) || (rd_addr_diff <= AL_EMPTY_NUM))
                aempty<=1'b1;
            else
                aempty<=1'b0;
        end 
    end 

    // the count of data writen to fifo 
    assign wrusedw = wr_addr_diff;

    // the count of data available for read
    assign rdusedw = rd_addr_diff;
 
    // delay empty_flag for 2cycle
    always @(posedge clkr,posedge rd_rst) 
    begin
        if (rd_rst == 1'b1) begin
            empty_flag_r1 <= 1'b1;
            empty_flag_r2 <= 1'b1;
        end else begin
            empty_flag_r1 <= empty_flag;
            empty_flag_r2 <= empty_flag_r1;
        end
    end
    // delay rd_en_s for 2cycle
    always @(posedge clkr,posedge rd_rst) 
    begin
        if (rd_rst == 1'b1) begin
            re_r1 <= 1'b0;
            re_r2 <= 1'b0;
        end else begin
            re_r1 <= rd_en_s;
            re_r2 <= re_r1;
        end
    end

    // generate data output valid flag
    always @(*)
    begin
        if(SHOW_AHEAD_EN && OUTREG_EN == "NOREG")
            valid = !empty_flag;
        else if(!SHOW_AHEAD_EN && OUTREG_EN == "OUTREG")
            valid = re_r2 & !empty_flag_r2;
        else
            valid = re_r1 & !empty_flag_r1;
    end

// =============================================
// instance logic below;
// =============================================
    // fifo read address synchronous to write clock domain using gray code
    a_pixel_fifo_gray_sync #(
        .ADDR_WIDTH          (ADDR_WIDTH_R)
    ) rd_to_wr_cross_inst (
        .primary_asreset_i   (rd_rst),
        .secondary_asreset_i (wr_rst),
        .primary_clk_i       (clkr),
        .secondary_clk_i     (clkw),
        .primary_addr_i      (rd_addr),
        .secondary_addr_o    (rd_to_wr_addr)
    );

    // fifo write address synchronous to read clock domain using gray code
    a_pixel_fifo_gray_sync #(
        .ADDR_WIDTH          (ADDR_WIDTH_W)
    ) wr_to_rd_cross_inst (
        .primary_asreset_i   (wr_rst),
        .secondary_asreset_i (rd_rst),
        .primary_clk_i       (clkw),
        .secondary_clk_i     (clkr),
        .primary_addr_i      (wr_addr),
        .secondary_addr_o    (wr_to_rd_addr)
    );

    generate if (SHOW_AHEAD_EN == 1'b1)begin 
        assign rd_addr_mux = rd_en_s ? rd_addr_next1 : rd_addr ;
    end else begin 
        assign rd_addr_mux = rd_addr ;
    end 
    endgenerate

    a_pixel_fifo_eram #(
        .DATAWIDTH_A        (DATA_WIDTH_W),
        .ADDRWIDTH_A        (ADDR_WIDTH_W), 
        .DATAWIDTH_B        (DATA_WIDTH_R),
        .ADDRWIDTH_B        (ADDR_WIDTH_R),
        .MODE               ("SDP"),
        .REGMODE_B          (OUTREG_EN)
    ) ram_inst (
        .clka               (clkw), 
        .rsta               (wr_rst), 
        .cea                (1'b1), 
        .wea                (wr_en_s), 
        .ocea               (1'b0),
        .dia                (di), 
        .addra              (wr_addr), 
        .clkb               (clkr), 
        .rstb               (rd_rst),
        .ceb                (SHOW_AHEAD_EN | rd_en_s),
        .web                (1'b0),  
        .oceb               (1'b1),  
        .addrb              (rd_addr_mux), 
        .dob                (dout)
    );

endmodule

// ===========================================================================
// $Version    : v1.0
// $Date       : 2022/04/26
// $Description: fifo write and read address crocess domain process
// ===========================================================================

module a_pixel_fifo_gray_sync #(
    parameter ADDR_WIDTH = 9
    )
    (
    input                                primary_asreset_i,
    input                                secondary_asreset_i,
    input                                primary_clk_i,
    input                                secondary_clk_i,
    input        [(ADDR_WIDTH-1):0]      primary_addr_i,
    output reg   [(ADDR_WIDTH-1):0]      secondary_addr_o
    );

//--------------------------------------------------------------------------------------------
//-------------internal parameter and signals definition below---------------
//--------------------------------------------------------------------------------------------
//-------------localparam definition

//-------------signals definition
    wire  [(ADDR_WIDTH-1):0]   primary_addr_gray;
    reg   [(ADDR_WIDTH-1):0]   primary_addr_gray_reg; //synthesis keep = true
    reg   [(ADDR_WIDTH-1):0]   sync_r1;               //synthesis keep = true
    reg   [(ADDR_WIDTH-1):0]   primary_addr_gray_sync;
//--------------------------------------------------------------------------------------------
//--------------------fuctional codes below---------------------------------
//-------------------------------------------------------------------------------------------- 
   
    function [ADDR_WIDTH-1:0] gray2bin;
        input [ADDR_WIDTH-1:0]           gray;
        integer                          j;
    begin
        gray2bin[ADDR_WIDTH-1]           = gray[ADDR_WIDTH-1];
        for (j = ADDR_WIDTH-1; j > 0; j  = j -1)
            gray2bin[j-1]                = gray2bin[j] ^ gray[j-1];
    end
    endfunction


    function [ADDR_WIDTH-1:0] bin2gray;
        input [ADDR_WIDTH-1:0]           bin;
        integer                          j;
    begin
        bin2gray[ADDR_WIDTH-1]           = bin[ADDR_WIDTH-1];
        for (j = ADDR_WIDTH-1; j > 0; j  = j - 1)
            bin2gray[j-1]                = bin[j] ^ bin[j-1];
    end
    endfunction

    // convert primary address to grey code
    assign primary_addr_gray            = bin2gray(primary_addr_i);

    // register the primary Address Pointer gray code
    always @(posedge primary_clk_i,posedge primary_asreset_i)
    begin
        if (primary_asreset_i == 1'b1)
            primary_addr_gray_reg       <= 'd0;
        else
            primary_addr_gray_reg       <= primary_addr_gray;
    end

    //--------------------------------------------------------------------
    // secondary clock Domain
    //--------------------------------------------------------------------
    // synchronize primary address grey code onto the secondary clock
    always @(posedge secondary_clk_i,posedge secondary_asreset_i)
    begin
        if (secondary_asreset_i == 1'b1) begin
            sync_r1       <= 'd0;
            primary_addr_gray_sync <= 'd0;
        end else begin
            sync_r1 <= primary_addr_gray_reg;
            primary_addr_gray_sync <= sync_r1;
        end
    end

    // convert the synchronized primary address grey code back to binary
    always @(posedge secondary_clk_i,posedge secondary_asreset_i)
    begin
        if (secondary_asreset_i == 1'b1) 
            secondary_addr_o       <= 'd0;
        else
            secondary_addr_o       <= gray2bin(primary_addr_gray_sync);
    end

endmodule

//////////////////////////////////////////////////////////////////////////////
// $Version    : v1.0
// $Date       : 2022/04/26
// $Description: DRAM/ERAM infer logic 
/////////////////////////////////////////////////////////////////////////////

