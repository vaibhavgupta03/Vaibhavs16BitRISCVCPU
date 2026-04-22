`timescale 1ns / 1ps

module top #(
    parameter SIM_MODE = 0
)(
    input        clk,
    input        btn0,   // rst         - active-high reset
    input        btn1,   // single_step - advance one instruction
    input        btn2,   // run_halt    - toggle continuous run
    input        btn3,   // modeRead    - 0=show ALU result, 1=show register
    input  [3:0] sw,     // valin       - register index to display in modeRead
    output [7:0] led     // leds        - 4-bit output
);

    cpu #(.SIM_MODE(SIM_MODE)) CPU (
        .clk        (clk),
        .rst        (btn0),
        .single_step(btn1),
        .run_halt   (btn2),
        .modeRead   (btn3),
        .valin      (sw),
        .leds       (led)
    );

endmodule