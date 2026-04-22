`timescale 1ns / 1ps
module alu(
    input  [3:0]  opcode,
    input  [15:0] A,
    input  [15:0] B,
    output reg [15:0] result,
    output [3:0] flags       // N C Z V
);
    wire [16:0] sum_add = {1'b0,A} + {1'b0,B};
    wire [16:0] sum_sub = {1'b0,A} + {1'b0,~B} + 17'd1;

    wire carry_add = sum_add[16];
    wire carry_sub = sum_sub[16];
    wire ov_add = (~A[15] & ~B[15] & sum_add[15]) |
                  ( A[15] &  B[15] & ~sum_add[15]);
    wire ov_sub = (~A[15] &  B[15] & sum_sub[15]) |
                  ( A[15] & ~B[15] & ~sum_sub[15]);

    // opcodes
    localparam ADD  = 4'd0,  SUB  = 4'd1,
               AND  = 4'd2,  OR   = 4'd3,
               XOR  = 4'd4,  SLL  = 4'd5,
               SRL  = 4'd6,  SRA  = 4'd7,
               SLT  = 4'd8,  SLTU = 4'd9,
               MUL  = 4'd10, PASS = 4'd11,
               NOR  = 4'd12, XNOR = 4'd13,
               MIN  = 4'd14, MAX  = 4'd15;

    always @(*) begin
        case (opcode)
            ADD:  result = sum_add[15:0];
            SUB:  result = sum_sub[15:0];
            AND:  result = A & B;
            OR:   result = A | B;
            XOR:  result = A ^ B;
            SLL:  result = A << B[3:0];
            SRL:  result = A >> B[3:0];
            SRA:  result = $signed(A) >>> B[3:0];
            SLT:  result = ($signed(A) < $signed(B)) ? 16'd1 : 16'd0;
            SLTU: result = (A < B)                   ? 16'd1 : 16'd0;
            MUL:  result = A[7:0] * B[7:0];          // lower 16 of 8x8
            PASS: result = B;
            NOR:  result = ~(A | B);
            XNOR: result = ~(A ^ B);
            MIN:  result = ($signed(A) < $signed(B)) ? A : B;
            MAX:  result = ($signed(A) > $signed(B)) ? A : B;
            default: result = 16'd0;
        endcase
    end

    assign flags[3] = result[15];                         // N
    assign flags[2] = (opcode==ADD) ? carry_add :
                      (opcode==SUB) ? carry_sub : 1'b0;  // C
    assign flags[1] = (result == 16'd0);                  // Z
    assign flags[0] = (opcode==ADD) ? ov_add :
                      (opcode==SUB) ? ov_sub : 1'b0;     // V
endmodule