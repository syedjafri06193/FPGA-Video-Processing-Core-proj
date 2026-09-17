// tb_lut3d -- the LUT against the Python golden model, pixel for pixel.
//
// Run per grade:  vvp build/tb_lut3d.vvp +grade=teal_orange
//
// Two things are being checked at once:
//
//   * the bank addressing, including the per-axis carry that the design
//     document's "same address for all banks" claim gets wrong.  With the
//     document's version this testbench fails on roughly 7 of every 8 pixels;
//   * the interpolation arithmetic, including the signed shift in lerp8 and
//     the B-then-G-then-R ordering, which has to match the model bit for bit.
//
// The identity grade is checked separately and more strictly: it must
// reproduce its input exactly below 240, and within 1 LSB above it, which is
// the documented consequence of node 16 representing 256 as 255.

`timescale 1ns/1ps
`default_nettype none

module tb_lut3d;
    localparam LATENCY = 6;
    localparam MAX_PIXELS = 8192;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg  [23:0] px_in = 24'd0;
    wire [23:0] px_out;

    // The grade under test is chosen at run time so one build covers them all.
    reg [8*64-1:0]  grade;
    // Separate registers rather than an array: $sformat cannot target an
    // array element in Icarus.
    reg [8*256-1:0] bf0, bf1, bf2, bf3, bf4, bf5, bf6, bf7;
    reg [8*256-1:0] stim_file, exp_file;

    reg [23:0] stim [0:MAX_PIXELS-1];
    reg [23:0] expected [0:MAX_PIXELS-1];
    integer n_stim = 0;

    // Banks are loaded by hierarchical reference after the files are known,
    // which keeps one compiled testbench usable for every grade.
    lut3d dut (.clk(clk), .px_in(px_in), .px_out(px_out));

    integer errors = 0;
    integer checked = 0;
    integer i, j, fd;
    integer identity_exact_errors = 0;
    integer identity_lsb_errors = 0;
    reg [23:0] got, want, src;
    reg is_identity;

    // Two conventions, and mixing them up is a one-pixel shift:
    //
    //   LATENCY = 6 is the number of pipeline *registers*, which is what a
    //   parallel delay_line must have to stay aligned;
    //
    //   the output for a value sampled on edge A appears on edge A + 5, so a
    //   checker stepping one edge per stimulus compares against the stimulus
    //   from LATENCY-1 iterations ago.
    //
    // This is exactly the off-by-one that shifts an image horizontally by a
    // pixel on hardware (section 12.2), which is why it is worth stating.
    localparam CHECK_DELAY = LATENCY - 1;

    initial begin
        if (!$value$plusargs("grade=%s", grade)) grade = "identity";
        is_identity = (grade == "identity");

        // Wait for time 0 to settle before loading: lut_bank's own initial
        // block clears its memory, and the order of initial blocks at time 0
        // is undefined -- load first and it wipes the LUT out from under you.
        #1;

        // Load the eight banks for this grade.
        $sformat(bf0, "sim/vectors/lut/%0s_bank0.mem", grade);
        $sformat(bf1, "sim/vectors/lut/%0s_bank1.mem", grade);
        $sformat(bf2, "sim/vectors/lut/%0s_bank2.mem", grade);
        $sformat(bf3, "sim/vectors/lut/%0s_bank3.mem", grade);
        $sformat(bf4, "sim/vectors/lut/%0s_bank4.mem", grade);
        $sformat(bf5, "sim/vectors/lut/%0s_bank5.mem", grade);
        $sformat(bf6, "sim/vectors/lut/%0s_bank6.mem", grade);
        $sformat(bf7, "sim/vectors/lut/%0s_bank7.mem", grade);
        $readmemh(bf0, dut.u_b0.mem);
        $readmemh(bf1, dut.u_b1.mem);
        $readmemh(bf2, dut.u_b2.mem);
        $readmemh(bf3, dut.u_b3.mem);
        $readmemh(bf4, dut.u_b4.mem);
        $readmemh(bf5, dut.u_b5.mem);
        $readmemh(bf6, dut.u_b6.mem);
        $readmemh(bf7, dut.u_b7.mem);

        stim_file = "sim/vectors/lut_stim.hex";
        $sformat(exp_file, "sim/vectors/lut_stim_expected_%0s.hex", grade);
        for (i = 0; i < MAX_PIXELS; i = i + 1) begin
            stim[i] = 24'hxxxxxx;
            expected[i] = 24'hxxxxxx;
        end
        $readmemh(stim_file, stim);
        $readmemh(exp_file, expected);

        n_stim = 0;
        for (i = 0; i < MAX_PIXELS; i = i + 1)
            if (stim[i] !== 24'hxxxxxx) n_stim = i + 1;

        if (n_stim == 0) begin
            $display("FAIL tb_lut3d: no stimulus -- run 'make vectors' first");
            $fatal(1);
        end

        if ($test$plusargs("vcd")) begin
            $dumpfile("build/tb_lut3d.vcd");
            $dumpvars(0, tb_lut3d);
        end

        // Push the stimulus through, checking LATENCY cycles behind.
        for (i = 0; i < n_stim + CHECK_DELAY; i = i + 1) begin
            @(negedge clk);
            px_in = (i < n_stim) ? stim[i] : 24'd0;
            @(posedge clk);
            #1;
            if (i >= CHECK_DELAY) begin
                j    = i - CHECK_DELAY;
                got  = px_out;
                want = expected[j];
                src  = stim[j];
                checked = checked + 1;

                if (got !== want) begin
                    errors = errors + 1;
                    if (errors <= 8)
                        $display("FAIL: in=%06h got=%06h expected=%06h", src, got, want);
                end

                if (is_identity) begin
                    // Exact below the top node, within 1 LSB above it.
                    if (src[23:16] <= 8'd240 && src[15:8] <= 8'd240 && src[7:0] <= 8'd240) begin
                        if (got !== src) begin
                            identity_exact_errors = identity_exact_errors + 1;
                            if (identity_exact_errors <= 4)
                                $display("FAIL: identity LUT changed %06h into %06h",
                                         src, got);
                        end
                    end else begin
                        // Widened to 9 bits: src[23:16] + 8'd1 wraps to 0 at
                        // 255, which is precisely the value being tested.
                        if ((({1'b0, got[23:16]} > {1'b0, src[23:16]} + 9'd1)) ||
                            (({1'b0, src[23:16]} > {1'b0, got[23:16]} + 9'd1)) ||
                            (({1'b0, got[15:8]}  > {1'b0, src[15:8]}  + 9'd1)) ||
                            (({1'b0, src[15:8]}  > {1'b0, got[15:8]}  + 9'd1)) ||
                            (({1'b0, got[7:0]}   > {1'b0, src[7:0]}   + 9'd1)) ||
                            (({1'b0, src[7:0]}   > {1'b0, got[7:0]}   + 9'd1))) begin
                            identity_lsb_errors = identity_lsb_errors + 1;
                            if (identity_lsb_errors <= 4)
                                $display("FAIL: identity LUT off by >1 LSB: %06h -> %06h",
                                         src, got);
                        end
                    end
                end
            end
        end

        $display("tb_lut3d[%0s]: %0d pixels checked against the golden model",
                 grade, checked);
        if (is_identity)
            $display("              identity: %0d exact errors, %0d >1 LSB errors",
                     identity_exact_errors, identity_lsb_errors);

        if (errors == 0 && identity_exact_errors == 0 && identity_lsb_errors == 0)
            $display("PASS tb_lut3d[%0s]", grade);
        else begin
            $display("FAIL tb_lut3d[%0s]: %0d mismatches", grade, errors);
            $fatal(1);
        end
        $finish;
    end
endmodule

`default_nettype wire
