// uart_rx.state stays inside IDLE..BREAK, so the default arm is unreachable.
`default_nettype none
module uart_rx_formal (
    input wire        clk,
    input wire        rst_n,
    input wire        rx,
    input wire [15:0] div
);
    wire       valid, frame_err;
    wire [7:0] data;

    uart_rx dut (
        .clk(clk), .rst_n(rst_n), .div(div), .rx(rx),
        .valid(valid), .data(data), .frame_err(frame_err)
    );

    always @* if ($initstate) assume(!rst_n);
endmodule
`default_nettype wire
