`timescale 1ns / 1ps
module instrROM(
    input  [5:0]      addr,
    output reg [15:0] data
);
    integer i;
    reg [15:0] mem [0:63];
    

    initial begin
        
        for (i = 0; i < 64; i = i + 1)
            mem[i] = 16'h0000;
        
        $readmemh("prog.hex", mem);
    end

    always @(*) data = mem[addr];
endmodule