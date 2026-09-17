// One bank of the 3D LUT: 729 x 24 bits, single port, registered output.
//
// Eight of these make up the LUT (design.md section 5).  Each is 17,496 bits,
// which fits a single BRAM18 -- so the whole 17^3 LUT costs 8 BRAM18 = 4
// BRAM36 out of the 75 on the device.
//
// Declared as a separate module rather than as `reg [23:0] bank [0:7][0:728]`
// because two-dimensional unpacked arrays of memories are exactly where BRAM
// inference goes sideways: Vivado will sometimes produce distributed RAM, and
// 8 x 729 x 24 bits of LUTRAM will not fit anything sensible.  One module, one
// array, one `ram_style` attribute, eight instances.

`default_nettype none

module lut_bank #(
    parameter INIT_FILE = "",   // empty means "leave the bank black"
    parameter DEPTH     = 729
)(
    input  wire        clk,
    input  wire [9:0]  addr,
    output reg  [23:0] q
);
    (* ram_style = "block" *) reg [23:0] mem [0:DEPTH-1];

    integer i;
    initial begin
        // Default to black so an unloaded LUT is obviously wrong rather than
        // full of X, which propagates and hides the real problem.
        for (i = 0; i < DEPTH; i = i + 1) mem[i] = 24'h000000;
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    always @(posedge clk)
        q <= mem[addr];
endmodule

`default_nettype wire
