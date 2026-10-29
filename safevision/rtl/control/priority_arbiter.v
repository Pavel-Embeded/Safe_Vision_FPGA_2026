


module priority_arbiter (
    input  wire       fire,
    input  wire       mediaf,
    input  wire       notice,
    output reg  [1:0] evt_code,
    output reg        valid
);
    localparam [1:0] EV_NONE       = 2'd0;
    localparam [1:0] EV_NOTICE     = 2'd1;
    localparam [1:0] EV_MEDIAFAULT = 2'd2;
    localparam [1:0] EV_FIRE       = 2'd3;

    always @* begin
        if (fire)        begin evt_code = EV_FIRE;       valid = 1'b1; end
        else if (mediaf) begin evt_code = EV_MEDIAFAULT; valid = 1'b1; end
        else if (notice) begin evt_code = EV_NOTICE;     valid = 1'b1; end
        else             begin evt_code = EV_NONE;       valid = 1'b0; end
    end

endmodule
