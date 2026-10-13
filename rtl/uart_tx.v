// UART transmitter, 8N1. Each bit lasts (div + 1) clock cycles.
// The bit-timer terminal count is a registered flag (cz == (cnt == 0)), computed
// one cycle ahead, so the high-fanout control decision is one flop, not a
// 16-bit compare.
`default_nettype none
module uart_tx (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] div,
    input  wire        start,
    input  wire [7:0]  data,
    output reg         tx,
    output reg         busy
);
    reg [15:0] cnt;
    reg        cz;       // cnt == 0, registered
    reg [3:0]  bitn;
    reg [8:0]  sh;
    wire       div_z = (div == 16'd0);
    wire       cnt_1 = (cnt == 16'd1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx   <= 1'b1;
            busy <= 1'b0;
            cnt  <= 16'd0;
            cz   <= 1'b1;
            bitn <= 4'd0;
            sh   <= 9'h1FF;
        end else if (!busy) begin
            tx <= 1'b1;
            if (start) begin
                busy <= 1'b1;
                tx   <= 1'b0;            // start bit
                sh   <= {1'b1, data};    // data LSB first, then stop bit
                cnt  <= div;
                cz   <= div_z;
                bitn <= 4'd0;
            end
        end else if (!cz) begin
            cnt <= cnt - 16'd1;
            cz  <= cnt_1;
        end else begin
            cnt <= div;
            cz  <= div_z;
            if (bitn == 4'd9) begin
                busy <= 1'b0;            // stop bit finished
                tx   <= 1'b1;
            end else begin
                tx   <= sh[0];
                sh   <= {1'b1, sh[8:1]};
                bitn <= bitn + 4'd1;
            end
        end
    end
endmodule
`default_nettype wire
