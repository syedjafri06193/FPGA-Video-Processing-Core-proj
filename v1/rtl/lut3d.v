// 17^3 3D LUT with trilinear interpolation (design.md section 9.6).
//
// Indexing is exact for 8-bit input: index = pixel[7:4] (0..15), fraction =
// pixel[3:0] (0..15).  Node i represents input value 16*i, and node 16
// represents 256 -- stored as 255, which is the only place the LUT is not
// mathematically exact (worst case 1 LSB, only for inputs above 240).
//
// ## The 8-bank scheme, and a correction to the design document
//
// The eight cube corners are (r+a, g+b, b+c) for a,b,c in {0,1}.  Adding one
// flips the LSB, so the eight corners always land in eight different banks:
//
//     bank = {R[0], G[0], B[0]}
//
// That part is right, and it is what makes a single-cycle 8-corner read
// possible from single-port BRAMs.
//
// The design document then says "all eight banks receive the *same* address".
// **That is only true when all three indices are even.**  The address of a
// corner is
//
//     addr = (R >> 1)*81 + (G >> 1)*9 + (B >> 1)
//
// and when R is odd, (R+1) >> 1 is (R >> 1) + 1 -- a different row.  Feeding
// every bank the same address reads the wrong corner on roughly 7 of every 8
// pixels, which shows up as vertical banding in the output (section 12.2).
//
// The fix is small and costs nothing: each bank's address is the base address
// plus a per-axis carry that depends only on that bank's parity bit and the
// index's LSB.  For bank parity bit `pr` on the red axis:
//
//     carry_r = R[0] & ~pr        // odd index, and this bank holds the +1 side
//
// so the address is base + 81*carry_r + 9*carry_g + carry_b.  Eight small
// adders on a shared base.  tb_lut3d proves the result against the Python
// model over every input the identity LUT can distinguish.

