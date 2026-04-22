`timescale 1ns / 1ps

module cpu #(parameter SIM_MODE = 0)(
    input        clk, rst,
    input        single_step, run_halt, modeRead,
    input  [3:0] valin,
    output [3:0] leds
);
    wire slow_clk;
    clkDivider #(.SIM_MODE(SIM_MODE)) CLK_DIV(
        .clk(clk), .clkout(slow_clk));

    localparam FETCH     = 3'd0,
               FETCH2    = 3'd1,
               DECODE    = 3'd2,
               EXECUTE   = 3'd3,
               MEMORY    = 3'd4,
               WRITEBACK = 3'd5,
               HALT      = 3'd6;

    reg [2:0]  state;
    reg [5:0]  PC;
    reg [15:0] IR, IMM_WORD;
    reg        running;
    reg        ss_prev, rh_prev;

    
    reg [3:0]  d_grp, d_dest, d_srcA, d_srcB;
    reg [15:0] d_imm;
    reg [3:0]  d_alu_op;
    reg        d_reg_write, d_mem_read, d_mem_write;
    reg        d_is_branch, d_is_jump, d_is_jal, d_is_lui;
    reg [2:0]  d_branch_type;

    
    reg [15:0] ex_result;
    reg [3:0]  ex_flags;
    reg [15:0] wb_data;
    
    
    reg [15:0] store_data; 

    
    wire [15:0] rom_data;
    wire [3:0]  dec_grp, dec_dest, dec_srcA, dec_srcB;
    wire [15:0] dec_imm;
    wire [3:0]  dec_alu_op;
    wire        dec_needs_imm, dec_reg_write;
    wire        dec_mem_read, dec_mem_write;
    wire        dec_is_branch, dec_is_jump, dec_is_jal, dec_is_lui;
    wire [2:0]  dec_branch_type;

    wire [15:0] regA_data, regB_data;
    wire [15:0] alu_result_w;
    wire [3:0]  alu_flags_w;
    wire [15:0] mem_rd_data;
    wire [15:0] reg_memOut;

    reg         ram_wr_en;
    reg [5:0]   ram_addr;
    reg [15:0]  ram_wr_data;
    reg         rf_wr_en;

    instrROM ROM(.addr(PC[5:0]), .data(rom_data));

    decoder DEC(
        .instr(IR),            .imm_word(IMM_WORD),
        .grp(dec_grp),         .dest(dec_dest),
        .srcA_addr(dec_srcA),  .srcB_addr(dec_srcB),
        .imm_out(dec_imm),     .alu_op(dec_alu_op),
        .needs_imm(dec_needs_imm),
        .reg_write(dec_reg_write),
        .mem_read(dec_mem_read),   .mem_write(dec_mem_write),
        .is_branch(dec_is_branch), .is_jump(dec_is_jump),
        .is_jal(dec_is_jal),       .is_lui(dec_is_lui),
        .branch_type(dec_branch_type)
    );

    register RF(
        .clk(slow_clk), .rst(rst),
        .wr_en(rf_wr_en),
        .wr_addr(d_dest),
        .wr_data(wb_data),
        .srcA_addr(dec_srcA),
        .srcB_addr(dec_srcB),
        .regA(regA_data), .regB(regB_data),
        .modeRead(modeRead), .valin(valin),
        .memOut(reg_memOut)
    );

    
    alu ALU(
        .opcode(d_alu_op),
        .A(regA_data),
        .B(
            (d_grp == 4'b0001 || d_mem_read || d_mem_write || d_is_lui)
                ? d_imm
                : regB_data
        ),
        .result(alu_result_w),
        .flags(alu_flags_w)
    );

    dataRAM DRAM(
        .clk(slow_clk),
        .wr_en(ram_wr_en),
        .addr(ram_addr),
        .wr_data(ram_wr_data),
        .rd_data(mem_rd_data)
    );

    
    reg branch_taken;
    always @(*) begin
        case (d_branch_type)
            3'b000: branch_taken = ex_flags[1];      // BEQ: Z=1
            3'b001: branch_taken = ~ex_flags[1];     // BNE: Z=0
            3'b010: branch_taken = ex_flags[3];      // BLT: N=1
            3'b011: branch_taken = ~ex_flags[3];     // BGE: N=0
            3'b100: branch_taken = ~ex_flags[2];     // BLTU: C=0
            3'b101: branch_taken =  ex_flags[2];     // BGEU: C=1
            default: branch_taken = 1'b0;
        endcase
    end

    
    always @(posedge slow_clk or posedge rst) begin
        if (rst) begin
            state      <= FETCH;
            PC         <= 6'd0;
            IR         <= 16'd0;
            IMM_WORD   <= 16'd0;
            running    <= 1'b0;
            rf_wr_en   <= 1'b0;
            ram_wr_en  <= 1'b0;
            ss_prev    <= 1'b0;
            rh_prev    <= 1'b0;
            ex_result  <= 16'd0;
            ex_flags   <= 4'd0;
            wb_data    <= 16'd0;
            store_data <= 16'd0; 
        end else begin
            rf_wr_en  <= 1'b0;
            ram_wr_en <= 1'b0;
            ss_prev   <= single_step;
            rh_prev   <= run_halt;

            if (run_halt && !rh_prev) running <= ~running;

            case (state)
                FETCH: begin
                    if (running || (single_step && !ss_prev)) begin
                        IR    <= rom_data;
                        PC    <= PC + 1;
                        state <= FETCH2;
                    end
                end

                FETCH2: begin
                    if (dec_needs_imm) begin
                        IMM_WORD <= rom_data;
                        PC       <= PC + 1;
                    end else begin
                        IMM_WORD <= 16'd0;
                    end
                    state <= DECODE;
                end

                DECODE: begin
                    d_grp        <= dec_grp;
                    d_dest       <= dec_dest;
                    d_srcA       <= dec_srcA;
                    d_srcB       <= dec_srcB;
                    d_imm        <= dec_imm;
                    
                    
                    d_alu_op     <= (dec_grp == 4'b0000) ? IMM_WORD[3:0] : dec_alu_op; 
                    
                    d_reg_write  <= dec_reg_write;
                    d_mem_read   <= dec_mem_read;
                    d_mem_write  <= dec_mem_write;
                    d_is_branch  <= dec_is_branch;
                    d_is_jump    <= dec_is_jump;
                    d_is_jal     <= dec_is_jal;
                    d_is_lui     <= dec_is_lui;
                    d_branch_type<= dec_branch_type;
                    state        <= EXECUTE;
                end

                EXECUTE: begin
                    ex_result  <= alu_result_w;
                    ex_flags   <= alu_flags_w;
                    
                    
                    store_data <= RF.bank[d_dest]; 

                    if (d_is_jump) begin
                        PC    <= PC + d_imm[5:0];
                        state <= FETCH;

                    end else if (d_is_jal) begin
                        
                        wb_data <= {10'd0, PC}; 
                        PC      <= PC + d_imm[5:0];
                        state   <= WRITEBACK;
                        
                    end else begin
                        state <= MEMORY;
                    end
                end

                MEMORY: begin
                    if (d_mem_write) begin
                        ram_wr_en   <= 1'b1;
                        ram_addr    <= ex_result[5:0];
                        
                        ram_wr_data <= store_data;   
                    end

                    if (d_mem_read) begin
                        ram_addr <= ex_result[5:0];
                    end

                    if (d_is_branch && branch_taken) begin
                        PC <= PC + d_imm[5:0];
                    end

                    state <= WRITEBACK;
                end

                WRITEBACK: begin
                    ram_wr_en <= 1'b0;
                    if (d_mem_read)
                        wb_data <= mem_rd_data;
                    else if (!d_is_jal)
                        wb_data <= ex_result;

                    if (d_reg_write)
                        rf_wr_en <= 1'b1;
                    
                    state <= (PC >= 6'd62) ? HALT : FETCH;
                end

                HALT: ;
            endcase
        end
    end

    assign leds = modeRead ? reg_memOut[3:0] : ex_result[3:0];
endmodule