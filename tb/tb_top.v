// Full-chip self-checking test of tt_um_alexstevens_serialcrc through the
// TinyTapeout pins only: SPI master model, UART TX/RX models, GPIO, IRQ.
`timescale 1ns/1ps
`default_nettype none
module tb_top;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #50 clk = ~clk;          // 10 MHz

    reg  [7:0] ui_in;
    reg  [7:0] uio_in;
    reg        ena;
    wire [7:0] uo_out, uio_out, uio_oe;

    tt_um_alexstevens_serialcrc #(.CLK_HZ(10_000_000), .BAUD(115_200)) dut (
        .ui_in(ui_in), .uo_out(uo_out), .uio_in(uio_in), .uio_out(uio_out),
        .uio_oe(uio_oe), .ena(ena), .clk(clk), .rst_n(rst_n)
    );

    localparam H = 4;               // clk cycles per SCLK half period (f_clk = 8 f_sclk)
    localparam A_ID = 8'h00, A_CTRL = 8'h01, A_STATUS = 8'h02, A_BAUD_LO = 8'h03,
               A_BAUD_HI = 8'h04, A_UART = 8'h05, A_POLY_LO = 8'h06, A_POLY_HI = 8'h07,
               A_INIT_LO = 8'h08, A_INIT_HI = 8'h09, A_XOR_LO = 8'h0A, A_XOR_HI = 8'h0B,
               A_CRC_DAT = 8'h0C, A_CRC_CMD = 8'h0D, A_CRC_LO = 8'h0E, A_CRC_HI = 8'h0F,
               A_GPIO = 8'h10, A_GPIO_OE = 8'h11;

    integer errors = 0, checks = 0;
    integer i, n, bitclk;
    reg [7:0]  r, r2;
    reg [31:0] rng;
    reg [7:0]  shadow [0:17];
    reg        rw_reg [0:17];

    // ---------------- helpers ----------------
    task check(input [31:0] got, input [31:0] exp, input [8*28-1:0] what);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("ERROR @%0t %0s: got %0h expected %0h", $time, what, got, exp);
            end
        end
    endtask

    task next_rand;
        begin
            rng = rng ^ (rng << 13);
            rng = rng ^ (rng >> 17);
            rng = rng ^ (rng << 5);
        end
    endtask

    // ---------------- SPI master (mode 0) ----------------
    integer miso_hi_idle = 0;
    always @(negedge clk) if (rst_n && ui_in[2] && uo_out[1]) miso_hi_idle = miso_hi_idle + 1;

    task spi_xfer(input [7:0] b0, input [7:0] b1, input integer nbits, output [7:0] rd);
        integer k;
        reg b;
        begin
            rd = 8'h00;
            @(negedge clk) ui_in[2] = 1'b0;
            repeat (H) @(negedge clk);
            for (k = 0; k < nbits; k = k + 1) begin
                b = (k < 8) ? b0[7-k] : b1[15-k];
                ui_in[3] = b;                         // MOSI changes while SCLK low
                repeat (H) @(negedge clk);
                if (k >= 8) rd[15-k] = uo_out[1];     // sample MISO at the rising edge
                ui_in[1] = 1'b1;
                repeat (H) @(negedge clk);
                ui_in[1] = 1'b0;
            end
            repeat (H) @(negedge clk);
            ui_in[2] = 1'b1;
            ui_in[3] = 1'b0;
            repeat (2 * H) @(negedge clk);
        end
    endtask

    task spi_write(input [7:0] a, input [7:0] d);
        reg [7:0] dummy;
        begin spi_xfer({1'b0, a[6:0]}, d, 16, dummy); end
    endtask

    task spi_read(input [7:0] a, output [7:0] d);
        begin spi_xfer({1'b1, a[6:0]}, 8'h00, 16, d); end
    endtask

    task expect_reg(input [7:0] a, input [7:0] exp, input [8*28-1:0] what);
        reg [7:0] v;
        begin spi_read(a, v); check(v, exp, what); end
    endtask

    // ---------------- UART monitor on uo_out[0] ----------------
    reg [7:0] txq [0:63];
    integer   ntx = 0, tx_ferr = 0, mk;
    reg [7:0] mb;
    always begin : uart_mon
        @(negedge clk);
        if (rst_n && uo_out[0] == 1'b0) begin
            repeat (bitclk / 2) @(negedge clk);
            for (mk = 0; mk < 8; mk = mk + 1) begin
                repeat (bitclk) @(negedge clk);
                mb[mk] = uo_out[0];
            end
            repeat (bitclk) @(negedge clk);
            if (uo_out[0] !== 1'b1) tx_ferr = tx_ferr + 1;
            txq[ntx[5:0]] = mb;
            ntx = ntx + 1;
        end
    end

    task wait_tx(input integer prev_n);
        integer to;
        begin
            to = 0;
            while (ntx == prev_n && to < bitclk * 40) begin @(negedge clk); to = to + 1; end
            check(ntx - prev_n, 1, "uart tx byte seen");
        end
    endtask

    // ---------------- UART driver on ui_in[0] ----------------
    task uart_send(input [7:0] b, input stopbit);
        integer k;
        begin
            @(negedge clk) ui_in[0] = 1'b0;
            repeat (bitclk) @(negedge clk);
            for (k = 0; k < 8; k = k + 1) begin
                ui_in[0] = b[k]; repeat (bitclk) @(negedge clk);
            end
            ui_in[0] = stopbit; repeat (bitclk) @(negedge clk);
            ui_in[0] = 1'b1;    repeat (bitclk) @(negedge clk);
        end
    endtask

    // ---------------- CRC through SPI ----------------
    task crc_setup(input [15:0] p, input [15:0] ini, input [15:0] xo, input [4:0] ctrl);
        begin
            spi_write(A_POLY_LO, p[7:0]);   spi_write(A_POLY_HI, p[15:8]);
            spi_write(A_INIT_LO, ini[7:0]); spi_write(A_INIT_HI, ini[15:8]);
            spi_write(A_XOR_LO, xo[7:0]);   spi_write(A_XOR_HI, xo[15:8]);
            spi_write(A_CTRL, {3'b000, ctrl});
            spi_write(A_CRC_CMD, 8'h01);
        end
    endtask

    task crc_expect(input [15:0] exp, input [8*28-1:0] what);
        begin
            spi_read(A_CRC_LO, r); spi_read(A_CRC_HI, r2);
            check({r2, r}, exp, what);
        end
    endtask

    integer busy_cycles = 0, irq_cycles = 0;
    always @(posedge clk) begin
        if (uo_out[2]) busy_cycles = busy_cycles + 1;
        if (uo_out[3]) irq_cycles  = irq_cycles + 1;
    end

    task crc_string_spi(input [15:0] p, input [15:0] ini, input refl, input [15:0] xo,
                        input [15:0] exp, input [8*28-1:0] what);
        begin
            crc_setup(p, ini, xo, {3'b000, refl, refl});
            for (i = 0; i < 9; i = i + 1) spi_write(A_CRC_DAT, 8'h31 + i[7:0]);
            crc_expect(exp, what);
        end
    endtask

    // ---------------- test sequence ----------------
    initial begin
        ui_in  = 8'b0000_0101;   // uart_rx idle high, cs_n high, sclk low
        uio_in = 8'h00;
        ena    = 1'b1;
        bitclk = 87;
        rng    = 32'h5EED1234;
        rw_reg[0] = 0; rw_reg[2] = 0; rw_reg[5] = 0; rw_reg[12] = 0; rw_reg[13] = 0;
        rw_reg[14] = 0; rw_reg[15] = 0;
        rw_reg[1] = 1; rw_reg[3] = 1; rw_reg[4] = 1; rw_reg[6] = 1; rw_reg[7] = 1;
        rw_reg[8] = 1; rw_reg[9] = 1; rw_reg[10] = 1; rw_reg[11] = 1; rw_reg[16] = 1;
        rw_reg[17] = 1;
        repeat (10) @(negedge clk);
        rst_n = 1'b1;
        repeat (5) @(negedge clk);

        // --- reset state of the pins ---
        check(uo_out, 8'h01, "uo_out after reset");
        check(uio_oe, 8'h00, "uio_oe after reset");
        check(uio_out, 8'h00, "uio_out after reset");

        // --- ID and reset values ---
        expect_reg(A_ID,      8'hA5, "ID");
        expect_reg(A_CTRL,    8'h00, "CTRL reset");
        expect_reg(A_STATUS,  8'h00, "STATUS reset");
        expect_reg(A_BAUD_LO, 8'd86, "BAUD_LO reset (115200)");
        expect_reg(A_BAUD_HI, 8'h00, "BAUD_HI reset");
        expect_reg(A_UART,    8'h00, "UART_DATA reset");
        expect_reg(A_POLY_LO, 8'h21, "POLY_LO reset");
        expect_reg(A_POLY_HI, 8'h10, "POLY_HI reset");
        expect_reg(A_INIT_LO, 8'hFF, "INIT_LO reset");
        expect_reg(A_INIT_HI, 8'hFF, "INIT_HI reset");
        expect_reg(A_XOR_LO,  8'h00, "XOR_LO reset");
        expect_reg(A_XOR_HI,  8'h00, "XOR_HI reset");
        expect_reg(A_CRC_LO,  8'hFF, "CRC_LO reset");
        expect_reg(A_CRC_HI,  8'hFF, "CRC_HI reset");
        expect_reg(A_GPIO,    8'h00, "GPIO reset");
        expect_reg(A_GPIO_OE, 8'h00, "GPIO_OE reset");

        // --- unmapped / read-only addresses ---
        expect_reg(8'h12, 8'h00, "unmapped 0x12");
        expect_reg(8'h40, 8'h00, "unmapped 0x40");
        expect_reg(8'h7F, 8'h00, "unmapped 0x7F");
        spi_write(A_ID, 8'h00);
        expect_reg(A_ID, 8'hA5, "ID is read-only");
        spi_write(8'h7F, 8'hFF);
        spi_write(A_CRC_LO, 8'h12);
        expect_reg(A_CRC_LO, 8'hFF, "CRC_LO is read-only");
        check(miso_hi_idle, 0, "MISO low while CS high");

        // --- walking/pattern write+readback of every RW register ---
        for (n = 0; n < 4; n = n + 1) begin
            r = (n == 0) ? 8'h55 : (n == 1) ? 8'hAA : (n == 2) ? 8'hFF : 8'h00;
            for (i = 1; i < 18; i = i + 1) if (rw_reg[i] && i != A_CTRL) begin
                spi_write(i[7:0], r);
                expect_reg(i[7:0], r, "RW pattern readback");
            end
            spi_write(A_CTRL, r);
            expect_reg(A_CTRL, r & 8'h1F, "CTRL readback (5 bits)");
        end
        spi_write(A_CTRL, 8'h00);

        // --- random register traffic against a shadow model ---
        for (i = 0; i < 18; i = i + 1) begin
            spi_read(i[7:0], r); shadow[i] = r;
        end
        for (n = 0; n < 120; n = n + 1) begin
            next_rand;
            i = 6 + (rng[11:8] % 12);            // POLY..GPIO_OE (skip CTRL/BAUD/UART)
            if (rw_reg[i]) begin
                spi_write(i[7:0], rng[7:0]); shadow[i] = rng[7:0];
            end
            if (rng[20]) begin
                next_rand; i = 6 + (rng[11:8] % 12);
                if (rw_reg[i]) expect_reg(i[7:0], shadow[i], "random shadow read");
            end
        end
        for (i = 6; i < 12; i = i + 1) expect_reg(i[7:0], shadow[i], "final shadow read");
        expect_reg(A_GPIO, shadow[16], "final shadow GPIO");
        expect_reg(A_GPIO_OE, shadow[17], "final shadow GPIO_OE");

        // --- GPIO drives the bidirectional pins ---
        spi_write(A_GPIO, 8'h3C);
        spi_write(A_GPIO_OE, 8'hF0);
        check(uio_out, 8'h3C, "uio_out = GPIO_OUT");
        check(uio_oe,  8'hF0, "uio_oe = GPIO_OE");

        // --- aborted SPI transaction has no effect ---
        spi_xfer({1'b0, 7'h10}, 8'hFF, 11, r);
        check(uio_out, 8'h3C, "aborted write ignored");
        spi_xfer({1'b0, 7'h10}, 8'hFF, 15, r);
        check(uio_out, 8'h3C, "aborted write (15b) ignored");
        expect_reg(A_GPIO, 8'h3C, "GPIO after abort");
        spi_write(A_GPIO, 8'h00);
        spi_write(A_GPIO_OE, 8'h00);

        // --- CRC accelerator via SPI: catalogue check values ---
        crc_string_spi(16'h1021, 16'hFFFF, 1'b0, 16'h0000, 16'h29B1, "CRC-16/CCITT-FALSE");
        crc_string_spi(16'h8005, 16'h0000, 1'b1, 16'h0000, 16'hBB3D, "CRC-16/ARC");
        crc_string_spi(16'h8005, 16'hFFFF, 1'b1, 16'h0000, 16'h4B37, "CRC-16/MODBUS");
        crc_string_spi(16'h1021, 16'h0000, 1'b0, 16'h0000, 16'h31C3, "CRC-16/XMODEM");
        crc_string_spi(16'h1021, 16'hFFFF, 1'b1, 16'hFFFF, 16'h906E, "CRC-16/X-25");
        check(busy_cycles, 5 * 9 * 8, "crc_busy pin cycles");

        // crc_done sticky flag + IRQ, cleared by reading STATUS.
        spi_read(A_STATUS, r);   // clear any pending sticky flags
        crc_setup(16'h1021, 16'hFFFF, 16'h0000, 5'b10000);   // irq_crc_done_en
        check(uo_out[3], 0, "irq low prev_n crc");
        spi_write(A_CRC_DAT, 8'h42);
        check(uo_out[3], 1, "irq on crc_done");
        expect_reg(A_STATUS, 8'h10, "STATUS crc_done");
        check(uo_out[3], 0, "irq cleared by STATUS read");
        expect_reg(A_STATUS, 8'h00, "STATUS crc_done cleared");
        // CRC_CMD with bit0 = 0 does nothing; CRC result unchanged.
        spi_read(A_CRC_LO, r);
        spi_write(A_CRC_CMD, 8'h00);
        expect_reg(A_CRC_LO, r, "CRC_CMD bit0=0 no-op");
        spi_write(A_CTRL, 8'h00);

        // --- UART TX at a faster divisor (16 clocks / bit) ---
        spi_write(A_BAUD_LO, 8'd15);
        spi_write(A_BAUD_HI, 8'd0);
        bitclk = 16;
        n = ntx; spi_write(A_UART, 8'h55); wait_tx(n); check(txq[n], 8'h55, "uart tx 0x55");
        n = ntx; spi_write(A_UART, 8'hA3); wait_tx(n); check(txq[n], 8'hA3, "uart tx 0xA3");
        n = ntx; spi_write(A_UART, 8'h00); wait_tx(n); check(txq[n], 8'h00, "uart tx 0x00");
        n = ntx; spi_write(A_UART, 8'hFF); wait_tx(n); check(txq[n], 8'hFF, "uart tx 0xFF");
        // A write while the transmitter is busy is ignored (64 clocks/bit so
        // a frame outlasts the following SPI transactions).
        spi_write(A_BAUD_LO, 8'd63);
        bitclk = 64;
        n = ntx;
        spi_write(A_UART, 8'h11);
        check(uo_out[4], 1, "tx_busy pin");
        expect_reg(A_STATUS, 8'h01, "STATUS tx_busy");
        spi_write(A_UART, 8'h22);
        repeat (bitclk * 30) @(negedge clk);
        spi_write(A_BAUD_LO, 8'd15);
        bitclk = 16;
        check(ntx - n, 1, "write while tx busy ignored");
        check(txq[n], 8'h11, "first tx byte kept");
        check(tx_ferr, 0, "tx stop bits ok");
        // A 16-bit divisor: BAUD_HI used (div = 0x0100 -> 257 clocks/bit).
        spi_write(A_BAUD_LO, 8'h00);
        spi_write(A_BAUD_HI, 8'h01);
        bitclk = 257;
        n = ntx; spi_write(A_UART, 8'hC9); wait_tx(n); check(txq[n], 8'hC9, "uart tx div 0x100");
        spi_write(A_BAUD_HI, 8'h00);
        spi_write(A_BAUD_LO, 8'd15);
        bitclk = 16;

        // --- UART RX ---
        uart_send(8'h5A, 1'b1);
        check(uo_out[5], 1, "rx_valid pin");
        check(uo_out[3], 0, "no irq when irq_rx_en=0");
        expect_reg(A_STATUS, 8'h02, "STATUS rx_valid");
        expect_reg(A_UART,   8'h5A, "rx data");
        expect_reg(A_STATUS, 8'h00, "rx_valid cleared by pop");
        // IRQ on receive.
        spi_write(A_CTRL, 8'h08);
        uart_send(8'hE7, 1'b1);
        check(uo_out[3], 1, "irq on rx");
        expect_reg(A_UART, 8'hE7, "rx data 2");
        check(uo_out[3], 0, "irq cleared by pop");
        spi_write(A_CTRL, 8'h00);
        // Overrun: two bytes without a read.
        uart_send(8'h01, 1'b1);
        uart_send(8'h02, 1'b1);
        expect_reg(A_STATUS, 8'h0A, "STATUS overrun+valid");
        expect_reg(A_STATUS, 8'h02, "overrun cleared by read");
        expect_reg(A_UART,   8'h02, "newest byte kept");
        // Overrun that happens *during* a STATUS read (after the value was
        // captured, before the read completes) must not be lost.
        uart_send(8'h03, 1'b1);
        fork
            uart_send(8'h04, 1'b1);
            begin repeat (50) @(negedge clk); spi_read(A_STATUS, r); end
        join
        check(r, 8'h02, "STATUS before late overrun");
        expect_reg(A_STATUS, 8'h0A, "late overrun preserved");
        expect_reg(A_UART,   8'h04, "late byte kept");
        // Framing error.
        uart_send(8'h99, 1'b0);
        expect_reg(A_STATUS, 8'h20, "STATUS frame_err");
        expect_reg(A_STATUS, 8'h00, "frame_err cleared");
        uart_send(8'h66, 1'b1);
        expect_reg(A_UART, 8'h66, "rx after framing error");

        // --- UART loopback through the chip pins (uo_out[0] -> ui_in[0]) ---
        n = ntx;
        spi_write(A_UART, 8'h3E);
        // Feed the monitored TX byte back into RX.
        wait_tx(n);
        uart_send(txq[n], 1'b1);
        expect_reg(A_UART, 8'h3E, "pin loopback");

        // --- streaming CRC: UART RX autofeed, CRC-16/MODBUS ---
        crc_setup(16'h8005, 16'hFFFF, 16'h0000, 5'b00111);
        for (i = 0; i < 9; i = i + 1) uart_send(8'h31 + i[7:0], 1'b1);
        crc_expect(16'h4B37, "autofeed CRC-16/MODBUS");
        expect_reg(A_UART, 8'h39, "autofeed last byte");
        spi_read(A_STATUS, r);
        // Autofeed off: received bytes do not touch the CRC.
        spi_write(A_CTRL, 8'h03);
        uart_send(8'hAB, 1'b1);
        crc_expect(16'h4B37, "autofeed disabled");
        spi_write(A_CTRL, 8'h00);

        // --- asynchronous reset restores defaults ---
        spi_write(A_GPIO_OE, 8'hFF);
        @(negedge clk) rst_n = 1'b0;
        repeat (3) @(negedge clk);
        check(uio_oe, 8'h00, "reset clears uio_oe");
        rst_n = 1'b1;
        bitclk = 87;
        repeat (3) @(negedge clk);
        expect_reg(A_BAUD_LO, 8'd86, "BAUD after reset");
        expect_reg(A_POLY_HI, 8'h10, "POLY after reset");

        if (errors == 0) $display("PASS tb_top: %0d checks, %0d UART bytes sent", checks, ntx);
        else             $display("FAIL tb_top: %0d errors / %0d checks", errors, checks);
        $finish;
    end

    initial begin
        #500_000_000;
        $display("FAIL tb_top: timeout");
        $finish;
    end
endmodule
`default_nettype wire
