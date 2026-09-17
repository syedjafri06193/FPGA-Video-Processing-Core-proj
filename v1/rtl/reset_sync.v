// Asynchronous assert, synchronous de-assert reset synchronizer.
//
// The video path has exactly two clock domains and no data CDC (design.md
// section 3.2) -- but reset still crosses into both, and releasing a reset
// asynchronously is how you get half a pipeline starting a cycle before the
// other half.  Two flops per domain, asserted immediately, released in step
// with that domain's clock.

`default_nettype none

module reset_sync #(
    parameter STAGES = 3
)(
    input  wire clk,
    input  wire async_rst_n,   // active low: tie to MMCM locked
    output wire rst            // active high, synchronous de-assert
);
    (* ASYNC_REG = "TRUE" *) reg [STAGES-1:0] sync = {STAGES{1'b1}};

    always @(posedge clk or negedge async_rst_n) begin
        if (!async_rst_n) sync <= {STAGES{1'b1}};
        else              sync <= {sync[STAGES-2:0], 1'b0};
    end

    assign rst = sync[STAGES-1];
endmodule

`default_nettype wire
