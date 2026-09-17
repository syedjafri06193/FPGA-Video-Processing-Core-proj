// 3x3 Sobel (design.md section 9.8).
//
//     Gx = [-1 0 +1]      Gy = [-1 -2 -1]
//          [-2 0 +2]           [ 0  0  0]
//          [-1 0 +1]           [+1 +2 +1]
//
// Every coefficient is a power of two, so this is shifts and adds -- no
// multipliers, no DSPs.
//
// |Gx| + |Gy| overestimates sqrt(Gx^2 + Gy^2) by up to 41%, which is visually
// irrelevant and saves a square root.  (alpha-max-beta-min, 0.96*max +
// 0.40*min, gets within 4% for two multiplies if you ever want it.)
//
// `border` forces the output to black on the one-pixel frame where the window
// hangs off the edge of the image.  The choice is arbitrary but it must match
// the Python model exactly, or every full-frame comparison fails on the border
// and you chase a phantom bug.

`default_nettype none

module sobel (
    input  wire       clk,
    input  wire       en,
    input  wire [7:0] p00, p01, p02,
    input  wire [7:0] p10, p11, p12,
    input  wire [7:0] p20, p21, p22,
    input  wire [7:0] threshold,
    input  wire       border,      // centre pixel is on the frame edge
    output reg  [7:0] mag,
    output reg        edge_flag
);
    localparam LATENCY = 2;

    wire signed [11:0] gx = $signed({4'b0, p02}) + ($signed({4'b0, p12}) <<< 1) + $signed({4'b0, p22})
                          - $signed({4'b0, p00}) - ($signed({4'b0, p10}) <<< 1) - $signed({4'b0, p20});

    wire signed [11:0] gy = $signed({4'b0, p20}) + ($signed({4'b0, p21}) <<< 1) + $signed({4'b0, p22})
                          - $signed({4'b0, p00}) - ($signed({4'b0, p01}) <<< 1) - $signed({4'b0, p02});

    reg [11:0] agx, agy;
    reg        border_d;

    always @(posedge clk) if (en) begin
        agx      <= gx[11] ? -gx : gx;
        agy      <= gy[11] ? -gy : gy;
        border_d <= border;
    end

    wire [12:0] total = {1'b0, agx} + {1'b0, agy};

    always @(posedge clk) if (en) begin
        if (border_d) begin
            mag       <= 8'd0;
            edge_flag <= 1'b0;
        end else begin
            mag       <= (total > 13'd255) ? 8'd255 : total[7:0];
            edge_flag <= (total > {5'b0, threshold});
        end
    end
endmodule

`default_nettype wire
