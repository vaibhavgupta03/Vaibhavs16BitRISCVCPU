`timescale 1ns / 1ps
module clkDivider #(parameter SIM_MODE = 0)(
    input  clk,
    output clkout
);
    generate
        if (SIM_MODE == 1) begin
            assign clkout = clk;
        end else begin
            reg [26:0] count  = 27'd0;   // ← MUST initialize
            reg        clk_reg = 1'b0;   // ← MUST initialize
            assign clkout = clk_reg;
            always @(posedge clk) begin
                if (count == 27'd49_999_999) begin  // 100MHz→1Hz
                    count   <= 27'd0;
                    clk_reg <= ~clk_reg;
                end else
                    count <= count + 1;
            end
        end
    endgenerate
endmodule