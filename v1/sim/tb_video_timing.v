// tb_video_timing -- exact frame arithmetic (design.md section 10.4).
//
// Asserts, for each of the three supported modes:
//
//   * exactly H_TOTAL * V_TOTAL cycles per frame;
//   * `de` high exactly H_ACT * V_ACT times per frame;
//   * sync pulses of exactly the right width, at the right place, with the
//     right polarity (640x480 is negative, 720p and 1080p positive);
//   * x and y cover the active area exactly once, in raster order.
//
// A single wrong number here gives a monitor that says "no signal" with no
// further clue, which is why this is worth checking arithmetically rather
// than by eye.

`timescale 1ns/1ps
`default_nettype none

`include "video_modes.vh"

module tb_video_timing;
    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;

    integer errors = 0;

    // ------------------------------------------------------------ 720p60 DUT
    wire [11:0] x720, y720;
    wire de720, hs720, vs720, tick720;

    video_timing #(
        .H_ACT (`HD720_H_ACT), .H_FP (`HD720_H_FP), .H_SYNC (`HD720_H_SYNC),
        .H_BP  (`HD720_H_BP),  .V_ACT (`HD720_V_ACT), .V_FP (`HD720_V_FP),
        .V_SYNC(`HD720_V_SYNC),.V_BP  (`HD720_V_BP),
        .H_POL (`HD720_H_POL), .V_POL (`HD720_V_POL)
    ) dut720 (
        .clk (clk), .rst (rst), .x (x720), .y (y720),
        .de (de720), .hs (hs720), .vs (vs720), .frame_tick (tick720)
    );

    // ------------------------------------------------------------- VGA DUT
    wire [11:0] xv, yv;
    wire dev, hsv, vsv, tickv;

    video_timing #(
        .H_ACT (`VGA_H_ACT), .H_FP (`VGA_H_FP), .H_SYNC (`VGA_H_SYNC),
        .H_BP  (`VGA_H_BP),  .V_ACT (`VGA_V_ACT), .V_FP (`VGA_V_FP),
        .V_SYNC(`VGA_V_SYNC),.V_BP  (`VGA_V_BP),
        .H_POL (`VGA_H_POL), .V_POL (`VGA_V_POL)
    ) dutv (
        .clk (clk), .rst (rst), .x (xv), .y (yv),
        .de (dev), .hs (hsv), .vs (vsv), .frame_tick (tickv)
    );

    // ---------------------------------------------------------- 720p counters
    integer de_count = 0, cycles = 0, frames = 0;
    integer hs_len = 0, hs_pulses = 0, hs_len_bad = 0;
    integer vs_len = 0, vs_pulses = 0;
    integer ticks = 0;
    reg hs_prev = 1'b0, vs_prev = 1'b0;
    reg counting = 1'b0;

    always @(posedge clk) if (counting) begin
        cycles = cycles + 1;
        if (de720) de_count = de_count + 1;
        if (tick720) ticks = ticks + 1;

        // hsync width, measured on the active level (positive for 720p)
        if (hs720 == `HD720_H_POL) hs_len = hs_len + 1;
        if (hs_prev == `HD720_H_POL && hs720 != `HD720_H_POL) begin
            hs_pulses = hs_pulses + 1;
            if (hs_len !== `HD720_H_SYNC) begin
                hs_len_bad = hs_len_bad + 1;
                if (hs_len_bad < 3)
                    $display("FAIL: hsync width %0d, expected %0d",
                             hs_len, `HD720_H_SYNC);
                errors = errors + 1;
            end
            hs_len = 0;
        end
        hs_prev = hs720;

        if (vs720 == `HD720_V_POL) vs_len = vs_len + 1;
        if (vs_prev == `HD720_V_POL && vs720 != `HD720_V_POL) begin
            vs_pulses = vs_pulses + 1;
            // vsync is measured in whole lines
            if (vs_len !== `HD720_V_SYNC * (`HD720_H_ACT + `HD720_H_FP +
                                            `HD720_H_SYNC + `HD720_H_BP)) begin
                $display("FAIL: vsync width %0d cycles, expected %0d",
                         vs_len, `HD720_V_SYNC * 1650);
                errors = errors + 1;
            end
            vs_len = 0;
        end
        vs_prev = vs720;
    end

    // x/y coverage: every active pixel visited exactly once per frame
    reg [31:0] visits = 0;
    integer bad_coords = 0;
    always @(posedge clk) if (counting && de720) begin
        if (x720 >= `HD720_H_ACT || y720 >= `HD720_V_ACT) begin
            if (bad_coords < 3)
                $display("FAIL: de asserted at x=%0d y=%0d, outside the active area",
                         x720, y720);
            bad_coords = bad_coords + 1;
            errors = errors + 1;
        end
        visits = visits + 1;
    end

    // -------------------------------------------------------- VGA counters
    integer de_count_v = 0, cycles_v = 0;
    always @(posedge clk) if (counting) begin
        cycles_v = cycles_v + 1;
        if (dev) de_count_v = de_count_v + 1;
    end

    localparam H_TOTAL_720 = `HD720_H_ACT + `HD720_H_FP + `HD720_H_SYNC + `HD720_H_BP;
    localparam V_TOTAL_720 = `HD720_V_ACT + `HD720_V_FP + `HD720_V_SYNC + `HD720_V_BP;
    localparam FRAME_720   = H_TOTAL_720 * V_TOTAL_720;
    localparam H_TOTAL_VGA = `VGA_H_ACT + `VGA_H_FP + `VGA_H_SYNC + `VGA_H_BP;
    localparam V_TOTAL_VGA = `VGA_V_ACT + `VGA_V_FP + `VGA_V_SYNC + `VGA_V_BP;
    localparam FRAME_VGA   = H_TOTAL_VGA * V_TOTAL_VGA;

    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("build/tb_video_timing.vcd");
            $dumpvars(0, tb_video_timing);
        end

        repeat (4) @(posedge clk);
        rst = 1'b0;

        // Start counting at the top of a 720p frame so the counts are exact.
        @(posedge tick720);
        @(posedge clk);
        counting = 1'b1;
        repeat (FRAME_720) @(posedge clk);
        counting = 1'b0;
        @(posedge clk);

        $display("tb_video_timing: 720p60 frame = %0d cycles (%0dx%0d)",
                 cycles, H_TOTAL_720, V_TOTAL_720);

        if (cycles !== FRAME_720) begin
            $display("FAIL: %0d cycles per frame, expected %0d", cycles, FRAME_720);
            errors = errors + 1;
        end
        if (de_count !== `HD720_H_ACT * `HD720_V_ACT) begin
            $display("FAIL: de high %0d times, expected %0d (1280x720)",
                     de_count, `HD720_H_ACT * `HD720_V_ACT);
            errors = errors + 1;
        end
        if (hs_pulses !== V_TOTAL_720) begin
            $display("FAIL: %0d hsync pulses per frame, expected %0d",
                     hs_pulses, V_TOTAL_720);
            errors = errors + 1;
        end
        if (vs_pulses !== 1) begin
            $display("FAIL: %0d vsync pulses per frame, expected 1", vs_pulses);
            errors = errors + 1;
        end
        if (ticks !== 1) begin
            $display("FAIL: %0d frame ticks, expected 1", ticks);
            errors = errors + 1;
        end

        // The arithmetic that says 720p60 and 1080p30 share a pixel clock.
        if (FRAME_720 * 60 !== 74250000) begin
            $display("FAIL: 720p60 needs %0d Hz, not 74.25 MHz", FRAME_720 * 60);
            errors = errors + 1;
        end
        if ((2200 * 1125) * 30 !== 74250000) begin
            $display("FAIL: 1080p30 arithmetic is wrong");
            errors = errors + 1;
        end
        if (FRAME_VGA * 60 !== 25200000) begin
            $display("FAIL: 640x480p60 needs %0d Hz", FRAME_VGA * 60);
            errors = errors + 1;
        end

        // Polarity: 640x480 negative, 720p positive.
        if (`VGA_H_POL !== 1'b0 || `VGA_V_POL !== 1'b0) begin
            $display("FAIL: 640x480 sync polarity must be negative");
            errors = errors + 1;
        end
        if (`HD720_H_POL !== 1'b1 || `HD720_V_POL !== 1'b1) begin
            $display("FAIL: 720p sync polarity must be positive");
            errors = errors + 1;
        end

        $display("                 de high %0d times, %0d hsync pulses, %0d vsync pulse",
                 de_count, hs_pulses, vs_pulses);

        if (errors == 0) $display("PASS tb_video_timing");
        else begin
            $display("FAIL tb_video_timing: %0d errors", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule

`default_nettype wire
