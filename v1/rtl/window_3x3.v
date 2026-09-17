// 3x3 window from three aligned rows (design.md section 9.7).
//
// Three 3-tap shift registers.  The window is centred on p11, which is one
// column behind the newest column entering -- so the centre pixel is one line
// and one column behind the pixel currently going into the line buffer, and
// **every parallel branch must be delayed by exactly that much**.  That offset
// is where the "image shifted by a few pixels" class of bug comes from
// (section 12.2), and video_pipeline derives it rather than hardcoding it.

`default_nettype none

module window_3x3 #(
    parameter W = 8
)(
    input  wire         clk,
    input  wire         en,
    input  wire [W-1:0] row0, row1, row2,
    output reg  [W-1:0] p00, p01, p02,
    output reg  [W-1:0] p10, p11, p12,
    output reg  [W-1:0] p20, p21, p22
);
    localparam LATENCY = 1;

    always @(posedge clk) if (en) begin
        // Newest column on the right, oldest on the left.
        p02 <= row0; p01 <= p02; p00 <= p01;
        p12 <= row1; p11 <= p12; p10 <= p11;
        p22 <= row2; p21 <= p22; p20 <= p21;
    end
endmodule

`default_nettype wire
