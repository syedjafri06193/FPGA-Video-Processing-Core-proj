// 8-digit multiplexed seven-segment display (design.md milestone M1).
//
// Worth building early and keeping: it is the only way to print a number from
// inside the FPGA without a UART, and the black-screen playbook (section 12.1)
// leans on it twice -- to show the measured pixel clock and to show a frame
// counter that proves the timing generator is running.
//
// Segments and anodes are active low, which is the usual arrangement; if the
// display is inverted on your board, flip ACTIVE_LOW rather than editing the
// decoder.

`default_nettype none

module seven_seg #(
    parameter CLK_HZ      = 74_250_000,
    parameter REFRESH_HZ  = 1000,        // per digit
    parameter ACTIVE_LOW  = 1
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] value,            // displayed as 8 hex digits
    input  wire [7:0]  dp,               // decimal points, bit per digit
    output reg  [7:0]  seg,              // {dp, g, f, e, d, c, b, a}
    output reg  [7:0]  an                // one low per active digit
);
    localparam integer DIVISOR = CLK_HZ / (REFRESH_HZ * 8);

    reg [19:0] tick = 20'd0;
    reg [2:0]  digit = 3'd0;

    always @(posedge clk) begin
        if (rst) begin
            tick  <= 20'd0;
            digit <= 3'd0;
        end else if (tick == DIVISOR[19:0] - 1) begin
            tick  <= 20'd0;
            digit <= digit + 3'd1;
        end else begin
            tick <= tick + 20'd1;
        end
    end

    reg [3:0] nibble;
    always @* begin
        case (digit)
            3'd0: nibble = value[3:0];
            3'd1: nibble = value[7:4];
            3'd2: nibble = value[11:8];
            3'd3: nibble = value[15:12];
            3'd4: nibble = value[19:16];
            3'd5: nibble = value[23:20];
            3'd6: nibble = value[27:24];
            default: nibble = value[31:28];
        endcase
    end

    reg [6:0] segments;
    always @* begin
        case (nibble)                    //       gfedcba
            4'h0: segments = 7'b0111111;
            4'h1: segments = 7'b0000110;
            4'h2: segments = 7'b1011011;
            4'h3: segments = 7'b1001111;
            4'h4: segments = 7'b1100110;
            4'h5: segments = 7'b1101101;
            4'h6: segments = 7'b1111101;
            4'h7: segments = 7'b0000111;
            4'h8: segments = 7'b1111111;
            4'h9: segments = 7'b1101111;
            4'hA: segments = 7'b1110111;
            4'hB: segments = 7'b1111100;
            4'hC: segments = 7'b0111001;
            4'hD: segments = 7'b1011110;
            4'hE: segments = 7'b1111001;
            default: segments = 7'b1110001;
        endcase
    end

    always @(posedge clk) begin
        seg <= ACTIVE_LOW ? ~{dp[digit], segments} : {dp[digit], segments};
        an  <= ACTIVE_LOW ? ~(8'd1 << digit) : (8'd1 << digit);
    end
endmodule

`default_nettype wire
