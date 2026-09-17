// tb_dvi_tx -- serialize, then deserialize, and check we get the words back.
//
// This is the test that catches the two classic black-screen causes that
// simulation *can* catch (design.md section 12.1):
//
//   * bit order -- TMDS is LSB first, and feeding data[9] first gives a stable
//     but meaningless signal;
//   * channel/phase alignment -- all four channels must present their words in
//     the same bit position, which is why the clock channel goes through an
//     identical serializer instead of being routed straight to an OBUFDS.
//
// The deserializer here samples both edges of clk_5x, exactly as a receiver
// would, then searches once for the word alignment and checks every channel
// agrees on it.

`timescale 1ns/1ps
`default_nettype none

`include "video_modes.vh"

module tb_dvi_tx;
    localparam PIXELS = 64;
    localparam CAPTURE = PIXELS * 10;

    reg clk_pix = 1'b0;
    reg clk_5x  = 1'b0;
    reg rst     = 1'b1;

    // 74.25 MHz and 371.25 MHz, phase aligned as one MMCM would produce them.
    always #6.7340 clk_pix = ~clk_pix;
    always #1.3468 clk_5x  = ~clk_5x;

    reg  [23:0] px = 24'h000000;
    reg         de = 1'b0;
    reg         hs = 1'b0;
    reg         vs = 1'b0;

    wire [2:0] tmds_p, tmds_n;
    wire       tmds_clk_p, tmds_clk_n;

    dvi_tx dut (
        .clk_pix (clk_pix), .clk_5x (clk_5x), .rst (rst),
        .px (px), .de (de), .hs (hs), .vs (vs),
        .tmds_p (tmds_p), .tmds_n (tmds_n),
        .tmds_clk_p (tmds_clk_p), .tmds_clk_n (tmds_clk_n)
    );

    // ---- capture the serial streams --------------------------------------
    reg        capturing = 1'b0;
    integer    nbits = 0;
    reg [0:CAPTURE-1] bits0, bits1, bits2, bitsc;

    always @(posedge clk_5x) if (capturing && nbits < CAPTURE) begin
        bits0[nbits] = tmds_p[0];
        bits1[nbits] = tmds_p[1];
        bits2[nbits] = tmds_p[2];
        bitsc[nbits] = tmds_clk_p;
        nbits = nbits + 1;
    end

    always @(negedge clk_5x) if (capturing && nbits < CAPTURE) begin
        bits0[nbits] = tmds_p[0];
        bits1[nbits] = tmds_p[1];
        bits2[nbits] = tmds_p[2];
        bitsc[nbits] = tmds_clk_p;
        nbits = nbits + 1;
    end

    // ---- expected encoder outputs ----------------------------------------
    // Snoop the encoders: this testbench is about the serializer, and the
    // encoder has its own testbench.
    reg [9:0] exp0 [0:PIXELS-1];
    reg [9:0] exp1 [0:PIXELS-1];
    reg [9:0] exp2 [0:PIXELS-1];
    integer   nwords = 0;

    always @(posedge clk_pix) if (capturing && nwords < PIXELS) begin
        exp0[nwords] = dut.ch0;
        exp1[nwords] = dut.ch1;
        exp2[nwords] = dut.ch2;
        nwords = nwords + 1;
    end

    // ---- checking --------------------------------------------------------
    integer errors = 0;
    integer woff, k, w, b, ok_align, best_align, lag, ok_lag, word_lag;
    reg [9:0] word;

    function [9:0] get_word(input [0:CAPTURE-1] stream, input integer start);
        integer j;
        begin
            get_word = 10'd0;
            for (j = 0; j < 10; j = j + 1)
                get_word[j] = stream[start + j];   // LSB first on the wire
        end
    endfunction

    // Differential outputs must always be complementary -- a stuck pair means
    // a missing OBUFDS or a constraint problem.  Sampled on the serial clock
    // rather than on any change, because p and n settle in different delta
    // cycles and comparing them mid-update is a simulation artifact.
    always @(posedge clk_5x) begin
        if (capturing && (tmds_p !== ~tmds_n)) begin
            $display("FAIL: TMDS pair not differential: p=%b n=%b", tmds_p, tmds_n);
            errors = errors + 1;
        end
        if (capturing && (tmds_clk_p !== ~tmds_clk_n)) begin
            $display("FAIL: TMDS clock pair not differential");
            errors = errors + 1;
        end
    end

    integer i;
    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("build/tb_dvi_tx.vcd");
            $dumpvars(0, tb_dvi_tx);
        end

        repeat (8) @(posedge clk_pix);
        rst = 1'b0;
        repeat (4) @(posedge clk_pix);

        // A frame fragment: blanking, then active video, then blanking again.
        @(negedge clk_pix);
        capturing = 1'b1;
        de = 1'b0; hs = 1'b1; vs = 1'b0;
        repeat (4) @(negedge clk_pix);
        de = 1'b1;
        for (i = 0; i < 40; i = i + 1) begin
            px = {8'h10 + i[7:0], 8'h80 - i[7:0], 8'hA0 ^ i[7:0]};
            @(negedge clk_pix);
        end
        de = 1'b0; hs = 1'b0; vs = 1'b1;
        repeat (8) @(negedge clk_pix);

        wait (nbits >= CAPTURE);
        capturing = 1'b0;

        // ---- find the word alignment on the clock channel ----
        // The clock channel is a constant word, so its stream is periodic;
        // whichever offset reproduces it exactly is the word boundary.
        best_align = -1;
        for (woff = 0; woff < 10; woff = woff + 1) begin
            ok_align = 1;
            for (w = 1; w < 20; w = w + 1)
                if (get_word(bitsc, woff + w * 10) !== `TMDS_CLK_WORD) ok_align = 0;
            if (ok_align && best_align < 0) best_align = woff;
        end

        // ---- find the word lag between the encoders and the wire ----
        word_lag = -1;
        if (best_align >= 0) begin
            for (lag = 0; lag < 6; lag = lag + 1) begin
                ok_lag = 1;
                for (w = 6; w < 20; w = w + 1)
                    if (get_word(bits0, best_align + w * 10) !== exp0[w - lag])
                        ok_lag = 0;
                if (ok_lag && word_lag < 0) word_lag = lag;
            end
            if (word_lag < 0) begin
                $display("FAIL: no consistent word lag between encoder and wire");
                $display("      wire word 6 = %b, encoder words 6..2 = %b %b %b %b %b",
                         get_word(bits0, best_align + 60),
                         exp0[6], exp0[5], exp0[4], exp0[3], exp0[2]);
                errors = errors + 1;
            end else begin
                $display("tb_dvi_tx: serializer word lag %0d pixel clocks", word_lag);
            end
        end

        if (best_align < 0 || word_lag < 0) begin
            $display("FAIL: clock channel never ok_align %b -- check bit order",
                     `TMDS_CLK_WORD);
            $display("      first 20 captured bits: %b", bitsc[0:19]);
            errors = errors + 1;
        end else begin
            $display("tb_dvi_tx: word alignment found at bit offset %0d", best_align);

            // ---- every data channel must use the same alignment ----
            for (w = 6; w < PIXELS - 2; w = w + 1) begin
                word = get_word(bits0, best_align + w * 10);
                if (word !== exp0[w - word_lag]) begin
                    if (errors < 5)
                        $display("FAIL: ch0 word %0d: got %b expected %b",
                                 w, word, exp0[w - word_lag]);
                    errors = errors + 1;
                end
                word = get_word(bits1, best_align + w * 10);
                if (word !== exp1[w - word_lag]) begin
                    if (errors < 5)
                        $display("FAIL: ch1 word %0d: got %b expected %b",
                                 w, word, exp1[w - word_lag]);
                    errors = errors + 1;
                end
                word = get_word(bits2, best_align + w * 10);
                if (word !== exp2[w - word_lag]) begin
                    if (errors < 5)
                        $display("FAIL: ch2 word %0d: got %b expected %b",
                                 w, word, exp2[w - word_lag]);
                    errors = errors + 1;
                end
            end

            // ---- the clock channel is a square wave at the pixel rate ----
            for (w = 2; w < 20; w = w + 1)
                if (get_word(bitsc, best_align + w * 10) !== `TMDS_CLK_WORD) begin
                    $display("FAIL: clock channel word %0d is %b", w,
                             get_word(bitsc, best_align + w * 10));
                    errors = errors + 1;
                end
        end

        if (errors == 0) begin
            $display("tb_dvi_tx: %0d serialized words per channel verified", PIXELS - 8);
            $display("PASS tb_dvi_tx");
        end else begin
            $display("FAIL tb_dvi_tx: %0d errors", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule

`default_nettype wire
