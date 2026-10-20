"""Pin-level SPI master and UART driver for tt_um_alexstevens_serialcrc.

SPI is mode 0, MSB first, with four clocks per SCLK half-period (the spec
minimum, f_clk = 8 * f_sclk). Edges are driven on the falling edge of clk,
matching the Icarus testbench, so the 2-flop synchronizers see a stable pin.
"""

from cocotb.triggers import FallingEdge

from simlib import Scoreboard, clocked


A_ID = 0x00
A_CTRL = 0x01
A_STATUS = 0x02
A_BAUD_LO = 0x03
A_BAUD_HI = 0x04
A_UART = 0x05
A_POLY_LO = 0x06
A_POLY_HI = 0x07
A_INIT_LO = 0x08
A_INIT_HI = 0x09
A_XOR_LO = 0x0A
A_XOR_HI = 0x0B
A_CRC_DATA = 0x0C
A_CRC_CMD = 0x0D
A_CRC_LO = 0x0E
A_CRC_HI = 0x0F
A_GPIO = 0x10
A_GPIO_OE = 0x11


class Chip:
    def __init__(self, dut, scoreboard):
        self.dut = dut
        self.sb = scoreboard
        self.ui = 0x05
        self.half = 4

    def drive(self):
        self.dut.ui_in.value = self.ui

    def setb(self, index, value):
        if value:
            self.ui |= 1 << index
        else:
            self.ui &= ~(1 << index)
        self.drive()

    def pin(self, index):
        return (int(self.dut.uo_out.value) >> index) & 1

    async def boot(self):
        self.dut.ena.value = 1
        self.dut.uio_in.value = 0
        self.ui = 0x05
        self.drive()
        self.dut.rst_n.value = 0
        await clocked(self.dut)
        for _ in range(4):
            await FallingEdge(self.dut.clk)
        self.dut.rst_n.value = 1
        for _ in range(6):
            await FallingEdge(self.dut.clk)

    async def spi_xfer(self, b0, b1, nbits=16, after_addr=None):
        rd = 0
        await FallingEdge(self.dut.clk)
        self.setb(2, 0)
        for _ in range(self.half):
            await FallingEdge(self.dut.clk)
        for k in range(nbits):
            if k == 8 and after_addr is not None:
                await after_addr()
            bit = ((b0 >> (7 - k)) & 1) if k < 8 else ((b1 >> (15 - k)) & 1)
            self.setb(3, bit)
            for _ in range(self.half):
                await FallingEdge(self.dut.clk)
            if k >= 8:
                rd |= self.pin(1) << (15 - k)
            self.setb(1, 1)
            for _ in range(self.half):
                await FallingEdge(self.dut.clk)
            self.setb(1, 0)
        for _ in range(self.half):
            await FallingEdge(self.dut.clk)
        self.setb(2, 1)
        self.setb(3, 0)
        for _ in range(2 * self.half):
            await FallingEdge(self.dut.clk)
        return rd

    async def write(self, addr, data):
        await self.spi_xfer(addr & 0x7F, data & 0xFF)

    async def read(self, addr):
        return await self.spi_xfer(0x80 | (addr & 0x7F), 0x00)

    async def expect(self, addr, exp, what):
        self.sb.eq(await self.read(addr), exp, what)

    async def set_baud(self, div):
        await self.write(A_BAUD_LO, div & 0xFF)
        await self.write(A_BAUD_HI, (div >> 8) & 0xFF)

    async def uart_frames(self, frames, bitclk, trail=4):
        """Drive complete frames. frames is a list of (byte, stop_bit)."""
        await FallingEdge(self.dut.clk)
        for byte, stop in frames:
            self.setb(0, 0)
            for _ in range(bitclk):
                await FallingEdge(self.dut.clk)
            for index in range(8):
                self.setb(0, (byte >> index) & 1)
                for _ in range(bitclk):
                    await FallingEdge(self.dut.clk)
            self.setb(0, stop)
            for _ in range(bitclk):
                await FallingEdge(self.dut.clk)
        self.setb(0, 1)
        for _ in range(trail):
            await FallingEdge(self.dut.clk)

    async def uart_send(self, byte, bitclk, stop=1):
        await self.uart_frames([(byte, stop)], bitclk, trail=bitclk + 4)

    async def _until(self, pred, limit, what):
        for _ in range(limit):
            if pred():
                return
            await FallingEdge(self.dut.clk)
        raise AssertionError(what)

    async def count_low_pulse(self, limit=20000):
        await self._until(lambda: self.pin(0) == 0, limit, "uart_tx never fell")
        n = 0
        for _ in range(limit):
            if self.pin(0) == 1:
                return n
            n += 1
            await FallingEdge(self.dut.clk)
        raise AssertionError("uart_tx stayed low")

    async def count_busy(self, limit=200000):
        await self._until(lambda: self.pin(4) == 1, limit, "uart_tx_busy never rose")
        n = 0
        for _ in range(limit):
            if self.pin(4) == 0:
                return n
            n += 1
            await FallingEdge(self.dut.clk)
        raise AssertionError("uart_tx_busy stayed high")

    async def capture_tx(self, bitclk, limit=200000):
        await self._until(lambda: self.pin(0) == 0, limit, "uart_tx never fell")
        for _ in range(bitclk // 2):
            await FallingEdge(self.dut.clk)
        value = 0
        for index in range(8):
            for _ in range(bitclk):
                await FallingEdge(self.dut.clk)
            value |= self.pin(0) << index
        for _ in range(bitclk):
            await FallingEdge(self.dut.clk)
        return value, self.pin(0)


def fresh(dut):
    return Chip(dut, Scoreboard())
