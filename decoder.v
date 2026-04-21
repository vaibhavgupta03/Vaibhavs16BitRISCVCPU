`timescale 1ns / 1ps
// ── Instruction encoding ──────────────────────────────────────────────
//
//  R-type  word1: [15:12]=grp  [11:8]=dest  [7:4]=srcA  [3:0]=srcB
//          word2: [3:0]=func   (upper 12 bits zero)
//    FIXED: srcB and func no longer share the same field.
//           srcB register address is in word1[3:0].
//           ALU func code comes from imm_word[3:0] (second fetch word).
//
//  I-type  word1: [15:12]=grp  [11:8]=dest  [7:4]=func  [3:0]=srcA
//          word2: 16-bit immediate
//    FIXED: srcA register address is in word1[3:0] (was hardwired to 0).
//           ALU func comes from word1[7:4] (not from srcA_addr field).
//
//  LD      word1: [15:12]=grp  [11:8]=dest  [7:4]=srcA  [3:0]=0
//          word2: offset
//
//  ST      word1: [15:12]=grp  [11:8]=rs    [7:4]=rb    [3:0]=0
//          word2: offset
//    NOTE: "dest" field holds the store-data register rs.
//          The CPU MEMORY stage must write bank[d_dest] to RAM,
//          not regB_data (which reads srcB_addr=instr[3:0]=0).
//
//  BRANCH  word1: [15:12]=grp  [11:8]=cond  [7:4]=srcA  [3:0]=srcB
//          word2: signed offset
//    FIXED: cond is no longer shifted left by 1 before being stored.
//           branch_type = instr[10:8] (lower 3 bits of the cond field).
//
//  J       word1: [15:12]=grp  [11:0]=0
//          word2: signed offset
//
//  JAL     word1: [15:12]=grp  [11:8]=dest  [7:0]=0
//          word2: signed offset
//
//  LUI     word1: [15:12]=grp  [11:8]=dest  [7:0]=0
//          word2: 16-bit immediate
//
//  NOP     single word 0x0000  (R-type group, all fields zero → ADD R0,R0,R0)
//
// Groups:
//   0000 = R-type ALU    (ADD SUB AND OR XOR SLL SRL SRA SLT SLTU MUL NOR …)
//   0001 = I-type ALU    (ADDI SUBI ANDI ORI XORI SLLI SRLI SRAI SLTI)
//   0010 = LOAD          (LW)
//   0011 = STORE         (SW)
//   0100 = BRANCH        (BEQ BNE BLT BGE BLTU BGEU)
//   0101 = JUMP          (J)
//   0110 = JUMP-LINK     (JAL)
//   0111 = UPPER IMM     (LUI)
// ─────────────────────────────────────────────────────────────────────

module decoder(
    input  [15:0] instr,
    input  [15:0] imm_word,     // second fetch word; valid when needs_imm=1
    // Instruction fields
    output [3:0]  grp,          // instruction group
    output [3:0]  dest,         // destination / rs-for-store
    output [3:0]  srcA_addr,    // first source register index
    output [3:0]  srcB_addr,    // second source register index
    output [15:0] imm_out,      // immediate value passed to ALU/memory
    output [3:0]  alu_op,       // ALU operation code
    output        needs_imm,    // 1 = instruction has a second 16-bit word
    // Control signals
    output        reg_write,
    output        mem_read,
    output        mem_write,
    output        is_branch,
    output        is_jump,
    output        is_jal,
    output        is_lui,
    output [2:0]  branch_type   // 000=BEQ 001=BNE 010=BLT 011=BGE
                                // 100=BLTU 101=BGEU
);
    assign grp      = instr[15:12];
    assign dest     = instr[11:8];

    // ── Source register address selection ────────────────────────────
    // R-type: srcA = instr[7:4],  srcB = instr[3:0]
    // I-type: srcA = instr[3:0]  (func is in instr[7:4], not srcA)
    // LD:     srcA = instr[7:4]  (base register)
    // ST:     srcA = instr[7:4]  (base register; data reg is dest/[11:8])
    // BR:     srcA = instr[7:4],  srcB = instr[3:0]
    // Others: don't-care (no register reads needed)
    assign srcA_addr = (grp == 4'b0001) ? instr[3:0]   // I-type: rs1 in [3:0]
                                        : instr[7:4];   // all others: rs1 in [7:4]

    assign srcB_addr = instr[3:0];   // R-type and BRANCH: rs2 in [3:0]

    // ── Immediate value ───────────────────────────────────────────────
    // All instructions that use a second word set needs_imm=1 and the
    // full 16-bit imm_word is forwarded.  NOP (0x0000, R-type grp)
    // does NOT need an immediate word.
    assign needs_imm = (grp == 4'b0001) |   // I-type
                       (grp == 4'b0010) |   // LOAD
                       (grp == 4'b0011) |   // STORE
                       (grp == 4'b0100) |   // BRANCH
                       (grp == 4'b0101) |   // JUMP
                       (grp == 4'b0110) |   // JAL
                       (grp == 4'b0111) |   // LUI
                       (grp == 4'b0000 && instr != 16'h0000); // R-type (not NOP)

    assign imm_out = imm_word;   // always use the fetched second word

    // ── ALU operation code ────────────────────────────────────────────
    // R-type: func lives in imm_word[3:0]  (second fetch word)
    // I-type: func lives in instr[7:4]     (word1, same field as old srcA)
    // LD/ST:  ADD (opcode 0) — compute address = base + offset
    // BRANCH: SUB (opcode 1) — compare rs1 and rs2
    // Others: PASS B (opcode 11) — forward immediate/offset unchanged
    assign alu_op =
        (grp == 4'b0000) ? imm_word[3:0] :   // R-type: func from word2
        (grp == 4'b0001) ? instr[7:4]    :   // I-type: func from word1[7:4]
        (grp == 4'b0010) ? 4'd0          :   // LOAD:  ADD base+offset
        (grp == 4'b0011) ? 4'd0          :   // STORE: ADD base+offset
        (grp == 4'b0100) ? 4'd1          :   // BRANCH: SUB for compare
        4'd11;                               // J/JAL/LUI: PASS B

    // ── Register-write enable ─────────────────────────────────────────
    assign reg_write = (grp == 4'b0000) |   // R-type
                       (grp == 4'b0001) |   // I-type
                       (grp == 4'b0010) |   // LOAD
                       (grp == 4'b0110) |   // JAL
                       (grp == 4'b0111);    // LUI

    assign mem_read  = (grp == 4'b0010);
    assign mem_write = (grp == 4'b0011);
    assign is_branch = (grp == 4'b0100);
    assign is_jump   = (grp == 4'b0101);
    assign is_jal    = (grp == 4'b0110);
    assign is_lui    = (grp == 4'b0111);

    // ── Branch condition ──────────────────────────────────────────────
    // cond field is in instr[11:8]; lower 3 bits give the condition code.
    // FIXED: was instr[11:9], but the old assembler shifted cond left by 1
    //        before storing it, making instr[11:9] work.  New assembler
    //        stores cond directly, so we read instr[10:8].
    assign branch_type = instr[10:8];

endmodule