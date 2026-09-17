// Video timing generator (design.md section 9.1).
//
// Two counters and some comparators.  Everything downstream keys off `de`,
// and `x`/`y` are carried alongside the pixels so that border handling and
// line-buffer addressing do not have to re-derive them.
//
// Outputs are registered, so every signal leaves this module with exactly one
// cycle of latency -- including x and y, which matters because the pattern
// generator's output is then one more cycle behind them.

`default_nettype none

module video_timing #(
    parameter H_ACT  = 1280, parameter H_FP = 110,
    parameter H_SYNC = 40,   parameter H_BP = 220,
    parameter V_ACT  = 720,  parameter V_FP = 5,
    parameter V_SYNC = 5,    parameter V_BP = 20,
    parameter H_POL  = 1'b1, parameter V_POL = 1'b1   // 1 = positive sync
)(
    input  wire        clk,
    input  wire        rst,
    output reg  [11:0] x,          // valid when de is high
    output reg  [11:0] y,
    output reg         de,
    output reg         hs,
    output reg         vs,
    output reg         frame_tick  // one pulse per frame, at the start of vsync
);
    localparam H_TOTAL = H_ACT + H_FP + H_SYNC + H_BP;
    localparam V_TOTAL = V_ACT + V_FP + V_SYNC + V_BP;
    localparam H_SYNC_START = H_ACT + H_FP;
    localparam H_SYNC_END   = H_ACT + H_FP + H_SYNC;
    localparam V_SYNC_START = V_ACT + V_FP;
    localparam V_SYNC_END   = V_ACT + V_FP + V_SYNC;

    reg [11:0] hcnt = 0;
    reg [11:0] vcnt = 0;

    wire line_end  = (hcnt == H_TOTAL - 1);
    wire frame_end = line_end && (vcnt == V_TOTAL - 1);

    always @(posedge clk) begin
        if (rst) begin
            hcnt <= 12'd0;
            vcnt <= 12'd0;
        end else if (line_end) begin
            hcnt <= 12'd0;
            vcnt <= (vcnt == V_TOTAL - 1) ? 12'd0 : vcnt + 12'd1;
        end else begin
            hcnt <= hcnt + 12'd1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            de <= 1'b0;
            hs <= ~H_POL;
            vs <= ~V_POL;
            x  <= 12'd0;
            y  <= 12'd0;
            frame_tick <= 1'b0;
        end else begin
            de <= (hcnt < H_ACT) && (vcnt < V_ACT);
            x  <= hcnt;
            y  <= vcnt;
            hs <= ((hcnt >= H_SYNC_START) && (hcnt < H_SYNC_END)) ? H_POL : ~H_POL;
            vs <= ((vcnt >= V_SYNC_START) && (vcnt < V_SYNC_END)) ? V_POL : ~V_POL;
            // Pulse once per frame, for animation counters and the frame-rate
            // debug display.  Deliberately derived from the counters rather
            // than from vs, so it is one cycle wide regardless of polarity.
            frame_tick <= line_end && (vcnt == V_SYNC_START - 1);
        end
    end

`ifdef FORMAL_ASSERTS
    always @(posedge clk) begin
        if (!rst) begin
            if (hcnt >= H_TOTAL) $error("hcnt out of range");
            if (vcnt >= V_TOTAL) $error("vcnt out of range");
        end
    end
`endif
endmodule

`default_nettype wire
