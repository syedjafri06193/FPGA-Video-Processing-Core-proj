// TMDS encoder -- DVI 1.0 section 3.2.2 (design.md section 9.2).
//
// Stage 1 minimises transitions by XOR or XNOR chaining.  Stage 2 keeps the
// serial stream DC balanced using a running disparity counter, inverting words
// when the disparity would otherwise run away.  During blanking the encoder
// emits one of four fixed control tokens, which are deliberately
// transition-*rich* so the receiver can find word boundaries.
//
// **The critical timing path in the whole design lives in this module** --
// the `cnt` feedback loop runs combinationally from a register, through
// comparators and adders, back to the same register (design.md section 11).
//
// So stage 1 is registered separately: `q_m` and the population counts depend
// only on `din`, never on `cnt`, so computing them a cycle earlier is free
// functionally and halves the depth of the feedback path.  That costs one
// cycle of latency -- irrelevant, and `LATENCY` below is what the rest of the
// design uses to stay aligned.

`default_nettype none

`include "video_modes.vh"

module tmds_encoder (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] din,     // pixel data for this channel
    input  wire [1:0] ctrl,    // {C1, C0} -- only used while de is low
    input  wire       de,
    output reg  [9:0] dout
);
    // Total latency from din to dout, in clk cycles.  Used by dvi_tx to keep
    // the three channels aligned with each other.
    localparam LATENCY = 2;

    // ---------------- stage 1: transition minimisation (no cnt dependency) --

    wire [3:0] n1d = din[0] + din[1] + din[2] + din[3]
                   + din[4] + din[5] + din[6] + din[7];

    // XNOR when the input has many ones, or exactly four ones and a zero LSB.
    wire use_xnor = (n1d > 4'd4) || ((n1d == 4'd4) && (din[0] == 1'b0));

    wire [8:0] qm;
    assign qm[0] = din[0];
    genvar i;
    generate
        for (i = 1; i < 8; i = i + 1) begin : g_qm
            assign qm[i] = use_xnor ? ~(qm[i-1] ^ din[i])
                                    :  (qm[i-1] ^ din[i]);
        end
    endgenerate
    assign qm[8] = ~use_xnor;   // 1 = XOR was used, 0 = XNOR

    wire [3:0] n1q_c = qm[0] + qm[1] + qm[2] + qm[3]
                     + qm[4] + qm[5] + qm[6] + qm[7];

    reg [8:0] qm_r;
    reg [3:0] n1q_r;
    reg [1:0] ctrl_r;
    reg       de_r;

    always @(posedge clk) begin
        if (rst) begin
            qm_r   <= 9'd0;
            n1q_r  <= 4'd0;
            ctrl_r <= 2'b00;
            de_r   <= 1'b0;
        end else begin
            qm_r   <= qm;
            n1q_r  <= n1q_c;
            ctrl_r <= ctrl;
            de_r   <= de;
        end
    end

    // ---------------- stage 2: DC balancing --------------------------------

    wire [3:0] n0q = 4'd8 - n1q_r;

    // (ones - zeros) and its negation, as signed values.
    wire signed [5:0] diff_1m0 = $signed({2'b0, n1q_r}) - $signed({2'b0, n0q});
    wire signed [5:0] diff_0m1 = -diff_1m0;

    reg signed [5:0] cnt;   // running disparity

    wire balanced = (cnt == 0) || (n1q_r == n0q);
    wire invert   = ((cnt > 0) && (n1q_r > n0q)) || ((cnt < 0) && (n0q > n1q_r));

    always @(posedge clk) begin
        if (rst) begin
            cnt  <= 6'sd0;
            dout <= `TMDS_CTRL_00;
        end else if (!de_r) begin
            // Disparity resets during blanking; the control tokens are
            // DC balanced by construction.
            cnt <= 6'sd0;
            case (ctrl_r)
                2'b00:   dout <= `TMDS_CTRL_00;
                2'b01:   dout <= `TMDS_CTRL_01;
                2'b10:   dout <= `TMDS_CTRL_10;
                default: dout <= `TMDS_CTRL_11;
            endcase
        end else if (balanced) begin
            dout[9]   <= ~qm_r[8];
            dout[8]   <=  qm_r[8];
            dout[7:0] <=  qm_r[8] ? qm_r[7:0] : ~qm_r[7:0];
            cnt       <=  qm_r[8] ? cnt + diff_1m0 : cnt + diff_0m1;
        end else if (invert) begin
            dout[9]   <= 1'b1;
            dout[8]   <= qm_r[8];
            dout[7:0] <= ~qm_r[7:0];
            cnt       <= cnt + {qm_r[8], 1'b0} + diff_0m1;   // + 2*qm[8]
        end else begin
            dout[9]   <= 1'b0;
            dout[8]   <= qm_r[8];
            dout[7:0] <= qm_r[7:0];
            cnt       <= cnt - {~qm_r[8], 1'b0} + diff_1m0;  // - 2*(~qm[8])
        end
    end

`ifdef SIM_ASSERTS
    // The DVI spec's own guarantees.  A broken encoder produces a black screen
    // and nothing else, so checking these in simulation is the only cheap way
    // to know the encoder is right (design.md section 10.4).
    integer t;
    integer transitions;
    reg [9:0] prev_word;
    always @(posedge clk) begin
        if (!rst && de_r) begin
            transitions = 0;
            for (t = 0; t < 9; t = t + 1)
                if (dout[t] !== dout[t+1]) transitions = transitions + 1;
            if (transitions > 5)
                $error("TMDS: %0d transitions in %b (limit 5)", transitions, dout);
            if (cnt > 6'sd8 || cnt < -6'sd8)
                $error("TMDS: running disparity %0d out of bounds", cnt);
        end
    end
`endif
endmodule

`default_nettype wire