`default_nettype none

module lut3d #(
    parameter LUT0 = "",
    parameter LUT1 = "",
    parameter LUT2 = "",
    parameter LUT3 = "",
    parameter LUT4 = "",
    parameter LUT5 = "",
    parameter LUT6 = "",
    parameter LUT7 = ""
)(
    input  wire        clk,
    input  wire [23:0] px_in,      // {R, G, B}
    output wire [23:0] px_out
);
    // 1 address + 1 BRAM + 1 permute + 3 lerp stages.  Everything parallel to
    // this module must be delayed by exactly this much.
    localparam LATENCY = 6;

    wire [3:0] ri = px_in[23:20], rf = px_in[19:16];
    wire [3:0] gi = px_in[15:12], gf = px_in[11:8];
    wire [3:0] bi = px_in[7:4],   bf = px_in[3:0];

    // ---- stage 1: base address, parity, per-bank carries -------------------
    // ri[3:1] is 0..7; the +1 corner can reach 8, which is why the address is
    // 10 bits (max 8*81 + 8*9 + 8 = 728).
    wire [9:0] base = {4'b0, ri[3:1]} * 10'd81
                    + {4'b0, gi[3:1]} * 10'd9
                    + {7'b0, bi[3:1]};

    reg [9:0] base_r;
    reg [2:0] parity_r;      // {ri[0], gi[0], bi[0]}
    reg [2:0] odd_r;         // same bits, kept separately for readability

    always @(posedge clk) begin
        base_r   <= base;
        parity_r <= {ri[0], gi[0], bi[0]};
        odd_r    <= {ri[0], gi[0], bi[0]};
    end

    // ---- stage 2: eight parallel reads, one per bank ----------------------
    wire [23:0] q [0:7];
    wire [9:0]  addr [0:7];

    genvar k;
    generate
        for (k = 0; k < 8; k = k + 1) begin : g_bank
            // Bank k holds corners whose parity is k.  It reads the +1 corner
            // on an axis exactly when that axis index is odd and this bank
            // sits on the even side of it.
            wire carry_r = odd_r[2] & (((k >> 2) & 1) == 0);
            wire carry_g = odd_r[1] & (((k >> 1) & 1) == 0);
            wire carry_b = odd_r[0] & (((k >> 0) & 1) == 0);
            assign addr[k] = base_r
                           + (carry_r ? 10'd81 : 10'd0)
                           + (carry_g ? 10'd9  : 10'd0)
                           + (carry_b ? 10'd1  : 10'd0);
        end
    endgenerate

    lut_bank #(.INIT_FILE(LUT0)) u_b0 (.clk(clk), .addr(addr[0]), .q(q[0]));
    lut_bank #(.INIT_FILE(LUT1)) u_b1 (.clk(clk), .addr(addr[1]), .q(q[1]));
    lut_bank #(.INIT_FILE(LUT2)) u_b2 (.clk(clk), .addr(addr[2]), .q(q[2]));
    lut_bank #(.INIT_FILE(LUT3)) u_b3 (.clk(clk), .addr(addr[3]), .q(q[3]));
    lut_bank #(.INIT_FILE(LUT4)) u_b4 (.clk(clk), .addr(addr[4]), .q(q[4]));
    lut_bank #(.INIT_FILE(LUT5)) u_b5 (.clk(clk), .addr(addr[5]), .q(q[5]));
    lut_bank #(.INIT_FILE(LUT6)) u_b6 (.clk(clk), .addr(addr[6]), .q(q[6]));
    lut_bank #(.INIT_FILE(LUT7)) u_b7 (.clk(clk), .addr(addr[7]), .q(q[7]));

    // ---- stage 3: permute banks into cube corners -------------------------
    // Corner (a,b,c) lives in bank {ri[0]^a, gi[0]^b, bi[0]^c}.
    //
    // The parity used here must belong to the pixel whose bank outputs are
    // arriving *now*, which is one cycle older than `parity_r`: that register
    // already holds the next pixel's parity, because the BRAM read sits
    // between them.  Using `parity_r` directly permutes each pixel's corners
    // with its successor's parity, which is correct only when consecutive
    // pixels happen to share parity -- so it passes on flat colour and fails
    // on every gradient.  Delaying it by one is the whole fix.
    reg [2:0] parity_q;
    always @(posedge clk) parity_q <= parity_r;

    wire [2:0] p = parity_q;
    reg [23:0] c000, c001, c010, c011, c100, c101, c110, c111;

    always @(posedge clk) begin
        c000 <= q[{p[2] ^ 1'b0, p[1] ^ 1'b0, p[0] ^ 1'b0}];
        c001 <= q[{p[2] ^ 1'b0, p[1] ^ 1'b0, p[0] ^ 1'b1}];
        c010 <= q[{p[2] ^ 1'b0, p[1] ^ 1'b1, p[0] ^ 1'b0}];
        c011 <= q[{p[2] ^ 1'b0, p[1] ^ 1'b1, p[0] ^ 1'b1}];
        c100 <= q[{p[2] ^ 1'b1, p[1] ^ 1'b0, p[0] ^ 1'b0}];
        c101 <= q[{p[2] ^ 1'b1, p[1] ^ 1'b0, p[0] ^ 1'b1}];
        c110 <= q[{p[2] ^ 1'b1, p[1] ^ 1'b1, p[0] ^ 1'b0}];
        c111 <= q[{p[2] ^ 1'b1, p[1] ^ 1'b1, p[0] ^ 1'b1}];
    end

    // ---- stages 4-6: the 7-lerp tree, B then G then R ---------------------
    // The order matters at the LSB, because every stage truncates.  The Python
    // model interpolates in the same order for the same reason.
    wire [3:0] bf_d3, gf_d4, rf_d5;
    delay_line #(.WIDTH(4), .DEPTH(3)) u_dbf (.clk(clk), .din(bf), .dout(bf_d3));
    delay_line #(.WIDTH(4), .DEPTH(4)) u_dgf (.clk(clk), .din(gf), .dout(gf_d4));
    delay_line #(.WIDTH(4), .DEPTH(5)) u_drf (.clk(clk), .din(rf), .dout(rf_d5));

    wire [23:0] l00, l01, l10, l11, m0, m1;

    lerp_rgb u_l00 (.clk(clk), .a(c000), .b(c001), .f(bf_d3), .y(l00));
    lerp_rgb u_l01 (.clk(clk), .a(c010), .b(c011), .f(bf_d3), .y(l01));
    lerp_rgb u_l10 (.clk(clk), .a(c100), .b(c101), .f(bf_d3), .y(l10));
    lerp_rgb u_l11 (.clk(clk), .a(c110), .b(c111), .f(bf_d3), .y(l11));

    lerp_rgb u_m0 (.clk(clk), .a(l00), .b(l01), .f(gf_d4), .y(m0));
    lerp_rgb u_m1 (.clk(clk), .a(l10), .b(l11), .f(gf_d4), .y(m1));

    lerp_rgb u_out (.clk(clk), .a(m0), .b(m1), .f(rf_d5), .y(px_out));
endmodule

`default_nettype wire
