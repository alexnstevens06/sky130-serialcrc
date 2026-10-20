"""uart_tx / uart_rx framing, including 1 clock/bit and baud tolerance."""

import cocotb
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge

from simlib import Scoreboard, apply_reset

class _Mon:
    def __init__(self, dut):
        self.dut = dut
        self.bytes = []
        self.frame_errs = 0

    async def run(self):
        while True:
            await RisingEdge(self.dut.clk)
            await ReadOnly()
            if int(self.dut.valid.value):
                self.bytes.append(int(self.dut.rx_data.value))
            if int(self.dut.frame_err.value):
                self.frame_errs += 1


async def boot(dut):
    dut.div.value = 4
    dut.start.value = 0
    dut.data.value = 0
    dut.use_line.value = 0
    dut.line_in.value = 1
    await apply_reset(dut)
    mon = _Mon(dut)
    cocotb.start_soon(mon.run())
    await RisingEdge(dut.clk)
    return mon


async def send_tx(dut, byte):
    while int(dut.busy.value):
        await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.data.value = byte
    dut.start.value = 1
    await FallingEdge(dut.clk)
    dut.start.value = 0


async def wait_bytes(dut, mon, count, timeout):
    for _ in range(timeout):
        if len(mon.bytes) >= count:
            return
        await RisingEdge(dut.clk)
    raise AssertionError(
        f"RX timeout: got {['0x%02X' % b for b in mon.bytes]}, want {count}, "
        f"frame_err={mon.frame_errs}"
    )


async def drive_frames(dut, frames, bitclk, release=True):
    dut.use_line.value = 1
    await FallingEdge(dut.clk)
    for byte, stop in frames:
        dut.line_in.value = 0
        for _ in range(bitclk):
            await FallingEdge(dut.clk)
        for index in range(8):
            dut.line_in.value = (byte >> index) & 1
            for _ in range(bitclk):
                await FallingEdge(dut.clk)
        dut.line_in.value = stop
        for _ in range(bitclk):
            await FallingEdge(dut.clk)
    if release:
        dut.line_in.value = 1


async def low_cycles(dut, limit):
    for _ in range(limit):
        if int(dut.tx.value) == 0:
            break
        await FallingEdge(dut.clk)
    else:
        raise AssertionError("tx never fell")
    count = 0
    for _ in range(limit):
        if int(dut.tx.value) == 1:
            return count
        count += 1
        await FallingEdge(dut.clk)
    raise AssertionError("tx stayed low")


async def busy_cycles(dut, limit):
    for _ in range(limit):
        if int(dut.busy.value) == 1:
            break
        await FallingEdge(dut.clk)
    else:
        raise AssertionError("busy never rose")
    count = 0
    for _ in range(limit):
        if int(dut.busy.value) == 0:
            return count
        count += 1
        await FallingEdge(dut.clk)
    raise AssertionError("busy stayed high")


@cocotb.test(timeout_time=50, timeout_unit="ms")
async def test_loopback_baud_edges(dut):
    sb = Scoreboard()
    mon = await boot(dut)
    sb.eq(dut.tx.value, 1, "idle high")
    for div in (0, 1, 2, 3):
        dut.div.value = div
        dut.use_line.value = 0
        for byte in range(256):
            mon.bytes.clear()
            mon.frame_errs = 0
            await send_tx(dut, byte)
            await wait_bytes(dut, mon, 1, (div + 1) * 20 + 40)
            sb.eq(mon.bytes[-1], byte, f"loop div {div} byte 0x{byte:02X}")
            sb.eq(mon.frame_errs, 0, f"no frame error div {div}")
    for div, byte in ((15, 0x96), (255, 0x5A), (0x101, 0xC9), (0x7FF, 0x3C)):
        dut.div.value = div
        mon.bytes.clear()
        await send_tx(dut, byte)
        await wait_bytes(dut, mon, 1, (div + 1) * 14 + 40)
        sb.eq(mon.bytes[-1], byte, f"loop div {div}")
    sb.note()


@cocotb.test(timeout_time=20, timeout_unit="ms")
async def test_bit_timing_and_busy_write(dut):
    sb = Scoreboard()
    mon = await boot(dut)
    for div in (0, 1, 4, 20, 255):
        dut.div.value = div
        limit = (div + 1) * 20 + 50
        low = cocotb.start_soon(low_cycles(dut, limit))
        busy = cocotb.start_soon(busy_cycles(dut, limit))
        await send_tx(dut, 0x01)
        sb.eq(await low, div + 1, f"start bit clocks div {div}")
        sb.eq(await busy, 10 * (div + 1), f"busy clocks div {div}")
        while int(dut.busy.value):
            await RisingEdge(dut.clk)

    dut.div.value = 20
    mon.bytes.clear()
    await send_tx(dut, 0x12)
    await ClockCycles(dut.clk, 30)
    await FallingEdge(dut.clk)
    dut.data.value = 0x34
    dut.start.value = 1
    await FallingEdge(dut.clk)
    dut.start.value = 0
    await wait_bytes(dut, mon, 1, 21 * 16)
    while int(dut.busy.value):
        await RisingEdge(dut.clk)
    await ClockCycles(dut.clk, 21 * 4)
    sb.eq(len(mon.bytes), 1, "start while busy ignored")
    sb.eq(mon.bytes[0], 0x12, "first byte kept")
    sb.note()


