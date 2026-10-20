"""Pin-level tests: SPI register file, UART, CRC-16, and reset."""

import random

import cocotb
from cocotb.triggers import FallingEdge, Timer

from chip_driver import (
    A_BAUD_HI,
    A_BAUD_LO,
    A_CRC_CMD,
    A_CRC_DATA,
    A_CRC_HI,
    A_CRC_LO,
    A_CTRL,
    A_GPIO,
    A_GPIO_OE,
    A_ID,
    A_INIT_HI,
    A_INIT_LO,
    A_POLY_HI,
    A_POLY_LO,
    A_STATUS,
    A_UART,
    A_XOR_HI,
    A_XOR_LO,
    fresh,
)
from crc_model import CATALOGUE, CHECK_MESSAGE, crc16

# Default parameters are CLK_HZ=66_000_000 and BAUD=115200, so the baud
# reset value is 572 (0x023C), not the regfile parameter default of 86.
BAUD_RESET = 572

RW = (
    (A_CTRL, 0x1F),
    (A_BAUD_LO, 0xFF),
    (A_BAUD_HI, 0xFF),
    (A_POLY_LO, 0xFF),
    (A_POLY_HI, 0xFF),
    (A_INIT_LO, 0xFF),
    (A_INIT_HI, 0xFF),
    (A_XOR_LO, 0xFF),
    (A_XOR_HI, 0xFF),
    (A_GPIO, 0xFF),
    (A_GPIO_OE, 0xFF),
)


async def load_crc(chip, poly, init, xorout, ctrl):
    await chip.write(A_POLY_LO, poly & 0xFF)
    await chip.write(A_POLY_HI, poly >> 8)
    await chip.write(A_INIT_LO, init & 0xFF)
    await chip.write(A_INIT_HI, init >> 8)
    await chip.write(A_XOR_LO, xorout & 0xFF)
    await chip.write(A_XOR_HI, xorout >> 8)
    await chip.write(A_CTRL, ctrl)
    await chip.write(A_CRC_CMD, 0x01)


async def read_crc(chip):
    lo = await chip.read(A_CRC_LO)
    hi = await chip.read(A_CRC_HI)
    return (hi << 8) | lo


@cocotb.test(timeout_time=20, timeout_unit="ms")
async def test_reset_defaults(dut):
    chip = fresh(dut)
    await chip.boot()
    chip.sb.eq(dut.uo_out.value, 0x01, "uo_out after reset")
    chip.sb.eq(dut.uio_out.value, 0x00, "uio_out after reset")
    chip.sb.eq(dut.uio_oe.value, 0x00, "uio_oe after reset")
    await chip.expect(A_ID, 0xA5, "ID")
    await chip.expect(A_CTRL, 0x00, "CTRL")
    await chip.expect(A_STATUS, 0x00, "STATUS")
    await chip.expect(A_BAUD_LO, BAUD_RESET & 0xFF, "BAUD_LO")
    await chip.expect(A_BAUD_HI, BAUD_RESET >> 8, "BAUD_HI")
    await chip.expect(A_UART, 0x00, "UART_DATA")
    await chip.expect(A_POLY_LO, 0x21, "POLY_LO")
    await chip.expect(A_POLY_HI, 0x10, "POLY_HI")
    await chip.expect(A_INIT_LO, 0xFF, "INIT_LO")
    await chip.expect(A_INIT_HI, 0xFF, "INIT_HI")
    await chip.expect(A_XOR_LO, 0x00, "XOR_LO")
    await chip.expect(A_XOR_HI, 0x00, "XOR_HI")
    await chip.expect(A_CRC_LO, 0xFF, "CRC_LO")
    await chip.expect(A_CRC_HI, 0xFF, "CRC_HI")
    await chip.expect(A_GPIO, 0x00, "GPIO")
    await chip.expect(A_GPIO_OE, 0x00, "GPIO_OE")
    for addr in (0x12, 0x40, 0x7F):
        await chip.expect(addr, 0x00, f"unmapped 0x{addr:02X}")
    chip.sb.note()


