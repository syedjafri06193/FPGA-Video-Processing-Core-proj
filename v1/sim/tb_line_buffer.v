// tb_line_buffer -- push a counting ramp and assert the rows are exactly one
// and two line periods apart (design.md section 10.4).
//
// This is the testbench that catches the classic off-by-one that shifts an
// image vertically by a line or two on hardware -- a bug that is invisible on
// a monitor and obvious here.

`timescale 1ns/1ps
`default_nettype none

module tb_line_buffer;
    localparam W = 16;      // pixels per line -- small, so the sim is quick
    localparam H = 8;

    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;

    reg  [23:0] din = 24'd0;
    reg         de  = 1'b0;
    wire [23:0] row0, row1, row2;
    wire        valid;

    line_buffer #(.WIDTH(24), .MAX_X(64)) dut (
        .clk (clk), .rst (rst), .de (de), .line_len (W[11:0]),
        .din (din), .row0 (row0), .row1 (row1), .row2 (row2), .valid (valid)
    );

    // Each pixel is its own (y, x) coordinate, so a misaligned row is obvious.
    function [23:0] pixel(input integer y, input integer x);
        pixel = {8'd0, y[7:0], x[7:0]};
    endfunction

    integer errors = 0, checked = 0;
    integer x, y, out_x, out_y;
    reg [23:0] want0, want1, want2;

    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("build/tb_line_buffer.vcd");
            $dumpvars(0, tb_line_buffer);
        end

        repeat (4) @(posedge clk);
        rst = 1'b0;

        // Feed H lines of W pixels, with blanking between lines exactly as the
        // timing generator produces it.
        for (y = 0; y < H; y = y + 1) begin
            for (x = 0; x < W; x = x + 1) begin
                @(negedge clk);
                de  = 1'b1;
                din = pixel(y, x);
            end
            @(negedge clk);
            de = 1'b0;
            repeat (6) @(negedge clk);   // horizontal blanking
        end
        @(negedge clk);
        de = 1'b0;
        repeat (10) @(negedge clk);

        $display("tb_line_buffer: %0d row triples checked", checked);
        if (errors == 0) $display("PASS tb_line_buffer");
        else begin
            $display("FAIL tb_line_buffer: %0d errors", errors);
            $fatal(1);
        end
        $finish;
    end

    // The output stream lags the input by the buffer's latency; reconstruct
    // which coordinate should be emerging and check all three rows at once.
    integer seen = 0;
    always @(posedge clk) begin
        if (!rst && valid) begin
            out_x = seen % W;
            out_y = seen / W;
            seen  = seen + 1;

            // Rows above the top of the frame read as whatever the memory held
            // (zero after reset), so only check once two full lines are in.
            if (out_y >= 2) begin
                checked = checked + 1;
                want2 = pixel(out_y, out_x);
                want1 = pixel(out_y - 1, out_x);
                want0 = pixel(out_y - 2, out_x);
                if (row2 !== want2 || row1 !== want1 || row0 !== want0) begin
                    errors = errors + 1;
                    if (errors <= 6)
                        $display("FAIL at (x=%0d,y=%0d): row2=%06h/%06h row1=%06h/%06h row0=%06h/%06h",
                                 out_x, out_y, row2, want2, row1, want1, row0, want0);
                end
            end
        end
    end
endmodule

`default_nettype wire
