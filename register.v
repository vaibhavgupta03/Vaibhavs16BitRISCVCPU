`timescale 1ns / 1ps
module register(
    input         clk, rst,
    input         wr_en,
    input  [3:0]  wr_addr,
    input  [15:0] wr_data,
    input  [3:0]  srcA_addr,
    input  [3:0]  srcB_addr,
    output [15:0] regA,
    output [15:0] regB,
    // Debug
    input         modeRead,
    input  [3:0]  valin,
    output reg [15:0] memOut
);
    reg [15:0] bank [0:15];
    integer i;

    assign regA = bank[srcA_addr];
    assign regB = bank[srcB_addr];

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 16; i = i + 1)
                bank[i] <= 16'd0;
        end else begin
            if (wr_en && wr_addr != 4'd0)
                bank[wr_addr] <= wr_data;
            bank[0] <= 16'd0;   // R0 hardwired zero
        end
    end

    always @(posedge clk) begin
        if (modeRead) memOut <= bank[valin];
    end
endmodule