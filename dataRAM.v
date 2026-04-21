`timescale 1ns / 1ps
module dataRAM(
    input         clk,
    input         wr_en,
    input  [5:0]  addr,      // 64 locations
    input  [15:0] wr_data,
    output [15:0] rd_data
);
    reg [15:0] mem [0:63];
    integer i;
    initial begin
        for (i = 0; i < 64; i = i + 1)
            mem[i] = 16'd0;
    end
    assign rd_data = mem[addr];
    always @(posedge clk) begin
        if (wr_en) mem[addr] <= wr_data;
    end
endmodule