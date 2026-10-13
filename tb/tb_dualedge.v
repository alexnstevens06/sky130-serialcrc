// Dual-edge tests: CRC engine (2 bits/clock, rise + fall) and UART loopback
// under skewed clock duty cycles (30%, 50%, 70% high), plus a phase check that
// crc_h updates on the falling edge and crc on the rising edge.
`timescale 1ns/1ps
`default_nettype none
module tb_dualedge;
    reg clk = 1'b0, rst_n = 1'b0;
    real period = 15.15, duty = 0.5;
    always begin
        #(period * duty)       clk = 1'b0;
        #(period * (1 - duty)) clk = 1'b1;
    end

    integer errors = 0, checks = 0;
    task check(input [15:0] got, input [15:0] exp, input [255:0] what);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("ERROR %0s: got %h expected %h (duty %0.2f)", what, got, exp, duty);
            end
        end
    endtask

    // ---- CRC engine ----
    reg  [15:0] poly, init, xorout;
    reg         refin, refout, clear = 0, start = 0;
    reg  [7:0]  din = 0;
    wire        busy, done;
    wire [15:0] result;
    crc16_engine dut (.clk(clk), .rst_n(rst_n), .poly(poly), .init(init), .xorout(xorout),
        .refin(refin), .refout(refout), .clear(clear), .start(start), .din(din),
        .busy(busy), .done(done), .result(result));

    // ---- UART loopback ----
    reg  [15:0] div = 16'd7;
    reg         tx_start = 0;
    reg  [7:0]  tx_data = 0;
    wire        txd, tx_busy, rx_valid, rx_err;
    wire [7:0]  rx_data;
    uart_tx u_tx (.clk(clk), .rst_n(rst_n), .div(div), .start(tx_start), .data(tx_data),
                  .tx(txd), .busy(tx_busy));
    uart_rx u_rx (.clk(clk), .rst_n(rst_n), .div(div), .rx(txd), .valid(rx_valid),
                  .data(rx_data), .frame_err(rx_err));

    // drive inputs just after the rising edge
    task tick; begin @(posedge clk); #0.5; end endtask

    task crc_run(input [15:0] p, input [15:0] ini, input [15:0] xo, input ri, input ro,
                 input [15:0] expv, input [255:0] name);
        integer k, cyc;
        reg [8*9-1:0] msg;
        begin
            msg = "123456789";
            poly = p; init = ini; xorout = xo; refin = ri; refout = ro;
            tick; clear = 1; tick; clear = 0;
            for (k = 8; k >= 0; k = k - 1) begin
                din = msg[k*8 +: 8]; start = 1; tick; start = 0;
                cyc = 0;
                while (busy) begin tick; cyc = cyc + 1; end
                check(cyc, 4, "4 cycles per byte");
            end
            check(result, expv, name);
        end
    endtask

    // Phase check: crc_h must change only on falling edges, crc only on rising.
    reg [15:0] last_h, last_c;
    integer phase_err = 0;
    reg chk_en = 0;   // off around async reset, which changes both registers
    always @(posedge clk) begin #0.1; if (dut.crc_h !== last_h && chk_en) phase_err = phase_err + 1; end
    always @(negedge clk) begin #0.1; if (dut.crc   !== last_c && chk_en) phase_err = phase_err + 1; end
    always @(clk) begin #0.2; last_h = dut.crc_h; last_c = dut.crc; end

    integer d, b, cnt_to;
    real duties [0:2];
    initial begin
        duties[0] = 0.30; duties[1] = 0.50; duties[2] = 0.70;
        for (d = 0; d < 3; d = d + 1) begin
            duty = duties[d];
            chk_en = 0; rst_n = 0; repeat (3) tick; rst_n = 1; tick; tick; chk_en = 1;
            crc_run(16'h1021, 16'hFFFF, 16'h0000, 0, 0, 16'h29B1, "CRC-16/CCITT-FALSE");
            crc_run(16'h8005, 16'h0000, 16'h0000, 1, 1, 16'hBB3D, "CRC-16/ARC");
            crc_run(16'h8005, 16'hFFFF, 16'h0000, 1, 1, 16'h4B37, "CRC-16/MODBUS");
            crc_run(16'h1021, 16'h0000, 16'h0000, 0, 0, 16'h31C3, "CRC-16/XMODEM");
            for (b = 0; b < 6; b = b + 1) begin
                div = 16'd3 + b;   // 4..9 clocks per bit
                tx_data = 8'h3C ^ (b * 8'h4B); tx_start = 1; tick; tx_start = 0;
                cnt_to = 0;
                while (!rx_valid && !rx_err && cnt_to < 2000) begin tick; cnt_to = cnt_to + 1; end
                check({7'd0, rx_err, rx_data}, {8'd0, tx_data}, "UART loopback");
                while (tx_busy) tick;
            end
            chk_en = 0;
        end
        check(phase_err, 0, "edge phase of crc / crc_h");
        if (errors == 0) $display("PASS tb_dualedge: %0d checks, duty 30/50/70%%", checks);
        else             $display("FAIL tb_dualedge: %0d errors", errors);
        $finish;
    end
endmodule
`default_nettype wire
