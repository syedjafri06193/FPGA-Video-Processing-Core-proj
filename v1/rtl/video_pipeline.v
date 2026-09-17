// The video path: LUT branch and Sobel branch in parallel, rejoined at the
// blend (design.md section 3.1).
//
// ## Why the branches are parallel rather than chained
//
// Edge detection runs on luma derived from the **ungraded** image, because
// colour grading can crush the local contrast the gradient operator depends
// on.  The RGB pixel takes a delay-matched path through the LUT, and the two
// meet at the blend.
//
// ## Delay matching, which is the fiddly part
//
// The 3x3 window centres on a pixel one line and one column behind the pixel
// entering the line buffer, so the Sobel result for pixel P is only available
// once P's neighbour at (y+1, x+1) has arrived.  Everything in parallel has to
// wait exactly that long:
//
//     sync   : H_TOTAL + 7 cycles of shift register
//     graded : LUT (6) + one line delay (H_TOTAL + 1)
//     sobel  : luma (1) + line buffer (2) + window (1) + sobel (2), plus the
//              H_TOTAL + 1 the window offset itself represents
//
// All three are derived from the module latencies below rather than counted by
// hand, so adding a pipeline stage to any of them keeps the picture aligned
// (section 9.4).
//
// ## Free-running rather than de-gated
//
// The delays here run on every clock and the line delays are H_TOTAL long,
// rather than advancing only during active video with H_ACT-long buffers.
// That costs a little BRAM (H_TOTAL is 1650 against 1280 active) and buys
// something worth much more: every delay in the design is measured in plain
// clock cycles, so de/hs/vs can be matched with an ordinary shift register and
// the alignment is verifiable by arithmetic.  The de-gated version needs every
// delay to be gated identically, and one missed enable is an image shifted by
// a line that looks almost right.

`default_nettype none

`include "video_modes.vh"

