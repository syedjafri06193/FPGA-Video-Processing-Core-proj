// DVI transmitter: three TMDS encoders and four serializers.
//
// Channel assignment (design.md section 9.2) -- getting this wrong is one of
// the black-screen causes in section 12.1:
//
//   ch0  Blue   ctrl = {vsync, hsync}    <-- sync lives here and nowhere else
//   ch1  Green  ctrl = 2'b00
//   ch2  Red    ctrl = 2'b00
//   clk  constant 10'b0000011111
//
// The clock channel goes through an identical serializer rather than being
// routed from the MMCM to an OBUFDS directly, because that is the only way its
// phase relationship to the data channels is guaranteed.
//
// This is DVI signalling: no data islands, no audio, no InfoFrames.  Every
// display that accepts HDMI accepts it, and it is dramatically simpler.

`default_nettype none

`include "video_modes.vh"

module dvi_tx (
    input  wire        clk_pix,
    input  wire        clk_5x,
    input  wire        rst,
    input  wire [23:0] px,      // {R, G, B}
    input  wire        de,
    input  wire        hs,
    input  wire        vs,
    output wire [2:0]  tmds_p,
    output wire [2:0]  tmds_n,
    output wire        tmds_clk_p,
    output wire        tmds_clk_n
);
    wire [9:0] ch0, ch1, ch2;

    // Blue carries the sync signals in its control word.
    tmds_encoder u_blue (
        .clk (clk_pix), .rst (rst),
        .din (px[7:0]), .ctrl ({vs, hs}), .de (de), .dout (ch0)
    );

    tmds_encoder u_green (
        .clk (clk_pix), .rst (rst),
        .din (px[15:8]), .ctrl (2'b00), .de (de), .dout (ch1)
    );

    tmds_encoder u_red (
        .clk (clk_pix), .rst (rst),
        .din (px[23:16]), .ctrl (2'b00), .de (de), .dout (ch2)
    );

    serializer_10to1 u_ser0 (
        .clk_pix (clk_pix), .clk_5x (clk_5x), .rst (rst),
        .data (ch0), .out_p (tmds_p[0]), .out_n (tmds_n[0])
    );

    serializer_10to1 u_ser1 (
        .clk_pix (clk_pix), .clk_5x (clk_5x), .rst (rst),
        .data (ch1), .out_p (tmds_p[1]), .out_n (tmds_n[1])
    );

    serializer_10to1 u_ser2 (
        .clk_pix (clk_pix), .clk_5x (clk_5x), .rst (rst),
        .data (ch2), .out_p (tmds_p[2]), .out_n (tmds_n[2])
    );

    serializer_10to1 u_serclk (
        .clk_pix (clk_pix), .clk_5x (clk_5x), .rst (rst),
        .data (`TMDS_CLK_WORD), .out_p (tmds_clk_p), .out_n (tmds_clk_n)
    );
endmodule

`default_nettype wire
