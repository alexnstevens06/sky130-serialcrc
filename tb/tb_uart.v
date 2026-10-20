// Self-checking unit test: uart_tx -> uart_rx loopback plus line-level
// stimulus (false start, framing error/break, baud mismatch).
`timescale 1ns/1ps
`default_nettype none
module tb_uart;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg  [15:0] div;
    reg         start;
    reg  [7:0]  data;
    wire        tx, busy;
    reg         use_tb;
    reg         tb_line;
    wire        line = use_tb ? tb_line : tx;
    wire        valid, frame_err;
    wire [7:0]  rxd;

    uart_tx utx (.clk(clk), .rst_n(rst_n), .div(div), .start(start),
                 .data(data), .tx(tx), .busy(busy));
    uart_rx urx (.clk(clk), .rst_n(rst_n), .div(div), .rx(line),
                 .valid(valid), .data(rxd), .frame_err(frame_err));

    integer errors = 0, checks = 0;
    integer nrx = 0, nfe = 0;
    integer i, d, t0, t1, old;
    reg [7:0]  last;
    reg [31:0] rng;

    always @(posedge clk) begin
        if (valid) begin nrx = nrx + 1; last = rxd; end
        if (frame_err) nfe = nfe + 1;
    end

    task next_rand;
        begin
            rng = rng ^ (rng << 13);
            rng = rng ^ (rng >> 17);
            rng = rng ^ (rng << 5);
        end
    endtask

    task check(input [31:0] got, input [31:0] exp, input [8*24-1:0] what);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("ERROR %0s: got %0h expected %0h (div %0d)", what, got, exp, div);
            end
        end
    endtask

    task wait_rx(input integer prev_n);
        integer to;
        begin
            to = 0;
            while (nrx == prev_n && to < 20 * (div + 1) * 12) begin
                @(negedge clk); to = to + 1;
            end
        end
    endtask

    // Send through the DUT transmitter and check the DUT receiver.
    task loop_byte(input [7:0] b);
        begin
            while (busy) @(negedge clk);
            old = nrx;
            @(negedge clk) begin start = 1'b1; data = b; end
            @(negedge clk) start = 1'b0;
            wait_rx(old);
            check(nrx - old, 1, "loopback count");
            check(last, b, "loopback data");
            while (busy) @(negedge clk);
        end
    endtask

    // Drive the line from the testbench with bitclk clocks per bit.
    task tb_send(input [7:0] b, input stopbit, input integer bitclk);
        integer k;
        begin
            tb_line = 1'b0; repeat (bitclk) @(negedge clk);
            for (k = 0; k < 8; k = k + 1) begin
                tb_line = b[k]; repeat (bitclk) @(negedge clk);
            end
            tb_line = stopbit; repeat (bitclk) @(negedge clk);
            tb_line = 1'b1;
        end
    endtask

    initial begin
        div = 16'd4; start = 1'b0; data = 8'h00; use_tb = 1'b0; tb_line = 1'b1;
        rng = 32'hC0FFEE11;
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);
        check(tx, 1, "idle high");

        // All 256 byte values at a fast divisor, and at 1 clock/bit.
        // div == 0 used to sample the start bit one cycle late.
        for (i = 0; i < 256; i = i + 1) loop_byte(i[7:0]);
        div = 16'd0;
        for (i = 0; i < 256; i = i + 1) loop_byte(i[7:0]);
        div = 16'd4;

        // Several divisors, edge patterns + random bytes.
        for (d = 0; d < 4; d = d + 1) begin
            div = (d == 0) ? 16'd7 : (d == 1) ? 16'd20 : (d == 2) ? 16'd86 : 16'd300;
            loop_byte(8'h00); loop_byte(8'hFF); loop_byte(8'h55); loop_byte(8'hAA);
            for (i = 0; i < 16; i = i + 1) begin next_rand; loop_byte(rng[7:0]); end
        end

        // Largest divisor: exercises every bit of the 16-bit baud counters.
        div = 16'hFFFF;
        loop_byte(8'h96);

        // Bit timing: start bit of 0x01 lasts exactly div+1 clocks.
        div = 16'd20;
        @(negedge clk) begin start = 1'b1; data = 8'h01; end
        @(negedge clk) start = 1'b0;
        t0 = $time;
        while (!tx) @(negedge clk);
        t1 = $time;
        check((t1 - t0) / 10, 21, "start bit width");
        while (busy) @(negedge clk);

        // start while busy is ignored by the transmitter.
        old = nrx;
        @(negedge clk) begin start = 1'b1; data = 8'h12; end
        @(negedge clk) start = 1'b0;
        repeat (30) @(negedge clk);
        @(negedge clk) begin start = 1'b1; data = 8'h34; end
        @(negedge clk) start = 1'b0;
        wait_rx(old);
        while (busy) @(negedge clk);
        repeat (40 * 21) @(negedge clk);
        check(nrx - old, 1, "start while busy ignored");
        check(last, 8'h12, "first byte kept");

        // Line-level tests driven by the testbench.
        use_tb = 1'b1;
        div = 16'd15;
        repeat (50) @(negedge clk);

        // False start: a glitch shorter than half a bit is rejected.
        old = nrx;
        tb_line = 1'b0; repeat (4) @(negedge clk); tb_line = 1'b1;
        repeat (16 * 12) @(negedge clk);
        check(nrx - old, 0, "false start rejected");
        check(nfe, 0, "no framing error on glitch");

        // Framing error (stop bit low), held low as a break, then recovery.
        old = nrx;
        tb_send(8'h3C, 1'b0, 16);
        tb_line = 1'b0; repeat (16 * 3) @(negedge clk); tb_line = 1'b1;
        repeat (32) @(negedge clk);
        check(nrx - old, 0, "bad frame dropped");
        check(nfe, 1, "framing error flagged");
        tb_send(8'h5A, 1'b1, 16);
        repeat (16) @(negedge clk);
        check(nrx - old, 1, "recover after break");
        check(last, 8'h5A, "recover data");

        // +/-3% baud mismatch is tolerated (32 clocks/bit vs 33 and 31).
        div = 16'd31;
        old = nrx;
        tb_send(8'hC3, 1'b1, 33); repeat (32) @(negedge clk);
        check(last, 8'hC3, "baud tolerance +3%");
        tb_send(8'h3C, 1'b1, 31); repeat (32) @(negedge clk);
        div = 16'd15;
        check(nrx - old, 2, "baud tolerance count");
        check(last, 8'h3C, "baud tolerance data");

        // Back-to-back frames with no idle time between them.
        old = nrx;
        for (i = 0; i < 8; i = i + 1) tb_send(8'h80 >> i, 1'b1, 16);
        repeat (16) @(negedge clk);
        check(nrx - old, 8, "back-to-back frames");
        check(last, 8'h01, "back-to-back last");

        if (errors == 0) $display("PASS tb_uart: %0d checks, %0d bytes received", checks, nrx);
        else             $display("FAIL tb_uart: %0d errors / %0d checks", errors, checks);
        $finish;
    end

    initial begin
        #100_000_000;
        $display("FAIL tb_uart: timeout");
        $finish;
    end
endmodule
`default_nettype wire
