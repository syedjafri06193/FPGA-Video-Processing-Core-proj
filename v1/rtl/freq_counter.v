// Measure one clock with another (design.md section 12.1, step 2).
//
// "Is the pixel clock the frequency you think it is?" is the second question
// in the black-screen playbook, and a wrong MMCM setting is common and silent.
// This counts clk_meas edges over a known number of clk_ref edges and presents
// the result in the reference domain, ready for the seven-segment display.
//
// The crossing is a toggle plus two synchronisers -- the only real CDC in the
// design, and it is deliberately the easy kind: one bit, slow, and with a
// handshake implied by the gate window rather than by data validity.

`default_nettype none

module freq_counter #(
    parameter REF_HZ = 100_000_000      // clk_ref frequency
)(
    input  wire        clk_ref,
    input  wire        rst_ref,
    input  wire        clk_meas,
    output reg  [31:0] hz               // measured frequency, in clk_ref domain
);
    // One-second gate.
    reg [31:0] ref_count = 32'd0;
    reg        gate = 1'b0;

    always @(posedge clk_ref) begin
        if (rst_ref) begin
            ref_count <= 32'd0;
            gate      <= 1'b0;
        end else if (ref_count == REF_HZ - 1) begin
            ref_count <= 32'd0;
            gate      <= ~gate;         // toggles once per second
        end else begin
            ref_count <= ref_count + 32'd1;
        end
    end

    // Cross the gate into the measured domain.
    (* ASYNC_REG = "TRUE" *) reg gate_meta = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg gate_sync = 1'b0;
    reg gate_prev = 1'b0;
    reg [31:0] meas_count = 32'd0;
    reg [31:0] meas_hold  = 32'd0;

    always @(posedge clk_meas) begin
        gate_meta <= gate;
        gate_sync <= gate_meta;
        gate_prev <= gate_sync;

        if (gate_sync != gate_prev) begin
            meas_hold  <= meas_count;   // one second's worth of edges
            meas_count <= 32'd1;
        end else begin
            meas_count <= meas_count + 32'd1;
        end
    end

    // And the result back again.  meas_hold is stable between gate edges, so
    // sampling it with two flops is safe.
    (* ASYNC_REG = "TRUE" *) reg [31:0] hz_meta = 32'd0;
    always @(posedge clk_ref) begin
        hz_meta <= meas_hold;
        hz      <= hz_meta;
    end
endmodule

`default_nettype wire
