// tb_tmds_encoder -- the DVI spec's own guarantees (design.md section 10.4).
//
// Four checks, in increasing order of how much they tell you:
//
//   1. every encoded data word has at most 5 transitions;
//   2. the running disparity stays bounded;
//   3. the four control tokens appear exactly when de is low;
//   4. decoding the word recovers the original byte.
//
// (4) is the one that catches a genuinely wrong encoder.  A word can satisfy
// the transition and disparity limits and still carry the wrong byte.

`timescale 1ns/1ps
`default_nettype none

`include "video_modes.vh"

module tb_tmds_encoder;
    localparam LATENCY = 2;

    reg        clk = 1'b0;
    reg        rst = 1'b1;
    reg  [7:0] din = 8'd0;
    reg  [1:0] ctrl = 2'b00;
    reg        de  = 1'b0;
    wire [9:0] dout;

    always #5 clk = ~clk;   // 100 MHz in simulation; frequency is irrelevant here

    tmds_encoder dut (
        .clk(clk), .rst(rst), .din(din), .ctrl(ctrl), .de(de), .dout(dout)
    );

    // ---- reference decoder ------------------------------------------------
    function [7:0] tmds_decode(input [9:0] word);
        reg [7:0] d;
        integer k;
        begin
            d = word[9] ? ~word[7:0] : word[7:0];
            tmds_decode[0] = d[0];
            for (k = 1; k < 8; k = k + 1)
                tmds_decode[k] = word[8] ? (d[k] ^ d[k-1]) : ~(d[k] ^ d[k-1]);
        end
    endfunction

    function integer transitions(input [9:0] word);
        integer k;
        begin
            transitions = 0;
            for (k = 0; k < 9; k = k + 1)
                if (word[k] !== word[k+1]) transitions = transitions + 1;
        end
    endfunction

    // ---- pipeline of expected values --------------------------------------
    reg [7:0] din_pipe  [0:LATENCY-1];
    reg [1:0] ctrl_pipe [0:LATENCY-1];
    reg       de_pipe   [0:LATENCY-1];
    integer   p;

    always @(posedge clk) begin
        din_pipe[0]  <= din;
        ctrl_pipe[0] <= ctrl;
        de_pipe[0]   <= de;
        for (p = 1; p < LATENCY; p = p + 1) begin
            din_pipe[p]  <= din_pipe[p-1];
            ctrl_pipe[p] <= ctrl_pipe[p-1];
            de_pipe[p]   <= de_pipe[p-1];
        end
    end

    integer errors = 0;
    integer checked = 0;
    integer ctrl_checked = 0;
    integer max_transitions = 0;
    integer max_disparity = 0;
    integer disparity = 0;
    integer ones, zeros, k2;
    reg checking = 1'b0;

    always @(posedge clk) if (checking) begin
        if (de_pipe[LATENCY-1]) begin
            checked = checked + 1;

            // (1) transitions
            if (transitions(dout) > 5) begin
                $display("FAIL: %0d transitions in %b (data 0x%02h)",
                         transitions(dout), dout, din_pipe[LATENCY-1]);
                errors = errors + 1;
            end
            if (transitions(dout) > max_transitions)
                max_transitions = transitions(dout);

            // (2) disparity, tracked independently of the DUT
            ones = 0;
            for (k2 = 0; k2 < 10; k2 = k2 + 1) ones = ones + dout[k2];
            zeros = 10 - ones;
            disparity = disparity + ones - zeros;
            if (disparity > max_disparity)  max_disparity = disparity;
            if (-disparity > max_disparity) max_disparity = -disparity;
            if (disparity > 16 || disparity < -16) begin
                $display("FAIL: running disparity %0d out of bounds", disparity);
                errors = errors + 1;
            end

            // (4) round trip
            if (tmds_decode(dout) !== din_pipe[LATENCY-1]) begin
                $display("FAIL: encode(0x%02h) = %b decodes to 0x%02h",
                         din_pipe[LATENCY-1], dout, tmds_decode(dout));
                errors = errors + 1;
            end
        end else begin
            // (3) control tokens
            ctrl_checked = ctrl_checked + 1;
            disparity = 0;
            case (ctrl_pipe[LATENCY-1])
                2'b00: if (dout !== `TMDS_CTRL_00) begin
                           $display("FAIL: ctrl 00 gave %b", dout); errors = errors + 1; end
                2'b01: if (dout !== `TMDS_CTRL_01) begin
                           $display("FAIL: ctrl 01 gave %b", dout); errors = errors + 1; end
                2'b10: if (dout !== `TMDS_CTRL_10) begin
                           $display("FAIL: ctrl 10 gave %b", dout); errors = errors + 1; end
                2'b11: if (dout !== `TMDS_CTRL_11) begin
                           $display("FAIL: ctrl 11 gave %b", dout); errors = errors + 1; end
            endcase
        end
    end

    // Stimulus changes on the negative edge and is sampled on the positive
    // edge, so there is no race between driving and checking.
    task drive(input [7:0] value);
        begin
            @(negedge clk);
            din = value;
            @(posedge clk);
        end
    endtask

    integer i, j;
    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("build/tb_tmds_encoder.vcd");
            $dumpvars(0, tb_tmds_encoder);
        end
        repeat (4) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);
        checking = 1'b1;

        // Sweep every input value, twice, so the disparity state differs on
        // the second pass.
        de = 1'b1;
        for (j = 0; j < 2; j = j + 1)
            for (i = 0; i < 256; i = i + 1) drive(i[7:0]);

        // Worst case for DC balance: long runs of the same value.
        for (i = 0; i < 512; i = i + 1) drive(8'h00);
        for (i = 0; i < 512; i = i + 1) drive(8'hFF);
        for (i = 0; i < 512; i = i + 1) drive(8'hAA);

        // Random data.
        for (i = 0; i < 4096; i = i + 1) drive($random);

        // Blanking with every control code, as a real frame does between lines.
        @(negedge clk);
        de = 1'b0;
        for (i = 0; i < 4; i = i + 1) begin
            @(negedge clk);
            ctrl = i[1:0];
            repeat (8) @(negedge clk);
        end
        @(negedge clk);
        de = 1'b1;

        // Back to active video, to prove the encoder recovers from blanking.
        for (i = 0; i < 256; i = i + 1) drive(i[7:0]);

        repeat (LATENCY + 2) @(posedge clk);
        checking = 1'b0;

        $display("tb_tmds_encoder: %0d data words, %0d control words checked",
                 checked, ctrl_checked);
        $display("                 max transitions %0d (limit 5), max |disparity| %0d",
                 max_transitions, max_disparity);
        if (errors == 0) $display("PASS tb_tmds_encoder");
        else begin
            $display("FAIL tb_tmds_encoder: %0d errors", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule

`default_nettype wire
