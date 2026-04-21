`timescale 1ns / 1ps
// ─── Clock Divider ───────────────────────────────────────────────────
module clkDivider #(
    parameter SIM_MODE = 0   // 1 = skip divider for simulation
)(
    input  clk,
    output clkout
);
    generate
        if (SIM_MODE == 1) begin
            // Simulation: pass clock straight through
            assign clkout = clk;
        end else begin
            // Hardware: divide 100MHz → ~1Hz (visible on LEDs)
            reg [26:0] count;
            reg        clk_reg;
            assign clkout = clk_reg;
            always @(posedge clk) begin
                if (count == 27'd99_999_999) begin
                    count   <= 0;
                    clk_reg <= ~clk_reg;
                end else begin
                    count <= count + 1;
                end
            end
        end
    endgenerate
endmodule