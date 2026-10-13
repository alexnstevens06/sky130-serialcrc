## How it works

SerialCRC is a small serial peripheral controlled over SPI (mode 0). Every SPI
transaction is 16 bits: a command byte `{rw, addr[6:0]}` followed by a data byte
(written by the host, or returned on MISO for reads). The register file controls:

- an 8N1 **UART** with a 16-bit baud divisor (default 115200 baud at 66 MHz),
  false-start rejection, framing-error and overrun flags;
- a **programmable CRC-16 engine** (polynomial, init, final XOR, input and output
  reflection), one bit per clock, which covers CRC-16/CCITT-FALSE, ARC, MODBUS,
  XMODEM, KERMIT, X-25 and others;
- **autofeed**: every byte received on the UART can also be streamed into the
  CRC, so the chip can check a packet as it arrives;
- 8 general-purpose outputs on the bidirectional pins and an IRQ output.

See `SPEC.md` for the full register map.

## How to test

1. Clock at up to 66 MHz and release `rst_n`. SCLK must be at most f_clk / 8 (8.25 MHz at 66 MHz).
2. Read register 0x00 over SPI: it returns `0xA5`.
3. Default CRC is CRC-16/CCITT-FALSE: write `0x01` to `0x0D` (load init), write
   the bytes `"123456789"` to `0x0C` one at a time, then read `0x0E`/`0x0F` and
   expect `0xB1`/`0x29`.
4. Connect a USB-UART at 115200 8N1: writing `0x05` sends a byte, and received
   bytes are read back from `0x05`.

## External hardware

An SPI master (e.g. the RP2040 on the TinyTapeout demo board, or any
microcontroller) and optionally a 3.3 V USB-UART adapter.
