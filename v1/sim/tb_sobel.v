// tb_sobel -- known responses (design.md section 10.4).
//
//   * a single white pixel on black gives the known 3x3 kernel response;
//   * a vertical edge maximises Gx and zeroes Gy;
//   * a horizontal edge does the opposite;
//   * flat field gives zero, whatever the level;
//   * the border flag forces black regardless of the gradient.
//
// These are the cases you can work out on paper, which makes them the ones
// worth asserting: if they pass, an error in the full-frame comparison is in
// the plumbing rather than in the arithmetic.

`timescale 1ns/1ps
`default_nettype none

module tb_sobel;
    localparam LATENCY = 2;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg [7:0] p00 = 0, p01 = 0, p02 = 0;
    reg [7:0] p10 = 0, p11 = 0, p12 = 0;
    reg [7:0] p20 = 0, p21 = 0, p22 = 0;
    reg [7:0] threshold = 8'd64;
    reg       border = 1'b0;
    wire [7:0] mag;
    wire       edge_flag;

    sobel dut (
        .clk (clk), .en (1'b1),
        .p00 (p00), .p01 (p01), .p02 (p02),
        .p10 (p10), .p11 (p11), .p12 (p12),
        .p20 (p20), .p21 (p21), .p22 (p22),
        .threshold (threshold), .border (border),
        .mag (mag), .edge_flag (edge_flag)
    );

    integer errors = 0;

    task apply(input [7:0] a, input [7:0] b, input [7:0] c,
               input [7:0] d, input [7:0] e, input [7:0] f,
               input [7:0] g, input [7:0] h, input [7:0] i,
               input bdr);
        begin
            @(negedge clk);
            p00 = a; p01 = b; p02 = c;
            p10 = d; p11 = e; p12 = f;
            p20 = g; p21 = h; p22 = i;
            border = bdr;
            repeat (LATENCY) @(posedge clk);
            #1;
        end
    endtask

    task expect_mag(input [8*32-1:0] name, input [7:0] want);
        begin
            if (mag !== want) begin
                $display("FAIL %0s: mag=%0d expected %0d", name, mag, want);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("build/tb_sobel.vcd");
            $dumpvars(0, tb_sobel);
        end

        // Flat black and flat white: no gradient anywhere.
        apply(0,0,0, 0,0,0, 0,0,0, 1'b0);
        expect_mag("flat black", 8'd0);
        apply(255,255,255, 255,255,255, 255,255,255, 1'b0);
        expect_mag("flat white", 8'd0);
        if (edge_flag !== 1'b0) begin
            $display("FAIL: flat field flagged as an edge");
            errors = errors + 1;
        end

        // Vertical edge: left half black, right half white.
        // Gx = (0 + 0 + 0) - ... = 255*4 = 1020, Gy = 0 -> clamped to 255.
        apply(0,0,255, 0,0,255, 0,0,255, 1'b0);
        expect_mag("vertical edge", 8'd255);

        // Horizontal edge: top black, bottom white.  Gy maximal, Gx zero.
        apply(0,0,0, 0,0,0, 255,255,255, 1'b0);
        expect_mag("horizontal edge", 8'd255);

        // Single white pixel in the centre: both gradients cancel, and the
        // centre pixel itself has zero weight in either kernel.
        apply(0,0,0, 0,255,0, 0,0,0, 1'b0);
        expect_mag("centre impulse", 8'd0);

        // White pixel at a corner: Gx = -255, Gy = -255 -> 510, clamped.
        apply(255,0,0, 0,0,0, 0,0,0, 1'b0);
        expect_mag("corner impulse", 8'd255);

        // A gentle gradient that does not clamp: step of 16 across.
        // Gx = 4*16 = 64, Gy = 0.
        apply(0,0,16, 0,0,16, 0,0,16, 1'b0);
        expect_mag("small step", 8'd64);

        // Threshold behaviour: 64 is not > 64, so no flag; 65 is.
        if (edge_flag !== 1'b0) begin
            $display("FAIL: magnitude 64 flagged at threshold 64");
            errors = errors + 1;
        end
        @(negedge clk); threshold = 8'd63;
        apply(0,0,16, 0,0,16, 0,0,16, 1'b0);
        if (edge_flag !== 1'b1) begin
            $display("FAIL: magnitude 64 not flagged at threshold 63");
            errors = errors + 1;
        end

        // Border forces black even on a maximal gradient.
        apply(0,0,255, 0,0,255, 0,0,255, 1'b1);
        expect_mag("border", 8'd0);
        if (edge_flag !== 1'b0) begin
            $display("FAIL: border pixel flagged as an edge");
            errors = errors + 1;
        end

        if (errors == 0) $display("PASS tb_sobel");
        else begin
            $display("FAIL tb_sobel: %0d errors", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule

`default_nettype wire
