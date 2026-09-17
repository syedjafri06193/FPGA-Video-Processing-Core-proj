// Mode mux and edge overlay (design.md section 9.9).
//
//   0 passthrough   the ungraded pixel, for A/B against the LUT
//   1 lut           graded only
//   2 edges         Sobel magnitude as grey, white on black
//   3 overlay       graded, with edges punched in white
//
// Mode 2 first is deliberate in the build order: edges on their own are much
// easier to eyeball than a blend, so get them right before combining.
//
// `glow` selects a proportional overlay instead of the hard switch:
//
//     out = graded + (255 - graded) * mag / 256
//
// which makes edges glow rather than punch holes.  It is off by default
// because the hard version is what the Python model implements, and keeping
// the default bit-exact with the model is worth more than the nicer picture.

`default_nettype none

`include "video_modes.vh"

module blend (
    input  wire        clk,
    input  wire        en,
    input  wire [23:0] rgb_raw,
    input  wire [23:0] rgb_graded,
    input  wire [7:0]  edge_mag,
    input  wire        edge_flag,
    input  wire [1:0]  mode,
    input  wire        glow,
    output reg  [23:0] rgb_out
);
    localparam LATENCY = 1;

    function [7:0] lift(input [7:0] base, input [7:0] mag);
        reg [15:0] product;
        begin
            product = (8'd255 - base) * mag;      // 0 .. 65025
            lift    = base + product[15:8];       // base + (255-base)*mag/256
        end
    endfunction

    wire [23:0] glow_rgb = {lift(rgb_graded[23:16], edge_mag),
                            lift(rgb_graded[15:8],  edge_mag),
                            lift(rgb_graded[7:0],   edge_mag)};

    always @(posedge clk) if (en) begin
        case (mode)
            `MODE_PASS:  rgb_out <= rgb_raw;
            `MODE_LUT:   rgb_out <= rgb_graded;
            `MODE_EDGES: rgb_out <= {3{edge_mag}};
            default:     rgb_out <= glow ? glow_rgb
                                         : (edge_flag ? 24'hFFFFFF : rgb_graded);
        endcase
    end
endmodule

`default_nettype wire
