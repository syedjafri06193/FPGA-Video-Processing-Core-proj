// Procedural video source (design.md section 9.5).
//
// There is no frame buffer and there cannot be one: a 1280x720x24 frame is
// 27.6 Mbit against 2.7 Mbit of BRAM on this part, and QSPI flash is roughly
// 4x too slow to stream from (223 MB/s needed, ~50 MB/s available).  So the
// content is generated on the fly, which is not a compromise -- it gives exact
// control over what the filters see.
//
// Patterns 1 and 2 (checkerboard, circle) are the ones worth pointing Sobel
// at: hard edges and curved edges.  Patterns 0 and 3 (ramps, XOR texture)
// cover the RGB cube, which is what exercises the LUT.
//
// Output is registered, so pixels are one cycle behind the x/y they were
// computed from -- top.v delays de/hs/vs to match.

`default_nettype none

module pattern_gen #(
    parameter H_ACT = 1280,
    parameter V_ACT = 720
)(
    input  wire        clk,
    input  wire [11:0] x,
    input  wire [11:0] y,
    input  wire        frame_tick,     // one pulse per frame
    input  wire        freeze,
    input  wire [2:0]  pattern_sel,
    output reg  [23:0] rgb
);
    localparam LATENCY = 1;
    localparam signed [12:0] CX = H_ACT / 2;
    localparam signed [12:0] CY = V_ACT / 2;

    reg [11:0] phase = 12'd0;
    always @(posedge clk)
        if (frame_tick && !freeze) phase <= phase + 12'd1;

    // Moving circle: the centre sweeps horizontally with the frame counter.
    wire signed [12:0] sweep = $signed({1'b0, phase[8:0]}) - 13'sd256;
    wire signed [12:0] cx    = CX + sweep;
    wire signed [12:0] dx    = $signed({1'b0, x}) - cx;
    wire signed [12:0] dy    = $signed({1'b0, y}) - CY;
    wire [25:0] r2 = dx * dx + dy * dy;
    wire in_circle = (r2 < 26'd10000);

    wire checkerboard = x[5] ^ y[5];
    wire [7:0] ramp_x = x[9:2];
    wire [7:0] ramp_y = y[9:2];
    wire [7:0] bars   = {3{x[9:7]}};

    always @(posedge clk) begin
        case (pattern_sel)
            3'd0: rgb <= {ramp_x, ramp_y, 8'h80};                    // gradient
            3'd1: rgb <= checkerboard ? 24'hFFFFFF : 24'h101010;          // checkerboard
            3'd2: rgb <= in_circle ? 24'hFF6020
                                   : {ramp_x, 8'h30, ramp_y};        // circle
            3'd3: rgb <= {x[7:0], y[7:0], x[7:0] ^ y[7:0]};          // xor texture
            3'd4: rgb <= {bars, bars, bars};                          // grey bars
            3'd5: rgb <= {{8{x[8]}}, {8{x[7]}}, {8{x[6]}}};          // colour bars
            3'd6: rgb <= (x[3:0] == 4'd0 || y[3:0] == 4'd0)
                          ? 24'hFFFFFF : 24'h000000;                  // grid
            default: rgb <= {ramp_y, ramp_x, ramp_x ^ ramp_y};
        endcase
    end
endmodule

`default_nettype wire
