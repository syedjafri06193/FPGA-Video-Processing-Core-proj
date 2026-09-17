// One linear interpolation stage: y = a + ((b - a) * f) >>> 4, f in 0..15.
//
// **The signed shift matters.**  The reference RTL in the design document
// computes the product into a signed value and then slices `p[12:4]` out of
// it, adding the slice as an *unsigned* number:
//
//     wire signed [12:0] p = d * $signed({1'b0, f});
//     y <= a + p[12:4];                      // <-- bug
//
// For any interpolation that runs downhill (b < a) the product is negative, so
// that slice is a large positive number and the output is wildly wrong -- on
// roughly half of all pixels, for any non-identity LUT.  It has to be an
// arithmetic shift of a signed value added to a signed accumulator:
//
//     y <= a + (p >>> 4);
//
// Truncation (rather than rounding) is deliberate: the Python golden model
// does the same thing, and matching it exactly is what makes a full-frame
// comparison meaningful (design.md section 10.1).
//
// Range: the result always lands within [min(a,b), max(a,b)], so no clamp is
// needed -- tb_lut3d proves that exhaustively over all 256x256x16 cases.

`default_nettype none

module lerp8 (
    input  wire       clk,
    input  wire [7:0] a,
    input  wire [7:0] b,
    input  wire [3:0] f,       // 0..15, interpreted as f/16
    output reg  [7:0] y
);
    wire signed [9:0]  d = $signed({2'b00, b}) - $signed({2'b00, a});
    wire signed [13:0] p = d * $signed({1'b0, f});
    wire signed [9:0]  delta = p[13:4];   // arithmetic: p >>> 4, floored

    always @(posedge clk)
        y <= $signed({2'b00, a}) + delta;
endmodule

// Three lerps in parallel: one RGB pixel interpolated by a single fraction.
module lerp_rgb (
    input  wire        clk,
    input  wire [23:0] a,
    input  wire [23:0] b,
    input  wire [3:0]  f,
    output wire [23:0] y
);
    lerp8 u_r (.clk(clk), .a(a[23:16]), .b(b[23:16]), .f(f), .y(y[23:16]));
    lerp8 u_g (.clk(clk), .a(a[15:8]),  .b(b[15:8]),  .f(f), .y(y[15:8]));
    lerp8 u_b (.clk(clk), .a(a[7:0]),   .b(b[7:0]),   .f(f), .y(y[7:0]));
endmodule

`default_nettype wire
