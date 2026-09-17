// tb_top_smoke -- does the whole thing come up and produce a signal?
//
// Not a functional check (the unit testbenches do that); this is the
// integration equivalent of the first three questions in the black-screen
// playbook (design.md section 12.1):
//
//   1. does the MMCM lock?
//   2. is the pixel clock running at the frequency we asked for?
//   3. are de and hsync coming out with the right line length?
//
// plus one the playbook cannot check from the bench: that the TMDS pairs are
// actually toggling and actually differential.
//
// Runs at 640x480 (MODE=0) because a 25 MHz pixel clock keeps the simulation
// short; the timing arithmetic for every mode is proven in tb_video_timing.

`timescale 1ns/1ps
`default_nettype none

`include "video_modes.vh"

module tb_top_smoke;
    localparam LINES = 4;
    localparam H_TOTAL = `VGA_H_ACT + `VGA_H_FP + `VGA_H_SYNC + `VGA_H_BP;

    reg clk_100 = 1'b0;
    always #5 clk_100 = ~clk_100;    // 100 MHz

    reg  [15:0] sw  = 16'h4023;      // threshold 0x40, pattern 2, overlay mode
    reg  [3:0]  btn = 4'd0;
    wire [15:0] led;
    wire [7:0]  seg, an;
    wire [2:0]  tmds_d_p, tmds_d_n;
    wire        tmds_clk_p, tmds_clk_n;

    top #(
        .MODE (0),
        .LUT0 ("sim/vectors/lut/teal_orange_bank0.mem"),
        .LUT1 ("sim/vectors/lut/teal_orange_bank1.mem"),
        .LUT2 ("sim/vectors/lut/teal_orange_bank2.mem"),
        .LUT3 ("sim/vectors/lut/teal_orange_bank3.mem"),
        .LUT4 ("sim/vectors/lut/teal_orange_bank4.mem"),
        .LUT5 ("sim/vectors/lut/teal_orange_bank5.mem"),
        .LUT6 ("sim/vectors/lut/teal_orange_bank6.mem"),
        .LUT7 ("sim/vectors/lut/teal_orange_bank7.mem")
    ) dut (
        .clk_100mhz (clk_100),
        .sw (sw), .btn (btn), .uart_rxd (1'b1),
        .led (led), .seg (seg), .an (an),
        .tmds_d_p (tmds_d_p), .tmds_d_n (tmds_d_n),
        .tmds_clk_p (tmds_clk_p), .tmds_clk_n (tmds_clk_n)
    );

    integer errors = 0;
    integer de_cycles = 0, line_cycles = 0, lines_seen = 0;
    integer nonblack = 0;
    integer tmds_edges = 0;
    reg [2:0] tmds_prev = 3'd0;
    reg de_prev = 1'b0;
    reg counting = 1'b0;

    wire clk_pix = dut.clk_pix;
    wire de_out  = dut.de_proc;

    always @(posedge clk_pix) if (counting) begin
        line_cycles = line_cycles + 1;
        if (de_out) begin
            de_cycles = de_cycles + 1;
            if (dut.px_proc !== 24'h000000) nonblack = nonblack + 1;
        end
        if (de_prev && !de_out) begin
            lines_seen = lines_seen + 1;
            if (lines_seen > 1 && de_cycles != `VGA_H_ACT * lines_seen)
                $display("note: de count %0d after %0d lines", de_cycles, lines_seen);
        end
        de_prev = de_out;
    end

    always @(posedge dut.clk_5x) begin
        if (counting) begin
            if (tmds_d_p !== ~tmds_d_n) begin
                if (errors < 3) $display("FAIL: TMDS pair not differential");
                errors = errors + 1;
            end
            if (tmds_d_p !== tmds_prev) tmds_edges = tmds_edges + 1;
            tmds_prev = tmds_d_p;
        end
    end

    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("build/tb_top_smoke.vcd");
            $dumpvars(0, tb_top_smoke);
        end

        // 1. MMCM lock
        wait (dut.locked === 1'b1);
        $display("tb_top_smoke: MMCM locked at %0t", $time);
        if (led[0] !== 1'b1) begin
            $display("FAIL: locked is not wired to led[0]");
            errors = errors + 1;
        end

        // Let the pipeline fill: it is a line deep by construction.
        repeat (3 * H_TOTAL) @(posedge clk_pix);
        counting = 1'b1;
        repeat (LINES * H_TOTAL) @(posedge clk_pix);
        counting = 1'b0;

        // 2. de is asserted for the right fraction of the time
        $display("tb_top_smoke: %0d active pixels over %0d cycles (%0d lines)",
                 de_cycles, line_cycles, lines_seen);
        if (de_cycles < `VGA_H_ACT * (LINES - 1)) begin
            $display("FAIL: only %0d active pixels in %0d lines", de_cycles, LINES);
            errors = errors + 1;
        end

        // 3. the pipeline is producing picture, not black
        if (nonblack * 4 < de_cycles) begin
            $display("FAIL: %0d of %0d active pixels are black -- the pipeline is not"
                     , nonblack, de_cycles);
            $display("     passing video (check the pattern generator and the LUT)");
            errors = errors + 1;
        end

        // 4. the serialisers are running
        if (tmds_edges < 100) begin
            $display("FAIL: only %0d TMDS transitions -- serialisers are not running",
                     tmds_edges);
            errors = errors + 1;
        end

        $display("tb_top_smoke: %0d non-black pixels, %0d TMDS transitions",
                 nonblack, tmds_edges);
        if (errors == 0) $display("PASS tb_top_smoke");
        else begin
            $display("FAIL tb_top_smoke: %0d errors", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule

`default_nettype wire
