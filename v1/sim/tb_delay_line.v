// tb_delay_line -- the module everything else depends on for alignment.
//
// Checks a few depths including the DEPTH=0 pass-through, because that case is
// what lets a parameterised latency go to zero without special-casing the
// instantiation, and it is easy to break.

`timescale 1ns/1ps
`default_nettype none

module tb_delay_line;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg [7:0] din = 8'd0;
    wire [7:0] d0, d1, d3, d7;

    delay_line #(.WIDTH(8), .DEPTH(0)) u0 (.clk(clk), .din(din), .dout(d0));
    delay_line #(.WIDTH(8), .DEPTH(1)) u1 (.clk(clk), .din(din), .dout(d1));
    delay_line #(.WIDTH(8), .DEPTH(3)) u3 (.clk(clk), .din(din), .dout(d3));
    delay_line #(.WIDTH(8), .DEPTH(7)) u7 (.clk(clk), .din(din), .dout(d7));

    reg [7:0] history [0:31];
    integer n = 0, errors = 0, i;

    always @(posedge clk) begin
        history[n % 32] <= din;
        n = n + 1;
    end

    task step(input [7:0] value);
        begin
            @(negedge clk);
            din = value;
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        for (i = 0; i < 32; i = i + 1) history[i] = 8'd0;

        for (i = 1; i <= 24; i = i + 1) begin
            step(i[7:0]);
            // DEPTH 0 is combinational.
            if (d0 !== din) begin
                $display("FAIL: DEPTH=0 gave %0d, expected %0d", d0, din);
                errors = errors + 1;
            end
            // A DEPTH=N line sampling on edge A presents that value on edge
            // A+(N-1): N registers, but the first one captures *at* A.  Mixing
            // the two conventions up is a one-pixel image shift, so the
            // testbench states which one it is using.
            if (d1 !== i[7:0]) begin
                $display("FAIL: DEPTH=1 gave %0d at step %0d, expected %0d", d1, i, i);
                errors = errors + 1;
            end
            if (i > 2 && d3 !== (i - 2)) begin
                $display("FAIL: DEPTH=3 gave %0d at step %0d, expected %0d", d3, i, i - 2);
                errors = errors + 1;
            end
            if (i > 6 && d7 !== (i - 6)) begin
                $display("FAIL: DEPTH=7 gave %0d at step %0d, expected %0d", d7, i, i - 6);
                errors = errors + 1;
            end
        end

        if (errors == 0) $display("PASS tb_delay_line");
        else begin
            $display("FAIL tb_delay_line: %0d errors", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule

`default_nettype wire
