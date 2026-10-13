// tt_um_alexstevens_serialcrc
// SPI-controlled UART + programmable CRC-16 accelerator, TinyTapeout pinout.
// Copyright (c) 2026 Alex Stevens. SPDX-License-Identifier: MIT
`default_nettype none
module tt_um_alexstevens_serialcrc #(
    parameter CLK_HZ = 66_000_000,
    parameter BAUD   = 115_200
) (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
    localparam integer DIV = (CLK_HZ + BAUD / 2) / BAUD - 1;
    localparam [15:0] BAUD_RESET = DIV[15:0];

    // ---- input synchronizers ----
    wire uart_rx, spi_sclk, spi_cs_n, spi_mosi;
    sync2 #(.RESET_VAL(1'b1)) u_sync_rx   (.clk(clk), .rst_n(rst_n), .d(ui_in[0]), .q(uart_rx));
    sync2 #(.RESET_VAL(1'b0)) u_sync_sclk (.clk(clk), .rst_n(rst_n), .d(ui_in[1]), .q(spi_sclk));
    sync2 #(.RESET_VAL(1'b1)) u_sync_cs   (.clk(clk), .rst_n(rst_n), .d(ui_in[2]), .q(spi_cs_n));
    sync2 #(.RESET_VAL(1'b0)) u_sync_mosi (.clk(clk), .rst_n(rst_n), .d(ui_in[3]), .q(spi_mosi));

    // ---- SPI slave ----
    wire [6:0] bus_addr;
    wire [7:0] bus_rdata, bus_wdata;
    wire       bus_rd_req, bus_rd_done, bus_wr;
    wire       spi_miso;
    spi_slave u_spi (
        .clk(clk), .rst_n(rst_n),
        .sclk(spi_sclk), .cs_n(spi_cs_n), .mosi(spi_mosi), .miso(spi_miso),
        .addr(bus_addr), .rd_req(bus_rd_req), .rd_done(bus_rd_done),
        .rd_data(bus_rdata), .wr_en(bus_wr), .wr_data(bus_wdata)
    );

    // ---- register file ----
    wire [15:0] baud_div, crc_poly, crc_init, crc_xorout, crc_result;
    wire        tx_start, tx_busy, rx_strobe, rx_frame_err, rx_valid;
    wire [7:0]  tx_data, rx_byte, crc_din;
    wire        crc_refin, crc_refout, crc_clear, crc_start, crc_busy, crc_done;
    wire        irq;
    regfile #(.BAUD_RESET(BAUD_RESET)) u_regs (
        .clk(clk), .rst_n(rst_n),
        .addr(bus_addr), .rd_req(bus_rd_req), .rd_done(bus_rd_done),
        .rd_data(bus_rdata), .wr_en(bus_wr), .wr_data(bus_wdata),
        .baud_div(baud_div), .tx_start(tx_start), .tx_data(tx_data),
        .tx_busy(tx_busy), .rx_strobe(rx_strobe), .rx_byte(rx_byte),
        .rx_frame_err(rx_frame_err), .rx_valid(rx_valid),
        .crc_poly(crc_poly), .crc_init(crc_init), .crc_xorout(crc_xorout),
        .crc_refin(crc_refin), .crc_refout(crc_refout), .crc_clear(crc_clear),
        .crc_start(crc_start), .crc_din(crc_din), .crc_busy(crc_busy),
        .crc_done_pulse(crc_done), .crc_result(crc_result),
        .gpio_out(uio_out), .gpio_oe(uio_oe), .irq(irq)
    );

    // ---- UART ----
    wire uart_tx;
    uart_tx u_tx (
        .clk(clk), .rst_n(rst_n), .div(baud_div),
        .start(tx_start), .data(tx_data), .tx(uart_tx), .busy(tx_busy)
    );
    uart_rx u_rx (
        .clk(clk), .rst_n(rst_n), .div(baud_div), .rx(uart_rx),
        .valid(rx_strobe), .data(rx_byte), .frame_err(rx_frame_err)
    );

    // ---- CRC accelerator ----
    crc16_engine #(.WIDTH(16), .RESET_VAL(16'hFFFF)) u_crc (
        .clk(clk), .rst_n(rst_n),
        .poly(crc_poly), .init(crc_init), .xorout(crc_xorout),
        .refin(crc_refin), .refout(crc_refout),
        .clear(crc_clear), .start(crc_start), .din(crc_din),
        .busy(crc_busy), .done(crc_done), .result(crc_result)
    );

    assign uo_out = {2'b00, rx_valid, tx_busy, irq, crc_busy, spi_miso, uart_tx};

    // ena is always 1 when the design is selected; unused inputs tied off.
    /* verilator lint_off UNUSEDSIGNAL */
    wire _unused = &{1'b0, ena, ui_in[7:4], uio_in};
    /* verilator lint_on UNUSEDSIGNAL */
endmodule
`default_nettype wire
