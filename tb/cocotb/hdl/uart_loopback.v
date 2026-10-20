// Direct uart_tx / uart_rx harness for the cocotb unit suite.
// use_line selects the testbench-driven line instead of the transmitter.
`timescale 1ns/1ps
`default_nettype none
module uart_loopback (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] div,
    input  wire        start,
    input  wire [7:0]  data,
    input  wire        use_line,
    input  wire        line_in,
    output wire        tx,
    output wire        busy,
    output wire        valid,
    output wire [7:0]  rx_data,
    output wire        frame_err
);
    wire line = use_line ? line_in : tx;

    uart_tx u_tx (
        .clk(clk), .rst_n(rst_n), .div(div),
        .start(start), .data(data), .tx(tx), .busy(busy)
    );
    uart_rx u_rx (
        .clk(clk), .rst_n(rst_n), .div(div), .rx(line),
        .valid(valid), .data(rx_data), .frame_err(frame_err)
    );
endmodule
`default_nettype wire
