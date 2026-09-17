// Behavioural models of the Xilinx primitives this design instantiates.
//
// **For simulation only.**  Vivado uses the real primitives; these exist so the
// whole transmitter can be simulated in Icarus Verilog, where the vendor
// libraries are not available.  They model the *documented behaviour* of each
// primitive (UG471, UG472), not its internals, and deliberately do not model
// timing, jitter or the SERDES reset sequence.
//
// The one behaviour that matters and is easy to get wrong is the OSERDESE2
// master/slave cascade: the master carries bits 0-7 on D1-D8, and the slave
// carries bits 8 and 9 on **D3 and D4**, which looks arbitrary and is the
// documented arrangement.  Output is LSB first.

`timescale 1ns/1ps

// ---------------------------------------------------------------- OSERDESE2

module OSERDESE2 #(
    parameter DATA_RATE_OQ   = "DDR",
    parameter DATA_RATE_TQ   = "SDR",
    parameter DATA_WIDTH     = 10,
    parameter SERDES_MODE    = "MASTER",
    parameter TRISTATE_WIDTH = 1,
    parameter TBYTE_CTL      = "FALSE",
    parameter TBYTE_SRC      = "FALSE",
    parameter INIT_OQ        = 1'b0,
    parameter INIT_TQ        = 1'b0,
    parameter SRVAL_OQ       = 1'b0,
    parameter SRVAL_TQ       = 1'b0
)(
    output reg  OQ,
    output wire OFB,
    output wire TQ,
    output wire TFB,
    output wire TBYTEOUT,
    output wire SHIFTOUT1,
    output wire SHIFTOUT2,
    input  wire CLK,
    input  wire CLKDIV,
    input  wire D1, D2, D3, D4, D5, D6, D7, D8,
    input  wire OCE,
    input  wire TCE,
    input  wire RST,
    input  wire SHIFTIN1,
    input  wire SHIFTIN2,
    input  wire T1, T2, T3, T4,
    input  wire TBYTEIN
);
    // The master's shift register holds the full 10-bit word: its own eight
    // bits plus the two shifted in from the slave.
    reg [9:0] shifter = 10'd0;
    reg [9:0] load    = 10'd0;
    integer   phase   = 0;

    wire [7:0] d = {D8, D7, D6, D5, D4, D3, D2, D1};

    assign SHIFTOUT1 = D3;      // slave contributes bits 8 and 9
    assign SHIFTOUT2 = D4;
    assign OFB = OQ;
    assign TQ = 1'b0;
    assign TFB = 1'b0;
    assign TBYTEOUT = 1'b0;

    generate
    if (SERDES_MODE == "MASTER") begin : g_master
        // Capture a new word on the slow clock.
        always @(posedge CLKDIV) begin
            if (RST) load <= 10'd0;
            else if (OCE) load <= {SHIFTIN2, SHIFTIN1, d};
        end

        // Shift out LSB first, two bits per CLK period (DDR).
        always @(posedge CLK) begin
            if (RST) begin
                OQ      <= 1'b0;
                shifter <= 10'd0;
                phase   <= 0;
            end else begin
                if (phase == 0) begin
                    OQ      <= load[0];
                    shifter <= {1'b0, load[9:1]};
                end else begin
                    OQ      <= shifter[0];
                    shifter <= {1'b0, shifter[9:1]};
                end
                phase <= (phase == (DATA_WIDTH / 2) - 1) ? 0 : phase + 1;
            end
        end

        always @(negedge CLK) begin
            if (!RST) begin
                OQ      <= shifter[0];
                shifter <= {1'b0, shifter[9:1]};
            end
        end
    end else begin : g_slave
        // The slave contributes data through SHIFTOUT only; its OQ is unused.
        always @(posedge CLK) OQ <= 1'b0;
    end
    endgenerate
endmodule

// ------------------------------------------------------------------- OBUFDS

module OBUFDS #(
    parameter IOSTANDARD = "TMDS_33",
    parameter SLEW = "FAST"
)(
    output wire O,
    output wire OB,
    input  wire I
);
    assign O  = I;
    assign OB = ~I;
endmodule

// ---------------------------------------------------------------- BUFG/BUFIO

module BUFG (output wire O, input wire I);
    assign O = I;
endmodule

module BUFIO (output wire O, input wire I);
    assign O = I;
endmodule

module BUFR #(parameter BUFR_DIVIDE = "BYPASS", parameter SIM_DEVICE = "7SERIES")
    (output wire O, input wire I, input wire CE, input wire CLR);
    assign O = I;
endmodule

// -------------------------------------------------------------- MMCME2_BASE
//
// Models frequency synthesis only: CLKOUT0 and CLKOUT1 are generated from
// CLKIN1 using the M/D/divide parameters, and LOCKED asserts after a delay.
// Phase relationships between outputs are exact here; on hardware they are
// exact too *provided both clocks come from the same MMCM*, which is the
// reason clocking.v instantiates only one.

module MMCME2_BASE #(
    parameter BANDWIDTH = "OPTIMIZED",
    parameter real CLKFBOUT_MULT_F = 5.000,
    parameter real CLKFBOUT_PHASE = 0.000,
    parameter real CLKIN1_PERIOD = 10.000,
    parameter real CLKOUT0_DIVIDE_F = 1.000,
    parameter integer CLKOUT1_DIVIDE = 1,
    parameter integer CLKOUT2_DIVIDE = 1,
    parameter real CLKOUT0_DUTY_CYCLE = 0.5,
    parameter real CLKOUT1_DUTY_CYCLE = 0.5,
    parameter real CLKOUT0_PHASE = 0.0,
    parameter real CLKOUT1_PHASE = 0.0,
    parameter integer DIVCLK_DIVIDE = 1,
    parameter real REF_JITTER1 = 0.010,
    parameter STARTUP_WAIT = "FALSE"
)(
    output wire CLKOUT0, output wire CLKOUT0B,
    output wire CLKOUT1, output wire CLKOUT1B,
    output wire CLKOUT2, output wire CLKOUT2B,
    output wire CLKOUT3, output wire CLKOUT3B,
    output wire CLKOUT4, output wire CLKOUT5, output wire CLKOUT6,
    output wire CLKFBOUT, output wire CLKFBOUTB,
    output reg  LOCKED,
    input  wire CLKIN1,
    input  wire CLKFBIN,
    input  wire PWRDWN,
    input  wire RST
);
    real vco_period = CLKIN1_PERIOD * DIVCLK_DIVIDE / CLKFBOUT_MULT_F;
    real half0, half1;

    reg clk0 = 1'b0;
    reg clk1 = 1'b0;

    initial begin
        half0 = vco_period * CLKOUT0_DIVIDE_F / 2.0;
        half1 = vco_period * CLKOUT1_DIVIDE / 2.0;
        LOCKED = 1'b0;
        // A real MMCM takes ~100 us to lock; scale that down so simulations
        // are not dominated by it, but keep it non-zero so designs that ignore
        // LOCKED are caught.
        #1000 LOCKED = 1'b1;
    end

    always #(half0) clk0 = ~clk0;
    always #(half1) clk1 = ~clk1;

    always @(posedge RST) begin
        if (RST) LOCKED <= 1'b0;
    end

    assign CLKOUT0 = clk0;
    assign CLKOUT1 = clk1;
    assign CLKOUT0B = ~clk0;
    assign CLKOUT1B = ~clk1;
    assign CLKOUT2 = 1'b0; assign CLKOUT2B = 1'b1;
    assign CLKOUT3 = 1'b0; assign CLKOUT3B = 1'b1;
    assign CLKOUT4 = 1'b0; assign CLKOUT5 = 1'b0; assign CLKOUT6 = 1'b0;
    assign CLKFBOUT = CLKIN1;
    assign CLKFBOUTB = ~CLKIN1;
endmodule
