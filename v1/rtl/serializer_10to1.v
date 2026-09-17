// 10:1 output serializer (design.md section 9.3).
//
// OSERDESE2 maxes out at 8:1 on its own, so a master and a slave are cascaded
// to reach 10:1.  The master carries bits 0-7; the slave carries bits 8 and 9
// on D3/D4 and passes them to the master through SHIFTOUT1/2.  That D3/D4
// arrangement looks arbitrary and is exactly what UG471 documents.
//
// Serial order is **LSB first** -- data[0] leaves first.  If the picture comes
// up as coherent-but-wrong noise, bit order and channel order are the first
// two things to check (section 12.1).
//
// At 720p60 this runs at 371.25 MHz on CLK with 742.5 Mb/s on the pin: inside
// the -1 speed grade's 464 MHz BUFG and 950 Mb/s OSERDES limits, with real
// margin.  1080p60 would need 742.5 MHz and 1485 Mb/s, which no clock buffer
// on the device can carry -- see section 2.2.

`default_nettype none

module serializer_10to1 (
    input  wire       clk_pix,   // 74.25 MHz  (CLKDIV)
    input  wire       clk_5x,    // 371.25 MHz (CLK)
    input  wire       rst,
    input  wire [9:0] data,
    output wire       out_p,
    output wire       out_n
);
    wire shift1, shift2, ser;

    OSERDESE2 #(
        .DATA_RATE_OQ   ("DDR"),
        .DATA_RATE_TQ   ("SDR"),
        .DATA_WIDTH     (10),
        .SERDES_MODE    ("MASTER"),
        .TRISTATE_WIDTH (1),
        .TBYTE_CTL      ("FALSE"),
        .TBYTE_SRC      ("FALSE")
    ) u_master (
        .OQ        (ser),
        .OFB       (), .TQ (), .TFB (), .TBYTEOUT (),
        .SHIFTOUT1 (), .SHIFTOUT2 (),
        .CLK       (clk_5x),
        .CLKDIV    (clk_pix),
        .D1 (data[0]), .D2 (data[1]), .D3 (data[2]), .D4 (data[3]),
        .D5 (data[4]), .D6 (data[5]), .D7 (data[6]), .D8 (data[7]),
        .OCE (1'b1), .TCE (1'b0), .RST (rst),
        .SHIFTIN1 (shift1), .SHIFTIN2 (shift2),
        .T1 (1'b0), .T2 (1'b0), .T3 (1'b0), .T4 (1'b0),
        .TBYTEIN (1'b0)
    );

    OSERDESE2 #(
        .DATA_RATE_OQ   ("DDR"),
        .DATA_RATE_TQ   ("SDR"),
        .DATA_WIDTH     (10),
        .SERDES_MODE    ("SLAVE"),
        .TRISTATE_WIDTH (1),
        .TBYTE_CTL      ("FALSE"),
        .TBYTE_SRC      ("FALSE")
    ) u_slave (
        .OQ        (), .OFB (), .TQ (), .TFB (), .TBYTEOUT (),
        .SHIFTOUT1 (shift1), .SHIFTOUT2 (shift2),
        .CLK       (clk_5x),
        .CLKDIV    (clk_pix),
        .D1 (1'b0),    .D2 (1'b0),
        .D3 (data[8]), .D4 (data[9]),
        .D5 (1'b0), .D6 (1'b0), .D7 (1'b0), .D8 (1'b0),
        .OCE (1'b1), .TCE (1'b0), .RST (rst),
        .SHIFTIN1 (1'b0), .SHIFTIN2 (1'b0),
        .T1 (1'b0), .T2 (1'b0), .T3 (1'b0), .T4 (1'b0),
        .TBYTEIN (1'b0)
    );

    // Nothing may sit between the OSERDESE2 and the OBUFDS -- the placer puts
    // the serializer in the I/O tile, and any logic here breaks that.
    OBUFDS #(.IOSTANDARD("TMDS_33")) u_obuf (
        .I (ser), .O (out_p), .OB (out_n)
    );
endmodule

`default_nettype wire
