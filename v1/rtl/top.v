// Top level (design.md sections 3.1, 8).
//
// One 100 MHz oscillator in, one DVI/HDMI stream out, with the whole pipeline
// runtime-controllable from the switches or the UART.
//
// Port names here must match the XDC exactly, character for character.  A
// mismatch is silently ignored by the tools and produces an unconnected pin,
// which is the first item in the M0 "common failures" list.
//
// Default mode is 720p60.  1080p30 is the same pixel clock with different
// timing constants (MODE_1080P30), and 640x480p60 needs the other MMCM
// settings as well -- see the parameters below and section 4.

`default_nettype none

`include "video_modes.vh"

module top #(
    // 0 = 640x480p60, 1 = 1280x720p60, 2 = 1920x1080p30
    parameter MODE = 1,
    // Bank initialisation files.  Empty means "black LUT", which is obviously
    // wrong on screen rather than subtly wrong -- scripts/build.tcl passes the
    // real paths, and an unset LUT with mode=1 is meant to look broken.
    parameter LUT0 = "", parameter LUT1 = "",
    parameter LUT2 = "", parameter LUT3 = "",
    parameter LUT4 = "", parameter LUT5 = "",
    parameter LUT6 = "", parameter LUT7 = ""
)(
    input  wire        clk_100mhz,
    input  wire [15:0] sw,
    input  wire [3:0]  btn,
    input  wire        uart_rxd,        // from the host
    output wire [15:0] led,
    output wire [7:0]  seg,
    output wire [7:0]  an,
    output wire [2:0]  tmds_d_p,
    output wire [2:0]  tmds_d_n,
    output wire        tmds_clk_p,
    output wire        tmds_clk_n
);
    // ---- mode constants ---------------------------------------------------
    localparam H_ACT   = (MODE == 0) ? `VGA_H_ACT   : (MODE == 2) ? `HD1080_H_ACT   : `HD720_H_ACT;
    localparam H_FP    = (MODE == 0) ? `VGA_H_FP    : (MODE == 2) ? `HD1080_H_FP    : `HD720_H_FP;
    localparam H_SYNC  = (MODE == 0) ? `VGA_H_SYNC  : (MODE == 2) ? `HD1080_H_SYNC  : `HD720_H_SYNC;
    localparam H_BP    = (MODE == 0) ? `VGA_H_BP    : (MODE == 2) ? `HD1080_H_BP    : `HD720_H_BP;
    localparam V_ACT   = (MODE == 0) ? `VGA_V_ACT   : (MODE == 2) ? `HD1080_V_ACT   : `HD720_V_ACT;
    localparam V_FP    = (MODE == 0) ? `VGA_V_FP    : (MODE == 2) ? `HD1080_V_FP    : `HD720_V_FP;
    localparam V_SYNC  = (MODE == 0) ? `VGA_V_SYNC  : (MODE == 2) ? `HD1080_V_SYNC  : `HD720_V_SYNC;
    localparam V_BP    = (MODE == 0) ? `VGA_V_BP    : (MODE == 2) ? `HD1080_V_BP    : `HD720_V_BP;
    localparam H_POL   = (MODE == 0) ? `VGA_H_POL   : `HD720_H_POL;
    localparam V_POL   = (MODE == 0) ? `VGA_V_POL   : `HD720_V_POL;
    localparam H_TOTAL = H_ACT + H_FP + H_SYNC + H_BP;
    localparam MAX_LINE = 2200;
    localparam PIX_HZ  = (MODE == 0) ? 25_000_000 : 74_250_000;

    // MMCM: D=1, M=10, /8 and /40 for VGA; D=5, M=37.125, /2 and /10 otherwise.
    localparam integer DIVCLK   = (MODE == 0) ? 1 : 5;
    localparam real    MULT     = (MODE == 0) ? 10.000 : 37.125;
    localparam real    DIV5X    = (MODE == 0) ? 8.000 : 2.000;
    localparam integer DIVPIX   = (MODE == 0) ? 40 : 10;

    // ---- clocking ---------------------------------------------------------
    wire clk_pix, clk_5x, locked, rst_pix, rst_5x;

    clk_gen #(
        .CLKIN_PERIOD (10.000),
        .DIVCLK       (DIVCLK),
        .MULT         (MULT),
        .CLKOUT0_DIV  (DIV5X),
        .CLKOUT1_DIV  (DIVPIX)
    ) u_clk (
        .clk_in  (clk_100mhz),
        .rst_in  (1'b0),
        .clk_pix (clk_pix),
        .clk_5x  (clk_5x),
        .locked  (locked),
        .rst_pix (rst_pix),
        .rst_5x  (rst_5x)
    );

    // ---- video timing -----------------------------------------------------
    wire [11:0] x, y;
    wire        de, hs, vs, frame_tick;

    video_timing #(
        .H_ACT (H_ACT), .H_FP (H_FP), .H_SYNC (H_SYNC), .H_BP (H_BP),
        .V_ACT (V_ACT), .V_FP (V_FP), .V_SYNC (V_SYNC), .V_BP (V_BP),
        .H_POL (H_POL), .V_POL (V_POL)
    ) u_timing (
        .clk (clk_pix), .rst (rst_pix),
        .x (x), .y (y), .de (de), .hs (hs), .vs (vs), .frame_tick (frame_tick)
    );

    // ---- control ----------------------------------------------------------
    wire [7:0] uart_data;
    wire       uart_valid, uart_frame_error;

    uart_rx #(.CLK_HZ (PIX_HZ), .BAUD (115200)) u_uart (
        .clk (clk_pix), .rst (rst_pix), .rx (uart_rxd),
        .data (uart_data), .valid (uart_valid), .frame_error (uart_frame_error)
    );

    wire [1:0] mode;
    wire [7:0] threshold;
    wire       lut_bypass, glow, freeze;
    wire [2:0] pattern_sel, lut_select;
    wire       uart_control;

    ctrl_regs u_ctrl (
        .clk (clk_pix), .rst (rst_pix),
        .sw (sw), .btn (btn),
        .uart_data (uart_data), .uart_valid (uart_valid),
        .mode (mode), .threshold (threshold),
        .lut_bypass (lut_bypass), .glow (glow), .freeze (freeze),
        .pattern_sel (pattern_sel), .lut_select (lut_select),
        .uart_control (uart_control)
    );

    // ---- source -----------------------------------------------------------
    wire [23:0] src_px;
    pattern_gen #(.H_ACT (H_ACT), .V_ACT (V_ACT)) u_pattern (
        .clk (clk_pix), .x (x), .y (y), .frame_tick (frame_tick),
        .freeze (freeze), .pattern_sel (pattern_sel), .rgb (src_px)
    );

    // pattern_gen registers its output, so the sync signals and coordinates
    // that produced a pixel are one cycle ahead of it.
    localparam SRC_LAT = 1;
    wire [2:0]  sync_src;
    wire [11:0] x_src, y_src;
    delay_line #(.WIDTH(3),  .DEPTH(SRC_LAT)) u_dsync (.clk(clk_pix), .din({de, hs, vs}), .dout(sync_src));
    delay_line #(.WIDTH(12), .DEPTH(SRC_LAT)) u_dxs   (.clk(clk_pix), .din(x), .dout(x_src));
    delay_line #(.WIDTH(12), .DEPTH(SRC_LAT)) u_dys   (.clk(clk_pix), .din(y), .dout(y_src));

    // ---- processing --------------------------------------------------------
    wire [23:0] px_proc;
    wire        de_proc, hs_proc, vs_proc;

    video_pipeline #(
        .H_ACT (H_ACT), .V_ACT (V_ACT), .H_TOTAL (H_TOTAL), .MAX_LINE (MAX_LINE),
        .LUT0 (LUT0), .LUT1 (LUT1), .LUT2 (LUT2), .LUT3 (LUT3),
        .LUT4 (LUT4), .LUT5 (LUT5), .LUT6 (LUT6), .LUT7 (LUT7)
    ) u_pipe (
        .clk (clk_pix), .rst (rst_pix),
        .px_in (src_px), .de_in (sync_src[2]), .hs_in (sync_src[1]), .vs_in (sync_src[0]),
        .x_in (x_src), .y_in (y_src),
        .mode (mode), .threshold (threshold),
        .lut_bypass (lut_bypass), .glow (glow),
        .px_out (px_proc), .de_out (de_proc), .hs_out (hs_proc), .vs_out (vs_proc)
    );

    // ---- output ------------------------------------------------------------
    dvi_tx u_dvi (
        .clk_pix (clk_pix), .clk_5x (clk_5x), .rst (rst_pix),
        .px (px_proc), .de (de_proc), .hs (hs_proc), .vs (vs_proc),
        .tmds_p (tmds_d_p), .tmds_n (tmds_d_n),
        .tmds_clk_p (tmds_clk_p), .tmds_clk_n (tmds_clk_n)
    );

    // ---- status ------------------------------------------------------------
    // Frame counter and measured pixel clock, because the two questions you
    // always want answered first are "is it locked" and "is the clock right".
    reg [31:0] frames = 32'd0;
    always @(posedge clk_pix)
        if (rst_pix) frames <= 32'd0;
        else if (frame_tick) frames <= frames + 32'd1;

    wire [31:0] pix_hz;
    freq_counter #(.REF_HZ (100_000_000)) u_freq (
        .clk_ref (clk_100mhz), .rst_ref (1'b0),
        .clk_meas (clk_pix), .hz (pix_hz)
    );

    // btn[1] swaps the display between the frame counter and the measured
    // pixel clock in Hz.
    wire [31:0] display_value = btn[1] ? pix_hz : frames;

    seven_seg #(.CLK_HZ (PIX_HZ)) u_seg (
        .clk (clk_pix), .rst (rst_pix),
        .value (display_value), .dp (8'h00), .seg (seg), .an (an)
    );

    assign led[0]     = locked;
    assign led[1]     = de_proc;
    assign led[2]     = vs_proc;
    assign led[3]     = uart_control;
    assign led[4]     = uart_frame_error;
    assign led[6:5]   = mode;
    assign led[7]     = lut_bypass;
    assign led[10:8]  = pattern_sel;
    assign led[15:11] = frames[4:0];
endmodule

`default_nettype wire
