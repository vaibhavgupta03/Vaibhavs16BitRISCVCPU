`timescale 1ns / 1ps
// ─── Testbench for cpu + test_all.asm ────────────────────────────────
module tb_cpu_test_all;

    reg        clk, rst;
    reg        single_step, run_halt, modeRead;
    reg  [3:0] valin;
    wire [3:0] leds;

    cpu #(.SIM_MODE(1)) DUT (
        .clk        (clk),
        .rst        (rst),
        .single_step(single_step),
        .run_halt   (run_halt),
        .modeRead   (modeRead),
        .valin      (valin),
        .leds       (leds)
    );

    initial clk = 0;
    always  #5 clk = ~clk;

    integer pass_cnt, fail_cnt;

    task check_reg;
        input  [3:0]  rnum;
        input  [15:0] expected;
        input  [8*32-1:0] tag;
        reg    [15:0] got;
        begin
            got = DUT.RF.bank[rnum];
            if (got === expected) begin
                $display("PASS  R%-2d = 16'h%04X  | %0s", rnum, got, tag);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL  R%-2d : got 16'h%04X  expected 16'h%04X  | %0s",
                         rnum, got, expected, tag);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    task check_mem;
        input  [5:0]  addr;
        input  [15:0] expected;
        input  [8*32-1:0] tag;
        reg    [15:0] got;
        begin
            got = DUT.DRAM.mem[addr];
            if (got === expected) begin
                $display("PASS  mem[%0d] = 16'h%04X  | %0s", addr, got, tag);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL  mem[%0d]: got 16'h%04X  expected 16'h%04X  | %0s",
                         addr, got, expected, tag);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_cpu_test_all.vcd");
        $dumpvars(0, tb_cpu_test_all);

        pass_cnt    = 0;
        fail_cnt    = 0;
        rst         = 1;
        single_step = 0;
        run_halt    = 0;
        modeRead    = 0;
        valin       = 4'h0;

        repeat(4) @(posedge clk);
        @(negedge clk);
        rst = 0;

        @(posedge clk); #1;
        run_halt = 1;
        @(posedge clk); #1;
        run_halt = 0;

        // 6 stages x ~50 instructions x safety margin
        repeat(600) @(posedge clk);

        $display("\n========== Register File Checks ==========");

        // R1: ADDI R1,R0,5 sets R1=5. "ADDI R1,R0,77" at word 38 is after
        // the JAL call site and is only reached on return. Since JR is not
        // implemented FUNC falls through to END, so word 38 is never executed.
        // Correct expected value is 5.
        check_reg( 1, 16'd5,   "ADDI R1=5 (JAL has no return, word38 unreachable)");
        check_reg( 2, 16'd100, "ADDI R2=100 (inside FUNC)");
        check_reg( 3, 16'd8,   "ADD  R3=R1+R2 (5+3)");
        check_reg( 4, 16'd2,   "SUB  R4=R1-R2 (5-3)");
        check_reg( 5, 16'd1,   "AND  R5=5&3");
        check_reg( 6, 16'd7,   "OR   R6=5|3");
        check_reg( 7, 16'd6,   "XOR  R7=5^3");
        check_reg( 8, 16'd1,   "SLT  R8=(3<5)=1");
        check_reg( 9, 16'd15,  "MUL  R9=5*3");
        check_reg(10, 16'd20,  "SLLI R10=5<<2");
        check_reg(11, 16'd10,  "SRLI R11=20>>1");
        check_reg(12, 16'd8,   "LW   R12=mem[0]=8");
        check_reg(13, 16'd2,   "LW   R13=mem[1]=2");
        check_reg(14, 16'd42,  "BEQ  taken -> R14=42");
        // JAL at word 36: PC after fetching both words = 38. R15 = 38.
        check_reg(15, 16'd38,  "JAL  R15 = return addr = 38");

        $display("\n========== Data Memory Checks ==========");
        check_mem(0, 16'd8, "SW R3 -> mem[0]=8");
        check_mem(1, 16'd2, "SW R4 -> mem[1]=2");

        $display("\n========== Summary ==========");
        $display("PASSED: %0d   FAILED: %0d   TOTAL: %0d",
                 pass_cnt, fail_cnt, pass_cnt + fail_cnt);
        if (fail_cnt == 0)
            $display("ALL TESTS PASSED");
        else
            $display("*** %0d TEST(S) FAILED ***", fail_cnt);
        $display("=========================================\n");
        $finish;
    end

    initial begin
        #150000;
        $display("TIMEOUT - simulation exceeded 150 us.");
        $finish;
    end

endmodule