// Video timing constants -- CEA-861 / VESA (design.md section 4.3).
//
// Getting a single number wrong here produces a monitor that says "no signal"
// with no further clue, so these are checked against the arithmetic identity
// H_TOTAL * V_TOTAL * refresh == pixel clock, which tb_video_timing asserts.
//
//   640x480p60   800 x 525  x 60 = 25,200,000   (25.175 MHz nominal, 25.0 used)
//   1280x720p60 1650 x 750  x 60 = 74,250,000
//   1920x1080p30 2200 x 1125 x 30 = 74,250,000
//
// Note that 720p60 and 1080p30 share the 74.25 MHz pixel clock: identical
// clocking infrastructure, different constants.  That is the honest way to put
// "1080p" on this project (section 1).

`ifndef VIDEO_MODES_VH
`define VIDEO_MODES_VH

// ---------------------------------------------------------------- 640x480p60
`define VGA_H_ACT   640
`define VGA_H_FP     16
`define VGA_H_SYNC   96
`define VGA_H_BP     48
`define VGA_V_ACT   480
`define VGA_V_FP     10
`define VGA_V_SYNC    2
`define VGA_V_BP     33
`define VGA_H_POL   1'b0   // negative
`define VGA_V_POL   1'b0   // negative

// --------------------------------------------------------------- 1280x720p60
`define HD720_H_ACT  1280
`define HD720_H_FP    110
`define HD720_H_SYNC   40
`define HD720_H_BP    220
`define HD720_V_ACT   720
`define HD720_V_FP      5
`define HD720_V_SYNC    5
`define HD720_V_BP     20
`define HD720_H_POL  1'b1   // positive
`define HD720_V_POL  1'b1   // positive

// -------------------------------------------------------------- 1920x1080p30
`define HD1080_H_ACT  1920
`define HD1080_H_FP     88
`define HD1080_H_SYNC   44
`define HD1080_H_BP    148
`define HD1080_V_ACT  1080
`define HD1080_V_FP      4
`define HD1080_V_SYNC    5
`define HD1080_V_BP     36
`define HD1080_H_POL  1'b1
`define HD1080_V_POL  1'b1

// TMDS control tokens (DVI 1.0, section 3.2.2), emitted during blanking.
`define TMDS_CTRL_00 10'b1101010100
`define TMDS_CTRL_01 10'b0010101011
`define TMDS_CTRL_10 10'b0101010100
`define TMDS_CTRL_11 10'b1010101011

// The clock channel is a constant word: five zeros then five ones produces a
// square wave at the pixel rate, phase-aligned with the data channels because
// it goes through an identical serializer.
`define TMDS_CLK_WORD 10'b0000011111

// Processing modes (switch-selected at runtime, section 9.9).
`define MODE_PASS    2'd0
`define MODE_LUT     2'd1
`define MODE_EDGES   2'd2
`define MODE_OVERLAY 2'd3

`endif