@cocotb.test(timeout_time=50, timeout_unit="ms")
async def test_spi_register_access(dut):
    chip = fresh(dut)
    await chip.boot()
    for pattern in (0x00, 0xFF, 0x55, 0xAA):
        for addr, mask in RW:
            await chip.write(addr, pattern)
            await chip.expect(addr, pattern & mask, f"readback 0x{addr:02X}")
    for bit in range(8):
        await chip.write(A_GPIO, 1 << bit)
        await chip.expect(A_GPIO, 1 << bit, f"GPIO walking 1 bit {bit}")
    await chip.write(A_GPIO, 0x3C)
    await chip.write(A_GPIO_OE, 0xF0)
    chip.sb.eq(dut.uio_out.value, 0x3C, "uio_out")
    chip.sb.eq(dut.uio_oe.value, 0xF0, "uio_oe")

    await chip.write(A_ID, 0x00)
    await chip.expect(A_ID, 0xA5, "ID is read-only")
    crc_lo = await chip.read(A_CRC_LO)
    await chip.write(A_CRC_LO, crc_lo ^ 0xFF)
    await chip.expect(A_CRC_LO, crc_lo, "CRC_LO is read-only")
    await chip.write(0x7F, 0xFF)
    await chip.expect(0x7F, 0x00, "unmapped write ignored")
    await chip.expect(A_GPIO, 0x3C, "unmapped write did not alias GPIO")

    await chip.spi_xfer(A_GPIO, 0xFF, nbits=11)
    await chip.spi_xfer(A_GPIO, 0xFF, nbits=15)
    await chip.spi_xfer(0x80 | A_GPIO, 0x00, nbits=15)
    await chip.expect(A_GPIO, 0x3C, "aborted SPI access ignored")

    highs = 0
    for _ in range(32):
        await FallingEdge(dut.clk)
        highs += chip.pin(1)
    chip.sb.eq(highs, 0, "MISO stays low while CS is high")
    chip.sb.note()


@cocotb.test(timeout_time=30, timeout_unit="ms")
async def test_uart_tx_timing(dut):
    chip = fresh(dut)
    await chip.boot()
    for div in (0, 1, 15):
        await chip.set_baud(div)
        low = cocotb.start_soon(chip.count_low_pulse())
        busy = cocotb.start_soon(chip.count_busy())
        await chip.write(A_UART, 0x01)
        chip.sb.eq(await low, div + 1, f"TX start width div {div}")
        chip.sb.eq(await busy, 10 * (div + 1), f"TX busy width div {div}")

    await chip.set_baud(15)
    captured = cocotb.start_soon(chip.capture_tx(16))
    await chip.write(A_UART, 0xA5)
    byte, stop = await captured
    chip.sb.eq(byte, 0xA5, "TX byte 0xA5")
    chip.sb.eq(stop, 1, "TX stop bit")

    await chip.set_baud(63)
    captured = cocotb.start_soon(chip.capture_tx(64))
    await chip.write(A_UART, 0x11)
    chip.sb.eq(chip.pin(4), 1, "tx_busy pin")
    await chip.write(A_UART, 0x22)
    byte, stop = await captured
    chip.sb.eq(byte, 0x11, "write while TX busy ignored")
    chip.sb.eq(stop, 1, "busy-ignored frame still stops")
    for _ in range(64):
        await FallingEdge(dut.clk)
        if chip.pin(0) == 0:
            raise AssertionError("second TX frame was not ignored")
    chip.sb.true(True, "no second TX frame")
    chip.sb.note()


@cocotb.test(timeout_time=80, timeout_unit="ms")
async def test_uart_rx_baud_and_framing(dut):
    chip = fresh(dut)
    await chip.boot()
    patterns = (0x00, 0xFF, 0x55, 0xAA, 0x01, 0x80, 0xA5)
    for div in (0, 1, 2, 3, 15):
        await chip.set_baud(div)
        for byte in patterns:
            await chip.uart_send(byte, div + 1)
            await chip.expect(A_UART, byte, f"RX div {div} 0x{byte:02X}")
    await chip.set_baud(0x101)
    await chip.uart_send(0xC9, 0x102)
    await chip.expect(A_UART, 0xC9, "RX div 0x101")

    await chip.set_baud(31)
    await chip.uart_send(0xC3, 33)
    await chip.expect(A_UART, 0xC3, "RX baud +3%")
    await chip.uart_send(0x3C, 31)
    await chip.expect(A_UART, 0x3C, "RX baud -3%")

    await chip.uart_send(0x55, 8)
    status = await chip.read(A_STATUS)
    data = await chip.read(A_UART)
    valid = (status >> 1) & 1
    frame_err = (status >> 5) & 1
    chip.sb.true(
        not (valid and data == 0x55 and not frame_err),
        "4x fast frame must not look like a clean 0x55",
    )

    # Let the too-fast frame finish, then drop whatever it left in RX/STATUS.
    for _ in range(32 * 16):
        await FallingEdge(dut.clk)
    await chip.read(A_STATUS)
    await chip.read(A_UART)
    await chip.read(A_STATUS)

    await chip.set_baud(15)
    await chip.uart_send(0x99, 16, stop=0)
    await chip.expect(A_STATUS, 0x20, "framing error")
    await chip.expect(A_STATUS, 0x00, "framing error clears")
    await chip.uart_send(0x66, 16)
    await chip.expect(A_UART, 0x66, "RX after framing error")

    await FallingEdge(dut.clk)
    chip.setb(0, 0)
    for _ in range(4):
        await FallingEdge(dut.clk)
    chip.setb(0, 1)
    for _ in range(16 * 14):
        await FallingEdge(dut.clk)
    await chip.expect(A_STATUS, 0x00, "false start ignored")

    await chip.uart_send(0x01, 16)
    await chip.uart_send(0x02, 16)
    await chip.expect(A_STATUS, 0x0A, "overrun")
    await chip.expect(A_UART, 0x02, "newest byte kept")

    await chip.write(A_CTRL, 0x08)
    await chip.uart_send(0xE7, 16)
    chip.sb.eq(chip.pin(3), 1, "IRQ on RX")
    await chip.expect(A_UART, 0xE7, "IRQ byte")
    chip.sb.eq(chip.pin(3), 0, "IRQ clears when the byte is popped")
    chip.sb.note()


