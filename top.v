`timescale 1ns / 1ps
module top #(parameter SIM_MODE = 0)(
    input        clk,
    input        btn0,   // rst         (active-high)
    input        btn1,   // single_step
    input        btn2,   // run_halt toggle
    input        btn3,   // modeRead
    input  [3:0] sw,
    output [7:0] led
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