module video_pipeline #(
    parameter H_ACT   = 1280,
    parameter V_ACT   = 720,
    parameter H_TOTAL = 1650,
    parameter MAX_LINE = 2200,
    parameter LUT0 = "", parameter LUT1 = "", parameter LUT2 = "", parameter LUT3 = "",
    parameter LUT4 = "", parameter LUT5 = "", parameter LUT6 = "", parameter LUT7 = ""
)(
    input  wire        clk,
    input  wire        rst,

    input  wire [23:0] px_in,
    input  wire        de_in,
    input  wire        hs_in,
    input  wire        vs_in,
    input  wire [11:0] x_in,
    input  wire [11:0] y_in,

    input  wire [1:0]  mode,
    input  wire [7:0]  threshold,
    input  wire        lut_bypass,
    input  wire        glow,

    output wire [23:0] px_out,
    output wire        de_out,
    output wire        hs_out,
    output wire        vs_out
);
    // ---- latencies, in clock cycles ---------------------------------------
    localparam LUMA_LAT   = 1;   // rgb2luma
    localparam LB_LAT     = 2;   // line_buffer alignment registers
    localparam WIN_LAT    = 1;   // window_3x3
    localparam SOBEL_LAT  = 2;   // sobel
    localparam LUT_LAT    = 6;   // lut3d
    localparam BLEND_LAT  = 1;   // blend

    // Cycles from a pixel entering to its 3x3 window being centred on it.
    localparam WINDOW_LAT = LUMA_LAT + LB_LAT + WIN_LAT;           // 4
    // The window centre trails the incoming pixel by one line and one column.
    localparam SPATIAL    = H_TOTAL + 1;
    // Total, excluding the blend stage (which every path shares).
    localparam PIPE_LAT   = SPATIAL + WINDOW_LAT + SOBEL_LAT;      // H_TOTAL+7

    // ---- Sobel branch ------------------------------------------------------
    wire [7:0] luma;
    rgb2luma u_luma (.clk (clk), .en (1'b1), .rgb (px_in), .y (luma));

    wire [7:0] row0, row1, row2;
    wire       rows_valid;

    line_buffer #(.WIDTH(8), .MAX_X(MAX_LINE)) u_lb (
        .clk (clk), .rst (rst), .de (1'b1), .line_len (H_TOTAL[11:0]),
        .din (luma), .row0 (row0), .row1 (row1), .row2 (row2), .valid (rows_valid)
    );

    wire [7:0] p00, p01, p02, p10, p11, p12, p20, p21, p22;
    window_3x3 #(.W(8)) u_win (
        .clk (clk), .en (1'b1),
        .row0 (row0), .row1 (row1), .row2 (row2),
        .p00 (p00), .p01 (p01), .p02 (p02),
        .p10 (p10), .p11 (p11), .p12 (p12),
        .p20 (p20), .p21 (p21), .p22 (p22)
    );

    // Border: the window centre is at (y_w - 1, x_w - 1) where (x_w, y_w) is
    // the coordinate delayed to the window stage.  x_w == 0 means the centre
    // sits in the blanking interval, which is border by definition.
    wire [11:0] x_w, y_w;
    delay_line #(.WIDTH(12), .DEPTH(WINDOW_LAT)) u_dx (.clk(clk), .din(x_in), .dout(x_w));
    delay_line #(.WIDTH(12), .DEPTH(WINDOW_LAT)) u_dy (.clk(clk), .din(y_in), .dout(y_w));

    wire border = (x_w == 12'd0) || (x_w == 12'd1) || (x_w == H_ACT[11:0])
               || (y_w == 12'd0) || (y_w == 12'd1) || (y_w == V_ACT[11:0]);

    wire [7:0] edge_mag;
    wire       edge_flag;

    sobel u_sobel (
        .clk (clk), .en (1'b1),
        .p00 (p00), .p01 (p01), .p02 (p02),
        .p10 (p10), .p11 (p11), .p12 (p12),
        .p20 (p20), .p21 (p21), .p22 (p22),
        .threshold (threshold), .border (border),
        .mag (edge_mag), .edge_flag (edge_flag)
    );

    // ---- LUT branch --------------------------------------------------------
    wire [23:0] graded;
    lut3d #(
        .LUT0(LUT0), .LUT1(LUT1), .LUT2(LUT2), .LUT3(LUT3),
        .LUT4(LUT4), .LUT5(LUT5), .LUT6(LUT6), .LUT7(LUT7)
    ) u_lut (
        .clk (clk), .px_in (px_in), .px_out (graded)
    );

    // Raw pixel, delayed to sit alongside the LUT output.
    wire [23:0] raw_lut_aligned;
    delay_line #(.WIDTH(24), .DEPTH(LUT_LAT)) u_draw (
        .clk (clk), .din (px_in), .dout (raw_lut_aligned)
    );

    wire [23:0] graded_sel = lut_bypass ? raw_lut_aligned : graded;

    // Both the graded and the raw pixel ride one line delay together, so the
    // 48-bit word costs a single BRAM-based delay instead of two.
    wire [47:0] delayed;
    line_delay #(.WIDTH(48), .MAX_X(MAX_LINE)) u_rgb_delay (
        .clk (clk), .rst (rst), .en (1'b1), .line_len (H_TOTAL[11:0]),
        .din ({graded_sel, raw_lut_aligned}), .dout (delayed)
    );

    wire [23:0] graded_aligned = delayed[47:24];
    wire [23:0] raw_aligned    = delayed[23:0];

    // ---- sync, delayed to match -------------------------------------------
    wire [2:0] sync_out;
    delay_line #(.WIDTH(3), .DEPTH(PIPE_LAT)) u_dsync (
        .clk (clk), .din ({de_in, hs_in, vs_in}), .dout (sync_out)
    );

    // ---- rejoin ------------------------------------------------------------
    wire [23:0] blended;
    blend u_blend (
        .clk (clk), .en (1'b1),
        .rgb_raw (raw_aligned), .rgb_graded (graded_aligned),
        .edge_mag (edge_mag), .edge_flag (edge_flag),
        .mode (mode), .glow (glow), .rgb_out (blended)
    );

    // The blend adds a cycle to the pixel; the sync signals take the same trip.
    wire [2:0] sync_final;
    delay_line #(.WIDTH(3), .DEPTH(BLEND_LAT)) u_dsync2 (
        .clk (clk), .din (sync_out), .dout (sync_final)
    );

    assign px_out = blended;
    assign de_out = sync_final[2];
    assign hs_out = sync_final[1];
    assign vs_out = sync_final[0];
endmodule

`default_nettype wire