@cocotb.test(timeout_time=20, timeout_unit="ms")
async def test_uart_pop_during_spi_read(dut):
    chip = fresh(dut)
    await chip.boot()
    await chip.set_baud(0)
    await chip.uart_send(0xA5, 1)
    await chip.expect(A_UART, 0xA5, "div 0 through the pin synchronizer")

    await chip.uart_send(0x11, 1)

    async def newer_byte():
        await chip.uart_send(0x22, 1)

    got = await chip.spi_xfer(0x80 | A_UART, 0x00, after_addr=newer_byte)
    chip.sb.eq(got, 0x11, "SPI read returns the captured byte")
    chip.sb.eq(chip.pin(5), 1, "newer byte stays pending")
    await chip.expect(A_STATUS, 0x02, "newer byte is not an overrun")
    await chip.expect(A_UART, 0x22, "newer byte is readable")
    chip.sb.note()


@cocotb.test(timeout_time=80, timeout_unit="ms")
async def test_crc_presets_random_and_autofeed(dut):
    chip = fresh(dut)
    await chip.boot()
    for name, poly, init, xorout, refin, refout, expect in CATALOGUE:
        ctrl = (1 if refin else 0) | (2 if refout else 0)
        await load_crc(chip, poly, init, xorout, ctrl)
        for byte in CHECK_MESSAGE:
            await chip.write(A_CRC_DATA, byte)
        chip.sb.eq(await read_crc(chip), expect, name)

    rng = random.Random(0x5EED)
    for case in range(8):
        poly = rng.randrange(0x10000)
        init = rng.randrange(0x10000)
        xorout = rng.randrange(0x10000)
        refin = bool(rng.getrandbits(1))
        refout = bool(rng.getrandbits(1))
        data = bytes(rng.randrange(256) for _ in range(rng.randrange(0, 9)))
        ctrl = (1 if refin else 0) | (2 if refout else 0)
        await load_crc(chip, poly, init, xorout, ctrl)
        for byte in data:
            await chip.write(A_CRC_DATA, byte)
        expect = crc16(data, poly, init, xorout, refin, refout)
        chip.sb.eq(await read_crc(chip), expect, f"SPI random[{case}]")

    await chip.read(A_STATUS)
    await load_crc(chip, 0x1021, 0xFFFF, 0, 0x10)
    chip.sb.eq(chip.pin(3), 0, "IRQ low before CRC")
    await chip.write(A_CRC_DATA, 0x42)
    chip.sb.eq(chip.pin(3), 1, "IRQ on crc_done")
    await chip.expect(A_STATUS, 0x10, "STATUS crc_done")
    chip.sb.eq(chip.pin(3), 0, "IRQ clears on STATUS read")
    before = await chip.read(A_CRC_LO)
    await chip.write(A_CRC_CMD, 0x00)
    await chip.expect(A_CRC_LO, before, "CRC_CMD bit0=0 is a no-op")

    await chip.set_baud(7)
    await load_crc(chip, 0x8005, 0xFFFF, 0, 0x07)
    for byte in CHECK_MESSAGE:
        await chip.uart_send(byte, 8)
    chip.sb.eq(await read_crc(chip), 0x4B37, "autofeed CRC-16/MODBUS")
    await chip.expect(A_UART, CHECK_MESSAGE[-1], "autofeed keeps the RX byte")
    await chip.write(A_CTRL, 0x03)
    await chip.uart_send(0xAB, 8)
    chip.sb.eq(await read_crc(chip), 0x4B37, "autofeed disabled")
    chip.sb.note()


