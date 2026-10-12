// Self-checking unit test for crc16_engine.
// Reference model: byte-wise Rocksoft CRC computed in the testbench.
`timescale 1ns/1ps
`default_nettype none
module tb_crc16;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg  [15:0] poly, init, xorout;
    reg         refin, refout, clear, start;
    reg  [7:0]  din;
    wire        busy, done;
    wire [15:0] result;

    crc16_engine #(.WIDTH(16), .RESET_VAL(16'hFFFF)) dut (
        .clk(clk), .rst_n(rst_n), .poly(poly), .init(init), .xorout(xorout),
        .refin(refin), .refout(refout), .clear(clear), .start(start),
        .din(din), .busy(busy), .done(done), .result(result)
    );

    integer errors = 0;
    integer checks = 0;
    integer done_count = 0;
    integer i, n, len;
    reg [31:0] rng;
    reg [15:0] ref_reg;
    reg [7:0]  msg [0:63];

    always @(posedge clk) if (done) done_count = done_count + 1;

    function [7:0] rev8(input [7:0] x);
        integer k;
        begin
            for (k = 0; k < 8; k = k + 1) rev8[k] = x[7-k];
        end
    endfunction

    function [15:0] rev16(input [15:0] x);
        integer k;
        begin
            for (k = 0; k < 16; k = k + 1) rev16[k] = x[15-k];
        end
    endfunction

    task next_rand;
        begin
            rng = rng ^ (rng << 13);
            rng = rng ^ (rng >> 17);
            rng = rng ^ (rng << 5);
        end
    endtask

    task ref_byte(input [7:0] b);
        integer k;
        reg [7:0] bb;
        begin
            bb = refin ? rev8(b) : b;
            ref_reg = ref_reg ^ {bb, 8'h00};
            for (k = 0; k < 8; k = k + 1)
                ref_reg = ref_reg[15] ? ((ref_reg << 1) ^ poly) : (ref_reg << 1);
        end
    endtask

    function [15:0] ref_result(input dummy);
        begin
            ref_result = (refout ? rev16(ref_reg) : ref_reg) ^ xorout;
        end
    endfunction

    task check(input [15:0] got, input [15:0] exp, input [8*24-1:0] what);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("ERROR %0s: got %h expected %h (poly %h init %h refin %b refout %b xor %h)",
                         what, got, exp, poly, init, refin, refout, xorout);
            end
        end
    endtask

    task do_clear;
        begin
            @(negedge clk) clear = 1'b1;
            @(negedge clk) clear = 1'b0;
            ref_reg = init;
        end
    endtask

    task feed(input [7:0] b);
        integer d0;
        begin
            d0 = done_count;
            @(negedge clk) begin start = 1'b1; din = b; end
            @(negedge clk) start = 1'b0;
            if (!busy) begin errors = errors + 1; $display("ERROR busy not set"); end
            while (busy) @(negedge clk);
            @(negedge clk);
            ref_byte(b);
            check(done_count - d0, 1, "done pulse count");
        end
    endtask

    task run_check_string(input [15:0] p, input [15:0] ini, input ri, input ro,
                          input [15:0] xo, input [15:0] expected);
        begin
            poly = p; init = ini; refin = ri; refout = ro; xorout = xo;
            do_clear;
            for (i = 0; i < 9; i = i + 1) feed(8'h31 + i[7:0]);   // "123456789"
            check(result, expected, "catalogue check value");
            check(result, ref_result(1'b0), "reference model");
        end
    endtask

    initial begin
        poly = 16'h1021; init = 16'hFFFF; xorout = 16'h0000;
        refin = 1'b0; refout = 1'b0; clear = 1'b0; start = 1'b0; din = 8'h00;
        rng = 32'h1BADF00D;
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        check(result, 16'hFFFF, "reset value");

        // Catalogue CRC-16 variants (reveng.sourceforge.net check values).
        run_check_string(16'h1021, 16'hFFFF, 1'b0, 1'b0, 16'h0000, 16'h29B1); // CCITT-FALSE
        run_check_string(16'h8005, 16'h0000, 1'b1, 1'b1, 16'h0000, 16'hBB3D); // ARC
        run_check_string(16'h8005, 16'hFFFF, 1'b1, 1'b1, 16'h0000, 16'h4B37); // MODBUS
        run_check_string(16'h1021, 16'h0000, 1'b0, 1'b0, 16'h0000, 16'h31C3); // XMODEM
        run_check_string(16'h1021, 16'h0000, 1'b1, 1'b1, 16'h0000, 16'h2189); // KERMIT
        run_check_string(16'h1021, 16'hFFFF, 1'b1, 1'b1, 16'hFFFF, 16'h906E); // X-25
        run_check_string(16'h3D65, 16'h0000, 1'b1, 1'b1, 16'hFFFF, 16'hEA82); // DNP

        // A start pulse while busy must be ignored.
        poly = 16'h1021; init = 16'hFFFF; refin = 0; refout = 0; xorout = 0;
        do_clear;
        @(negedge clk) begin start = 1'b1; din = 8'hA5; end
        @(negedge clk) begin start = 1'b1; din = 8'h5A; end   // ignored
        @(negedge clk) start = 1'b0;
        while (busy) @(negedge clk);
        ref_byte(8'hA5);
        check(result, ref_result(1'b0), "start while busy ignored");

        // clear cancels a byte in flight.
        @(negedge clk) begin start = 1'b1; din = 8'h77; end
        @(negedge clk) start = 1'b0;
        repeat (3) @(negedge clk);
        do_clear;
        check({15'd0, busy}, 16'd0, "clear cancels busy");
        check(result, init, "clear loads init");

        // Randomised: polynomials, init, reflections, xorout, lengths.
        for (n = 0; n < 250; n = n + 1) begin
            next_rand; poly   = rng[15:0] | 16'h0001; init = rng[31:16];
            next_rand; xorout = rng[15:0]; refin = rng[16]; refout = rng[17];
            len = 1 + (rng[23:18] % 32);
            do_clear;
            for (i = 0; i < len; i = i + 1) begin
                next_rand; msg[i] = rng[7:0];
                feed(msg[i]);
            end
            check(result, ref_result(1'b0), "random message");
        end

        // Asynchronous reset in the middle of a byte.
        @(negedge clk) begin start = 1'b1; din = 8'h3C; end
        @(negedge clk) start = 1'b0;
        rst_n = 1'b0;
        @(negedge clk) rst_n = 1'b1;
        check({15'd0, busy}, 16'd0, "reset clears busy");

        if (errors == 0) $display("PASS tb_crc16: %0d checks", checks);
        else             $display("FAIL tb_crc16: %0d errors / %0d checks", errors, checks);
        $finish;
    end

    initial begin
        #50_000_000;
        $display("FAIL tb_crc16: timeout");
        $finish;
    end
endmodule
`default_nettype wire
