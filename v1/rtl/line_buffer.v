// Three-row line buffer (design.md section 9.7).
//
// Sobel needs three scanlines; the whole pipeline is streaming, so nothing is
// stored longer than that.  At 720p a 24-bit line is 1280 x 24 = 30.7 kbit,
// so the two buffers cost 2 BRAM36 of the 75 on the device.
//
// ## Why this does not take an `x` input
//
// The design document's version addresses both buffers with the incoming `x`
// and writes the second one with the value read from the first:
//
//     q0 <= buf0[x];  buf0[x] <= din;
//     q1 <= buf1[x];  buf1[x] <= q0;      // <-- writes last cycle's value
//
// and then notes the resulting one-column skew as something to correct with an
// offset address.  Rather than carrying that fix-up around, each line delay
// here is a self-contained FIFO addressed by its own counter which advances
// only while its enable is high.  After exactly one active line the counter
// wraps, so the value read back *is* the pixel from the line above, with no
// skew to correct.
//
// Row alignment is then just latency matching: the second delay is fed a cycle
// after the first, so its enable and its output are a cycle later, and rows 1
// and 2 are re-registered to line up with row 0.  All three outputs present
// the same column, LATENCY cycles after the pixel entered.

`default_nettype none

module line_delay #(
    parameter WIDTH = 24,
    parameter MAX_X = 1920
)(
    input  wire             clk,
    input  wire             rst,
    input  wire             en,        // advance only during active video
    input  wire [11:0]      line_len,  // active pixels per line
    input  wire [WIDTH-1:0] din,
    output reg  [WIDTH-1:0] dout
);
    (* ram_style = "block" *) reg [WIDTH-1:0] mem [0:MAX_X-1];
    reg [11:0] addr = 12'd0;

    always @(posedge clk) begin
        if (rst) begin
            addr <= 12'd0;
            dout <= {WIDTH{1'b0}};
        end else if (en) begin
            // Read before write: the old contents are exactly one line old.
            dout      <= mem[addr];
            mem[addr] <= din;
            addr      <= (addr == line_len - 12'd1) ? 12'd0 : addr + 12'd1;
        end
    end
endmodule

module line_buffer #(
    parameter WIDTH = 24,
    parameter MAX_X = 1920
)(
    input  wire             clk,
    input  wire             rst,
    input  wire             de,
    input  wire [11:0]      line_len,
    input  wire [WIDTH-1:0] din,
    output wire [WIDTH-1:0] row0,      // two lines above
    output wire [WIDTH-1:0] row1,      // one line above
    output wire [WIDTH-1:0] row2,      // current line
    output wire             valid      // all three rows aligned
);
    localparam LATENCY = 2;

    // de follows the data through the delays.
    reg de_d1 = 1'b0, de_d2 = 1'b0;
    always @(posedge clk) begin
        if (rst) begin
            de_d1 <= 1'b0;
            de_d2 <= 1'b0;
        end else begin
            de_d1 <= de;
            de_d2 <= de_d1;
        end
    end

    wire [WIDTH-1:0] d1, d2;

    line_delay #(.WIDTH(WIDTH), .MAX_X(MAX_X)) u_l1 (
        .clk (clk), .rst (rst), .en (de), .line_len (line_len),
        .din (din), .dout (d1)
    );

    line_delay #(.WIDTH(WIDTH), .MAX_X(MAX_X)) u_l2 (
        .clk (clk), .rst (rst), .en (de_d1), .line_len (line_len),
        .din (d1), .dout (d2)
    );

    // Re-register the newer rows so all three present the same column.
    reg [WIDTH-1:0] row2_d1 = {WIDTH{1'b0}};
    reg [WIDTH-1:0] row2_d2 = {WIDTH{1'b0}};
    reg [WIDTH-1:0] row1_d1 = {WIDTH{1'b0}};

    always @(posedge clk) begin
        if (de)    row2_d1 <= din;
        if (de_d1) row2_d2 <= row2_d1;
        if (de_d1) row1_d1 <= d1;
    end

    assign row0  = d2;
    assign row1  = row1_d1;
    assign row2  = row2_d2;
    assign valid = de_d2;
endmodule

`default_nettype wire
