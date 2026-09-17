// tb_pipeline -- a whole image in, a whole image out, compared pixel for
// pixel against the Python golden model (design.md section 10.3).
//
//   vvp build/tb_pipeline.vvp +mode=3 +grade=teal_orange
//
// This is the testbench that matters.  Debugging video by looking at a monitor
// is close to useless: a single off-by-one in a line buffer produces an image
// that looks subtly wrong in a way you cannot localise.  Here the answer is
// "first mismatch at (x=1, y=2)".
//
// The image is streamed with realistic blanking, so the line buffers see the
// same line boundaries they will see on hardware.

`timescale 1ns/1ps
`default_nettype none

`include "video_modes.vh"

module tb_pipeline;
    // Small image: simulation of a real 720p frame would take hours, and every
    // bug this catches is visible at 64x64.
    localparam W = 64;
    localparam H = 64;
    localparam H_BLANK = 20;
    localparam V_BLANK = 4;
    localparam H_TOTAL = W + H_BLANK;
    localparam MAXPIX  = W * H;

    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;

    reg  [23:0] px_in = 24'd0;
    reg         de_in = 1'b0;
    reg         hs_in = 1'b0;
    reg         vs_in = 1'b0;
    reg  [11:0] x_in  = 12'd0;
    reg  [11:0] y_in  = 12'd0;

    reg  [1:0]  mode = `MODE_OVERLAY;
    reg  [7:0]  threshold = 8'd64;
    reg         lut_bypass = 1'b0;
    reg         glow = 1'b0;

    wire [23:0] px_out;
    wire        de_out, hs_out, vs_out;

    video_pipeline #(
        .H_ACT (W), .V_ACT (H), .H_TOTAL (H_TOTAL), .MAX_LINE (256)
    ) dut (
        .clk (clk), .rst (rst),
        .px_in (px_in), .de_in (de_in), .hs_in (hs_in), .vs_in (vs_in),
        .x_in (x_in), .y_in (y_in),
        .mode (mode), .threshold (threshold),
        .lut_bypass (lut_bypass), .glow (glow),
        .px_out (px_out), .de_out (de_out), .hs_out (hs_out), .vs_out (vs_out)
    );

    reg [23:0] src [0:MAXPIX-1];
    reg [8*64-1:0]  grade;
    reg [8*256-1:0] bf0, bf1, bf2, bf3, bf4, bf5, bf6, bf7;
    reg [8*256-1:0] outfile;
    integer mode_arg, thr_arg;
    integer fout;
    integer out_count = 0;

    // Collect every pixel the pipeline says is active.
    always @(posedge clk) if (!rst && de_out) begin
        $fwrite(fout, "%06h\n", px_out);
        out_count = out_count + 1;
    end

    integer i, j, line;
    initial begin
        if (!$value$plusargs("grade=%s", grade)) grade = "identity";
        if (!$value$plusargs("mode=%d", mode_arg)) mode_arg = 3;
        if (!$value$plusargs("threshold=%d", thr_arg)) thr_arg = 64;
        mode = mode_arg[1:0];
        threshold = thr_arg[7:0];

        // Load banks after time 0, so lut_bank's own initialisation does not
        // run afterwards and wipe them.
        #1;
        $sformat(bf0, "sim/vectors/lut/%0s_bank0.mem", grade);
        $sformat(bf1, "sim/vectors/lut/%0s_bank1.mem", grade);
        $sformat(bf2, "sim/vectors/lut/%0s_bank2.mem", grade);
        $sformat(bf3, "sim/vectors/lut/%0s_bank3.mem", grade);
        $sformat(bf4, "sim/vectors/lut/%0s_bank4.mem", grade);
        $sformat(bf5, "sim/vectors/lut/%0s_bank5.mem", grade);
        $sformat(bf6, "sim/vectors/lut/%0s_bank6.mem", grade);
        $sformat(bf7, "sim/vectors/lut/%0s_bank7.mem", grade);
        $readmemh(bf0, dut.u_lut.u_b0.mem);
        $readmemh(bf1, dut.u_lut.u_b1.mem);
        $readmemh(bf2, dut.u_lut.u_b2.mem);
        $readmemh(bf3, dut.u_lut.u_b3.mem);
        $readmemh(bf4, dut.u_lut.u_b4.mem);
        $readmemh(bf5, dut.u_lut.u_b5.mem);
        $readmemh(bf6, dut.u_lut.u_b6.mem);
        $readmemh(bf7, dut.u_lut.u_b7.mem);

        $readmemh("sim/vectors/input.hex", src);
        $sformat(outfile, "build/output_mode%0d_%0s.hex", mode_arg, grade);
        fout = $fopen(outfile, "w");
        if (fout == 0) begin
            $display("FAIL tb_pipeline: cannot open %0s", outfile);
            $fatal(1);
        end

        if ($test$plusargs("vcd")) begin
            $dumpfile("build/tb_pipeline.vcd");
            $dumpvars(0, tb_pipeline);
        end

        repeat (4) @(negedge clk);
        rst = 1'b0;

        // Prime the pipeline with one blank frame's worth of line periods so
        // the line buffers hold real data rather than reset values by the time
        // the first active line arrives.
        for (line = 0; line < 3; line = line + 1)
            for (i = 0; i < H_TOTAL; i = i + 1) begin
                @(negedge clk);
                de_in = 1'b0; x_in = i[11:0]; y_in = 12'd0; px_in = 24'd0;
            end

        // The frame itself.
        for (j = 0; j < H; j = j + 1) begin
            for (i = 0; i < W; i = i + 1) begin
                @(negedge clk);
                de_in = 1'b1;
                x_in  = i[11:0];
                y_in  = j[11:0];
                px_in = src[j * W + i];
                hs_in = 1'b0;
            end
            for (i = W; i < H_TOTAL; i = i + 1) begin
                @(negedge clk);
                de_in = 1'b0;
                x_in  = i[11:0];
                y_in  = j[11:0];
                px_in = 24'd0;
                hs_in = (i >= W + 2) && (i < W + 6);
            end
        end

        // Flush: the last line is still inside the delay chain.
        vs_in = 1'b1;
        for (line = 0; line < V_BLANK; line = line + 1)
            for (i = 0; i < H_TOTAL; i = i + 1) begin
                @(negedge clk);
                de_in = 1'b0;
                x_in  = i[11:0];
                y_in  = H[11:0] + line[11:0];
                px_in = 24'd0;
            end

        $fclose(fout);
        $display("tb_pipeline[mode=%0d grade=%0s]: %0d pixels written to %0s",
                 mode_arg, grade, out_count, outfile);
        if (out_count !== MAXPIX) begin
            $display("FAIL tb_pipeline: %0d pixels, expected %0d -- de_out is not"
                     , out_count, MAXPIX);
            $display("     aligned with the data; check the sync delay depth");
            $fatal(1);
        end
        $display("PASS tb_pipeline (pixel count); compare against the model next");
        $finish;
    end
endmodule

`default_nettype wire
