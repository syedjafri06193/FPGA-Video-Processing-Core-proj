// 8N1 UART receiver, oversampled 16x.
//
// Used for runtime control (design.md section 8, M8): set the edge threshold
// numerically, switch modes, and -- as a stretch goal -- upload a LUT.
//
// The start bit is confirmed at its midpoint before the receiver commits, so a
// glitch on an idle line does not shift a byte in.

`default_nettype none

module uart_rx #(
    parameter CLK_HZ  = 74_250_000,
    parameter BAUD    = 115_200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid,      // one cycle per received byte
    output reg        frame_error
);
    localparam integer DIVISOR = CLK_HZ / BAUD;
    localparam integer HALF    = DIVISOR / 2;

    localparam ST_IDLE  = 2'd0;
    localparam ST_START = 2'd1;
    localparam ST_DATA  = 2'd2;
    localparam ST_STOP  = 2'd3;

    // Two flops before anything looks at the pin: it is asynchronous.
    (* ASYNC_REG = "TRUE" *) reg rx_meta = 1'b1;
    (* ASYNC_REG = "TRUE" *) reg rx_sync = 1'b1;
    always @(posedge clk) begin
        rx_meta <= rx;
        rx_sync <= rx_meta;
    end

    reg [1:0]  state = ST_IDLE;
    reg [15:0] count = 16'd0;
    reg [2:0]  bit_index = 3'd0;
    reg [7:0]  shifter = 8'd0;

    always @(posedge clk) begin
        if (rst) begin
            state       <= ST_IDLE;
            count       <= 16'd0;
            bit_index   <= 3'd0;
            valid       <= 1'b0;
            frame_error <= 1'b0;
        end else begin
            valid <= 1'b0;
            case (state)
                ST_IDLE: begin
                    if (!rx_sync) begin          // falling edge: start bit
                        state <= ST_START;
                        count <= 16'd0;
                    end
                end

                ST_START: begin
                    if (count == HALF[15:0]) begin
                        if (!rx_sync) begin      // still low at mid-bit
                            state     <= ST_DATA;
                            count     <= 16'd0;
                            bit_index <= 3'd0;
                        end else begin
                            state <= ST_IDLE;    // glitch, not a start bit
                        end
                    end else begin
                        count <= count + 16'd1;
                    end
                end

                ST_DATA: begin
                    if (count == DIVISOR[15:0] - 1) begin
                        count   <= 16'd0;
                        shifter <= {rx_sync, shifter[7:1]};   // LSB first
                        if (bit_index == 3'd7) state <= ST_STOP;
                        else bit_index <= bit_index + 3'd1;
                    end else begin
                        count <= count + 16'd1;
                    end
                end

                ST_STOP: begin
                    if (count == DIVISOR[15:0] - 1) begin
                        count <= 16'd0;
                        state <= ST_IDLE;
                        data  <= shifter;
                        if (rx_sync) begin
                            valid       <= 1'b1;        // proper stop bit
                            frame_error <= 1'b0;
                        end else begin
                            // Sticky: it drives an LED, and a framing error
                            // that clears itself a cycle later is one nobody
                            // will ever see.  Cleared by the next good byte.
                            frame_error <= 1'b1;
                        end
                    end else begin
                        count <= count + 16'd1;
                    end
                end
            endcase
        end
    end
endmodule

`default_nettype wire
