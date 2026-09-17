// Parameterised W x D shift register (design.md section 9.4).
//
// Used everywhere to keep de/hs/vs/x/y aligned with pixel data that has been
// through a pipeline.  **Do not hand-count registers** -- every processing
// module exports its latency as a localparam, and the delays are derived from
// those, so adding a pipeline stage to Sobel six months from now updates the
// alignment automatically.
//
// A mismatch here is the cause of the two most common "picture appears but is
// wrong" symptoms: an image shifted horizontally by a few pixels (de not
// matched to the data) or vertically by a line or two (line-buffer latency not
// accounted for).

`default_nettype none

module delay_line #(
    parameter WIDTH = 1,
    parameter DEPTH = 1
)(
    input  wire             clk,
    input  wire [WIDTH-1:0] din,
    output wire [WIDTH-1:0] dout
);
    generate
        if (DEPTH == 0) begin : g_zero
            assign dout = din;
        end else begin : g_sr
            reg [WIDTH-1:0] sr [0:DEPTH-1];
            integer k;
            always @(posedge clk) begin
                sr[0] <= din;
                for (k = 1; k < DEPTH; k = k + 1)
                    sr[k] <= sr[k-1];
            end
            assign dout = sr[DEPTH-1];
        end
    endgenerate
endmodule

`default_nettype wire