@cocotb.test(timeout_time=20, timeout_unit="ms")
async def test_reset_during_activity(dut):
    chip = fresh(dut)
    await chip.boot()
    await chip.write(A_GPIO, 0xA5)
    await chip.write(A_GPIO_OE, 0xFF)
    await chip.write(A_CTRL, 0x1F)
    await chip.set_baud(0)
    await chip.uart_send(0x01, 1)
    await chip.uart_send(0x02, 1)
    chip.sb.eq(chip.pin(5), 1, "RX valid before reset")

    await chip.set_baud(40)
    low = cocotb.start_soon(chip.count_low_pulse())
    await chip.write(A_UART, 0x55)
    chip.sb.eq(await low, 41, "TX was running when reset hit")
    chip.dut.rst_n.value = 0
    await Timer(1, unit="ns")
    chip.sb.eq(chip.pin(0), 1, "reset forces TX idle high")
    chip.sb.eq(chip.pin(4), 0, "reset clears tx_busy")
    chip.sb.eq(chip.pin(5), 0, "reset clears rx_valid")
    chip.ui = 0x05
    chip.drive()
    for _ in range(3):
        await FallingEdge(dut.clk)
    chip.dut.rst_n.value = 1
    for _ in range(6):
        await FallingEdge(dut.clk)

    chip.sb.eq(dut.uo_out.value, 0x01, "pins idle after reset")
    chip.sb.eq(dut.uio_oe.value, 0x00, "GPIO_OE cleared")
    await chip.expect(A_BAUD_LO, BAUD_RESET & 0xFF, "BAUD_LO restored")
    await chip.expect(A_BAUD_HI, BAUD_RESET >> 8, "BAUD_HI restored")
    await chip.expect(A_CTRL, 0x00, "CTRL restored")
    await chip.expect(A_GPIO, 0x00, "GPIO restored")
    await chip.expect(A_STATUS, 0x00, "sticky flags cleared by reset")
    await chip.expect(A_POLY_HI, 0x10, "POLY restored")
    await chip.expect(A_ID, 0xA5, "ID after reset")

    await chip.write(A_GPIO, 0x5A)
    await FallingEdge(dut.clk)
    chip.setb(2, 0)
    for _ in range(chip.half):
        await FallingEdge(dut.clk)
    # 10 of the 16 bits of a GPIO write, then reset. Not a completed write.
    b0 = A_GPIO & 0x7F
    b1 = 0xFF
    for k in range(10):
        bit = ((b0 >> (7 - k)) & 1) if k < 8 else ((b1 >> (15 - k)) & 1)
        chip.setb(3, bit)
        for _ in range(chip.half):
            await FallingEdge(dut.clk)
        chip.setb(1, 1)
        for _ in range(chip.half):
            await FallingEdge(dut.clk)
        chip.setb(1, 0)
    chip.dut.rst_n.value = 0
    chip.ui = 0x05
    chip.drive()
    for _ in range(3):
        await FallingEdge(dut.clk)
    chip.dut.rst_n.value = 1
    for _ in range(6):
        await FallingEdge(dut.clk)
    await chip.expect(A_GPIO, 0x00, "GPIO is the reset value after a mid-write reset")
    chip.sb.note()


@cocotb.test(timeout_time=20, timeout_unit="ms")
async def test_sclk_level_at_reset(dut):
    """SCLK high while CS is low at reset release does not shift a SPI bit."""
    chip = fresh(dut)
    await chip.boot()

    async def release(ui):
        await FallingEdge(dut.clk)
        dut.rst_n.value = 0
        chip.ui = ui
        chip.drive()
        for _ in range(4):
            await FallingEdge(dut.clk)
        dut.rst_n.value = 1
        for _ in range(8):
            await FallingEdge(dut.clk)

    await release(0x03)  # uart idle, SCLK high, CS low
    chip.setb(1, 0)
    for _ in range(chip.half):
        await FallingEdge(dut.clk)
    await chip.write(A_GPIO, 0xA5)
    await chip.expect(A_GPIO, 0xA5, "SCLK high at reset release")

    await release(0x01)  # uart idle, SCLK low, CS low
    await chip.write(A_GPIO, 0x5A)
    await chip.expect(A_GPIO, 0x5A, "SCLK low at reset release")
    chip.sb.note()
