// Runtime control: switches, buttons and UART (design.md section 8, M8).
//
// Protocol, deliberately trivial: each command is two bytes, a register
// address and a value.  Sending `01 40` sets the threshold to 0x40.
//
//   0x00  mode        [1:0]
//   0x01  threshold   [7:0]
//   0x02  flags       bit0 lut_bypass, bit1 glow, bit2 freeze
//   0x03  pattern     [2:0]
//   0x04  source      bit0 = 1 selects UART control, 0 returns to the switches
//
// The switches win until a UART command says otherwise, so the board is usable
// with nothing plugged into it, and a demo can still be driven from a laptop.
//
// Everything here is in the pixel clock domain.  The UART receiver runs in the
// same domain, so there is no crossing to get wrong -- the only reason that is
// affordable is that the UART is slow relative to the pixel clock, not fast.

`default_nettype none

`include "video_modes.vh"

module ctrl_regs (
    input  wire        clk,
    input  wire        rst,

    input  wire [15:0] sw,
    input  wire [3:0]  btn,

    input  wire [7:0]  uart_data,
    input  wire        uart_valid,

    output wire [1:0]  mode,
    output wire [7:0]  threshold,
    output wire        lut_bypass,
    output wire        glow,
    output wire        freeze,
    output wire [2:0]  pattern_sel,
    output reg  [2:0]  lut_select,
    output reg         uart_control
);
    reg [1:0] r_mode      = `MODE_OVERLAY;
    reg [7:0] r_threshold = 8'd64;
    reg [2:0] r_flags     = 3'b000;
    reg [2:0] r_pattern   = 3'd2;

    reg       expect_value = 1'b0;
    reg [7:0] reg_addr     = 8'd0;

    always @(posedge clk) begin
        if (rst) begin
            expect_value <= 1'b0;
            uart_control <= 1'b0;
            lut_select   <= 3'd0;
            r_mode       <= `MODE_OVERLAY;
            r_threshold  <= 8'd64;
            r_flags      <= 3'b000;
            r_pattern    <= 3'd2;
        end else if (uart_valid) begin
            if (!expect_value) begin
                reg_addr     <= uart_data;
                expect_value <= 1'b1;
            end else begin
                expect_value <= 1'b0;
                case (reg_addr)
                    8'h00: begin r_mode      <= uart_data[1:0]; uart_control <= 1'b1; end
                    8'h01: begin r_threshold <= uart_data;      uart_control <= 1'b1; end
                    8'h02: begin r_flags     <= uart_data[2:0]; uart_control <= 1'b1; end
                    8'h03: begin r_pattern   <= uart_data[2:0]; uart_control <= 1'b1; end
                    8'h04: uart_control <= uart_data[0];
                    8'h05: lut_select   <= uart_data[2:0];
                    default: ;   // unknown register: ignored, not latched
                endcase
            end
        end
    end

    // Switch map, chosen so the useful demo controls are under your thumb:
    //   sw[1:0]  mode          sw[2] LUT bypass   sw[3] glow overlay
    //   sw[6:4]  pattern       sw[7] freeze       sw[15:8] threshold
    assign mode        = uart_control ? r_mode      : sw[1:0];
    assign lut_bypass  = uart_control ? r_flags[0]  : sw[2];
    assign glow        = uart_control ? r_flags[1]  : sw[3];
    assign pattern_sel = uart_control ? r_pattern   : sw[6:4];
    assign freeze      = uart_control ? r_flags[2]  : sw[7];

    // btn[0] forces the threshold to a known mid value, which is the fastest
    // way to get a sane picture back after turning the switches into nonsense.
    assign threshold = btn[0] ? 8'd64
                              : (uart_control ? r_threshold : sw[15:8]);
endmodule

`default_nettype wire
