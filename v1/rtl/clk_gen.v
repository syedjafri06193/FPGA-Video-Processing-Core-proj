// MMCM wrapper: one 100 MHz oscillator in, two phase-related clocks out
// (design.md section 4).
//
// 720p60 and 1080p30 (74.25 MHz pixel, 371.25 MHz serial):
//
//     D = 5, M = 37.125  ->  PFD  = 100/5      = 20 MHz     (10-450 OK)
//                            VCO  = 100*37.125/5 = 742.5 MHz (600-1200 OK)
//     CLKOUT0 / 2   -> 371.25 MHz   clk_5x
//     CLKOUT1 / 10  ->  74.25 MHz   clk_pix
//
// 640x480p60 (25 MHz pixel, 125 MHz serial):
//
//     D = 1, M = 10      ->  VCO = 1000 MHz
//     CLKOUT0 / 8   -> 125 MHz, CLKOUT1 / 40 -> 25 MHz
//
// The 742.5 MHz VCO is internal to the MMCM and perfectly legal.  What must
// never happen is routing 742.5 MHz onto a BUFG -- that is the wall 1080p60
// hits on this part (section 2.2), and it is why this design tops out at a
// 371.25 MHz serial clock.
//
// Both clocks come from the **same MMCM** so they are phase-related.  Two
// separate MMCMs drift and the OSERDES output becomes garbage.
//
// Named clk_gen rather than clocking, because `clocking` is a SystemVerilog
// keyword and any tool in -sv mode rejects a module with that name.
//
// In Vivado, prefer the Clocking Wizard to this hand instantiation if you want
// the GUI to check your arithmetic; the parameters below are what it would
// generate, and keeping them in source makes them reviewable in git.

`default_nettype none

module clk_gen #(
    parameter real CLKIN_PERIOD   = 10.000,   // 100 MHz
    parameter integer DIVCLK      = 5,
    parameter real MULT           = 37.125,
    parameter real CLKOUT0_DIV    = 2.000,    // clk_5x
    parameter integer CLKOUT1_DIV = 10        // clk_pix
)(
    input  wire clk_in,        // 100 MHz board oscillator
    input  wire rst_in,        // active high, asynchronous
    output wire clk_pix,
    output wire clk_5x,
    output wire locked,
    output wire rst_pix,       // synchronous to clk_pix
    output wire rst_5x         // synchronous to clk_5x
);
    wire clk_fb;
    wire clk_5x_raw, clk_pix_raw;
    wire mmcm_locked;

    MMCME2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKIN1_PERIOD      (CLKIN_PERIOD),
        .DIVCLK_DIVIDE      (DIVCLK),
        .CLKFBOUT_MULT_F    (MULT),
        .CLKFBOUT_PHASE     (0.000),
        .CLKOUT0_DIVIDE_F   (CLKOUT0_DIV),
        .CLKOUT1_DIVIDE     (CLKOUT1_DIV),
        .CLKOUT0_DUTY_CYCLE (0.5),
        .CLKOUT1_DUTY_CYCLE (0.5),
        .CLKOUT0_PHASE      (0.000),
        .CLKOUT1_PHASE      (0.000),
        .REF_JITTER1        (0.010),
        .STARTUP_WAIT       ("FALSE")
    ) u_mmcm (
        .CLKOUT0  (clk_5x_raw),  .CLKOUT0B (),
        .CLKOUT1  (clk_pix_raw), .CLKOUT1B (),
        .CLKOUT2  (), .CLKOUT2B (), .CLKOUT3 (), .CLKOUT3B (),
        .CLKOUT4  (), .CLKOUT5 (), .CLKOUT6 (),
        .CLKFBOUT (clk_fb), .CLKFBOUTB (),
        .LOCKED   (mmcm_locked),
        .CLKIN1   (clk_in),
        .CLKFBIN  (clk_fb),
        .PWRDWN   (1'b0),
        .RST      (rst_in)
    );

    BUFG u_bufg_pix (.I (clk_pix_raw), .O (clk_pix));
    BUFG u_bufg_5x  (.I (clk_5x_raw),  .O (clk_5x));

    assign locked = mmcm_locked;

    // Hold everything in reset until the MMCM locks.  Wire `locked` to an LED:
    // it is the first question in the black-screen playbook (section 12.1).
    reset_sync u_rst_pix (.clk (clk_pix), .async_rst_n (mmcm_locked), .rst (rst_pix));
    reset_sync u_rst_5x  (.clk (clk_5x),  .async_rst_n (mmcm_locked), .rst (rst_5x));
endmodule

`default_nettype wire
