# Design spec: tt_um_alexstevens_serialcrc

A TinyTapeout-style (1x1 tile, sky130) serial peripheral: an SPI-slave-controlled
register file fronting a UART (8N1, programmable baud) and a programmable CRC-16
accelerator. UART RX bytes can optionally stream directly into the CRC engine.

## Top module (exact TinyTapeout port list)
module tt_um_alexstevens_serialcrc (
  input  wire [7:0] ui_in, output wire [7:0] uo_out,
  input  wire [7:0] uio_in, output wire [7:0] uio_out, output wire [7:0] uio_oe,
  input  wire ena, input wire clk, input wire rst_n);

Pins:
- ui_in[0] uart_rx, ui_in[1] spi_sclk, ui_in[2] spi_cs_n, ui_in[3] spi_mosi, ui_in[7:4] unused
- uo_out[0] uart_tx (idle high), uo_out[1] spi_miso, uo_out[2] crc_busy,
  uo_out[3] irq (active high), uo_out[4] uart_tx_busy, uo_out[5] rx_valid, uo_out[7:6] 0
- uio_out = GPIO_OUT reg, uio_oe = GPIO_OE reg (general-purpose outputs)
- All async inputs (uart_rx, sclk, cs_n, mosi) pass through 2-flop synchronizers.
  SPI is oversampled by clk; requires f_clk >= 8 * f_sclk.

## SPI slave protocol (mode 0: CPOL=0, CPHA=0, MSB first)
Each transaction while cs_n low is 16 bits: byte0 = {rw, addr[6:0]} (rw=1 read, 0 write),
byte1 = write data (write) or read data shifted out on MISO (read). For reads, the slave
drives MISO with the register value during byte1, MSB first, bit changes after falling
SCLK edge (first bit valid as soon as the 8th SCLK rising edge of byte0 has been seen and
then the falling edge occurs). Register reads that have side effects (UART_DATA pop, STATUS sticky-bit clear)
take effect once, when the 16th bit of the read completes; a sticky bit is
only cleared if it was set in the value that was shifted out. A UART_DATA read
captures its byte when the address phase completes. A UART byte that arrives
before the 16th bit was not that captured value: it stays in UART_DATA with
rx_valid set, and it is not an overrun. Overrun means an unread byte was
overwritten by one that no in-flight read will return. Deasserting cs_n mid-transaction aborts it with no effect.
MISO = 0 when cs_n high.

## Register map (8-bit)
0x00 ID         RO  0xA5
0x01 CTRL       RW  [0] crc_refin (reflect each input byte), [1] crc_refout (reflect 16-bit result),
                    [2] rx_autofeed (each received UART byte is also fed to the CRC),
                    [3] irq_rx_en, [4] irq_crc_done_en. reset 0x00
0x02 STATUS     RO  [0] tx_busy, [1] rx_valid, [2] crc_busy, [3] rx_overrun (sticky, cleared by
                    reading STATUS), [4] crc_done (sticky, cleared by reading STATUS),
                    [5] frame_err (sticky, UART stop bit was low, cleared by reading STATUS)
0x03 BAUD_LO    RW  divisor low byte  (clocks per bit = {BAUD_HI,BAUD_LO}+1, so 0 is 1 clock/bit); reset value
0x04 BAUD_HI    RW  divisor high byte    gives 115200 baud at the parameter CLK_HZ (66_000_000 -> div=572; 10_000_000 -> div=86)
0x05 UART_DATA  W: start TX of byte (ignored if tx_busy). R: pop RX byte (clears rx_valid)
0x06 POLY_LO    RW  CRC polynomial (normal form, no x^16 term); reset 0x1021
0x07 POLY_HI    RW
0x08 INIT_LO    RW  CRC init value; reset 0xFFFF
0x09 INIT_HI    RW
0x0A XOROUT_LO  RW  final XOR; reset 0x0000
0x0B XOROUT_HI  RW
0x0C CRC_DATA   W   feed one byte to the CRC (2 bits/clock on both clock edges, 4 clocks, crc_busy high)
0x0D CRC_CMD    W   bit0 = 1: load CRC register with INIT
0x0E CRC_LO     RO  result low byte  (after refout + xorout)
0x0F CRC_HI     RO  result high byte
0x10 GPIO_OUT   RW
0x11 GPIO_OE    RW
other addresses read 0x00, writes ignored.
irq = (irq_rx_en & rx_valid) | (irq_crc_done_en & crc_done).
CRC presets this must reproduce: CRC-16/CCITT-FALSE ("123456789" -> 0x29B1),
CRC-16/ARC (poly 0x8005, init 0, refin, refout -> 0xBB3D),
CRC-16/MODBUS (0x8005, init 0xFFFF, refin, refout -> 0x4B37),
CRC-16/XMODEM (0x1021, init 0 -> 0x31C3).
If a CRC_DATA write arrives while busy it is ignored. If an autofeed byte and a CRC_DATA
write arrive in the same cycle, the autofeed byte wins. (At any baud divisor a UART byte
takes >= 10 clocks and the CRC needs 4, so autofeed never overruns the engine.)

## Module breakdown (rtl/)
sync2.v, spi_slave.v, uart_tx.v, uart_rx.v (mid-bit sampling, false-start rejection,
stop-bit check), crc16_engine.v (parameter WIDTH=16, dual-edge 2-bit-per-clock LFSR, runtime poly),
regfile.v, tt_um_alexstevens_serialcrc.v (top). Plain Verilog-2005 (synthesizable with
yosys + verilator lint-clean with -Wall; no `initial` in RTL).
