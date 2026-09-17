// Luma, as the golden model computes it (design.md section 9.8).
//
//     Y = (77*R + 150*G + 29*B) >> 8
//
// The weights are 0.299/0.587/0.114 scaled by 256 and rounded; they sum to
// exactly 256, so the result never exceeds 255 and no clamp is needed.  The
// shift truncates, and the Python model truncates the same way -- that is what
// makes the full-frame comparison exact rather than approximate.
//
// Three constant multiplies synthesise to shift-add trees, or to three DSP48s
// if Vivado prefers; either is fine at 74.25 MHz.

`default_nettype none

module rgb2luma (
    input  wire        clk,
    input  wire        en,
    input  wire [23:0] rgb,
    output reg  [7:0]  y
);
    localparam LATENCY = 1;

    wire [15:0] acc = rgb[23:16] * 16'd77
                    + rgb[15:8]  * 16'd150
                    + rgb[7:0]   * 16'd29;

    always @(posedge clk) if (en) y <= acc[15:8];
endmodule

`default_nettype wire