@cocotb.test(timeout_time=10, timeout_unit="ms")
async def test_framing_false_start_and_baud_tolerance(dut):
    sb = Scoreboard()
    mon = await boot(dut)

    dut.div.value = 15
    dut.use_line.value = 1
    dut.line_in.value = 1
    await FallingEdge(dut.clk)
    dut.line_in.value = 0
    for _ in range(4):
        await FallingEdge(dut.clk)
    dut.line_in.value = 1
    await ClockCycles(dut.clk, 16 * 12)
    sb.eq(len(mon.bytes), 0, "false start rejected")
    sb.eq(mon.frame_errs, 0, "glitch is not a framing error")

    for div in (0, 15):
        bitclk = div + 1
        dut.div.value = div
        mon.bytes.clear()
        mon.frame_errs = 0
        await drive_frames(dut, [(0x3C, 0)], bitclk, release=False)
        for _ in range(bitclk * 3):
            await FallingEdge(dut.clk)
        dut.line_in.value = 1
        await ClockCycles(dut.clk, bitclk * 4)
        sb.eq(len(mon.bytes), 0, f"bad frame dropped div {div}")
        sb.eq(mon.frame_errs, 1, f"framing error div {div}")
        mon.bytes.clear()
        mon.frame_errs = 0
        await drive_frames(dut, [(0x5A, 1)], bitclk)
        await wait_bytes(dut, mon, 1, bitclk * 20 + 30)
        sb.eq(mon.bytes[-1], 0x5A, f"recover div {div}")

    dut.div.value = 31
    mon.bytes.clear()
    mon.frame_errs = 0
    await drive_frames(dut, [(0xC3, 1)], 33)
    await wait_bytes(dut, mon, 1, 33 * 16)
    sb.eq(mon.bytes[-1], 0xC3, "baud +3%")
    await drive_frames(dut, [(0x3C, 1)], 31)
    await wait_bytes(dut, mon, 2, 33 * 16)
    sb.eq(mon.bytes[-1], 0x3C, "baud -3%")
    sb.eq(mon.frame_errs, 0, "tolerance has no framing error")

    mon.bytes.clear()
    mon.frame_errs = 0
    await drive_frames(dut, [(0x55, 1)], 8)
    await ClockCycles(dut.clk, 32 * 4)
    clean = mon.bytes == [0x55] and mon.frame_errs == 0
    sb.true(not clean, "4x fast frame must not look like a clean 0x55")

    # The fast frame above can leave the receiver mid-byte. Reset before the
    # back-to-back check so that case is only about contiguous frames.
    dut.rst_n.value = 0
    dut.line_in.value = 1
    dut.use_line.value = 1
    await ClockCycles(dut.clk, 2)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    mon.bytes.clear()
    mon.frame_errs = 0
    dut.div.value = 0
    frames = [(0x80 >> i, 1) for i in range(8)]
    await drive_frames(dut, frames, 1)
    await wait_bytes(dut, mon, 8, 200)
    sb.eq(len(mon.bytes), 8, "back-to-back count")
    sb.eq(mon.bytes[-1], 0x01, "back-to-back last")
    sb.true(mon.bytes == [0x80 >> i for i in range(8)], f"back-to-back data {mon.bytes}")
    sb.note()


def center_cycle(div):
    """Stop-bit sample, 0-based from the first cycle the start bit is seen."""
    return ((div + 1) >> 1) + 9 * (div + 1)


@cocotb.test(timeout_time=10, timeout_unit="ms")
async def test_even_divisor_sample_phase(dut):
    """Even divisors sample the center of the bit, not one cycle later."""
    sb = Scoreboard()
    mon = await boot(dut)
    for div in (1, 2, 3, 4, 6):
        dut.div.value = div
        dut.use_line.value = 1
        dut.line_in.value = 1
        byte = 0xA5
        bits = [0] + [((byte >> index) & 1) for index in range(8)] + [1]
        await FallingEdge(dut.clk)
        saw = None
        cycle = 0
        for bit in bits:
            dut.line_in.value = bit
            for _ in range(div + 1):
                await RisingEdge(dut.clk)
                await ReadOnly()
                if saw is None and int(dut.valid.value):
                    saw = cycle
                    sb.eq(int(dut.rx_data.value), byte, f"sample data div {div}")
                cycle += 1
                await FallingEdge(dut.clk)
        sb.eq(saw, center_cycle(div), f"sample cycle div {div}")

    # The last cycle of a div-2 start bit is past the center. Raising the
    # line there used to look like a false start.
    dut.div.value = 2
    dut.use_line.value = 1
    dut.line_in.value = 1
    mon.bytes.clear()
    mon.frame_errs = 0
    await FallingEdge(dut.clk)
    for bi in range(10):
        for ti in range(3):
            if bi == 0:
                dut.line_in.value = int(ti == 2)
            else:
                dut.line_in.value = 1
            await FallingEdge(dut.clk)
    dut.line_in.value = 1
    await wait_bytes(dut, mon, 1, 80)
    sb.eq(mon.bytes[-1], 0xFF, "even divisor keeps a start bit with a late high")
    sb.eq(mon.frame_errs, 0, "late start-bit high is not a framing error")
    sb.note()
