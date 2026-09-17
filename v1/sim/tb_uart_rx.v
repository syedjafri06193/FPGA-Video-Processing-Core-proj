// tb_uart_rx -- bytes in at the wire level, bytes out at the register level.
//
// Checks the normal path, a back-to-back pair, a framing error (missing stop
// bit), and a glitch on the idle line that must not be mistaken for a start
// bit.  The last one is why the receiver re-checks the start bit at its
// midpoint rather than committing on the falling edge.

`timescale 1ns/1ps
`default_nettype none

module tb_uart_rx;
    localparam CLK_HZ = 1_000_000;    // small numbers keep the sim short
    localparam BAUD   = 125_000;      // 8 clocks per bit
    localparam integer BIT_CYCLES = CLK_HZ / BAUD;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg rx  = 1'b1;
    always #5 clk = ~clk;

    wire [7:0] data;
    wire       valid, frame_error;

    uart_rx #(.CLK_HZ (CLK_HZ), .BAUD (BAUD)) dut (
        .clk (clk), .rst (rst), .rx (rx),
        .data (data), .valid (valid), .frame_error (frame_error)
    );

    integer errors = 0;
    integer received = 0;
    reg [7:0] last = 8'd0;

    always @(posedge clk) if (valid) begin
        last = data;
        received = received + 1;
    end

    task send_byte(input [7:0] value, input stop_bit);
        integer b;
        begin
            rx = 1'b0;                                  // start
            repeat (BIT_CYCLES) @(posedge clk);
            for (b = 0; b < 8; b = b + 1) begin         // LSB first
                rx = value[b];
                repeat (BIT_CYCLES) @(posedge clk);
            end
            rx = stop_bit;
            repeat (BIT_CYCLES) @(posedge clk);
            rx = 1'b1;
        end
    endtask

    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("build/tb_uart_rx.vcd");
            $dumpvars(0, tb_uart_rx);
        end

        repeat (4) @(posedge clk);
        rst = 1'b0;
        repeat (4) @(posedge clk);

        send_byte(8'h5A, 1'b1);
        repeat (4) @(posedge clk);
        if (received !== 1 || last !== 8'h5A) begin
            $display("FAIL: sent 0x5A, got 0x%02h after %0d bytes", last, received);
            errors = errors + 1;
        end

        // Back to back, as a two-byte control command arrives.
        send_byte(8'h01, 1'b1);
        send_byte(8'h40, 1'b1);
        repeat (4) @(posedge clk);
        if (received !== 3 || last !== 8'h40) begin
            $display("FAIL: back-to-back bytes: got 0x%02h after %0d", last, received);
            errors = errors + 1;
        end

        // Framing error: stop bit low.
        send_byte(8'hA5, 1'b0);
        repeat (4) @(posedge clk);
        if (received !== 3) begin
            $display("FAIL: framing error still produced a byte");
            errors = errors + 1;
        end
        if (!frame_error) begin
            $display("FAIL: framing error not reported");
            errors = errors + 1;
        end

        // A one-clock glitch on an idle line is not a start bit.
        repeat (20) @(posedge clk);
        rx = 1'b0;
        @(posedge clk);
        rx = 1'b1;
        repeat (BIT_CYCLES * 12) @(posedge clk);
        if (received !== 3) begin
            $display("FAIL: a glitch was decoded as a byte (got %0d bytes)", received);
            errors = errors + 1;
        end

        // And the receiver still works afterwards.
        send_byte(8'h7E, 1'b1);
        repeat (4) @(posedge clk);
        if (received !== 4 || last !== 8'h7E) begin
            $display("FAIL: receiver did not recover after a glitch");
            errors = errors + 1;
        end

        $display("tb_uart_rx: %0d bytes received", received);
        if (errors == 0) $display("PASS tb_uart_rx");
        else begin
            $display("FAIL tb_uart_rx: %0d errors", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule

`default_nettype wire
