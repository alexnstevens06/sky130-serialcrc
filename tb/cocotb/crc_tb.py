"""crc16_engine against the Python Rocksoft model, plus busy/clear/reset."""

import random

import cocotb
from cocotb.triggers import FallingEdge, RisingEdge, Timer

from crc_model import CATALOGUE, CHECK_MESSAGE, crc16
from simlib import Scoreboard, apply_reset


async def boot(dut):
    dut.clear.value = 0
    dut.start.value = 0
    dut.din.value = 0
    dut.refin.value = 0
    dut.refout.value = 0
    dut.poly.value = 0x1021
    dut.init.value = 0xFFFF
    dut.xorout.value = 0
    await apply_reset(dut)


async def program(dut, poly, init, xorout, refin, refout):
    dut.poly.value = poly
    dut.init.value = init
    dut.xorout.value = xorout
    dut.refin.value = int(refin)
    dut.refout.value = int(refout)


async def clear(dut):
    await FallingEdge(dut.clk)
    dut.clear.value = 1
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.clear.value = 0


async def feed(dut, byte):
    await FallingEdge(dut.clk)
    dut.din.value = byte
    dut.start.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    if int(dut.busy.value) != 1:
        raise AssertionError(f"busy not set for byte 0x{byte:02X}")
    await FallingEdge(dut.clk)
    dut.start.value = 0
    saw_done = 0
    for _ in range(8):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        if int(dut.done.value):
            saw_done += 1
        if int(dut.busy.value) == 0:
            if saw_done != 1:
                raise AssertionError(f"done pulsed {saw_done} times for 0x{byte:02X}")
            return
    raise AssertionError("CRC engine stayed busy")


async def run_message(dut, data, poly, init, xorout, refin, refout):
    await program(dut, poly, init, xorout, refin, refout)
    await clear(dut)
    for byte in data:
        await feed(dut, byte)
    await Timer(1, unit="ns")
    return int(dut.result.value)


@cocotb.test(timeout_time=5, timeout_unit="ms")
async def test_catalogue(dut):
    sb = Scoreboard()
    await boot(dut)
    for name, poly, init, xorout, refin, refout, expect in CATALOGUE:
        got = await run_message(dut, CHECK_MESSAGE, poly, init, xorout, refin, refout)
        sb.eq(got, expect, name)
    sb.note()


@cocotb.test(timeout_time=20, timeout_unit="ms")
async def test_random_matches_python(dut):
    sb = Scoreboard()
    await boot(dut)
    rng = random.Random(0xC0FFEE)
    for case in range(40):
        poly = rng.randrange(0x10000)
        init = rng.randrange(0x10000)
        xorout = rng.randrange(0x10000)
        refin = bool(rng.randrange(2))
        refout = bool(rng.randrange(2))
        length = rng.randrange(0, 17)
        data = bytes(rng.randrange(256) for _ in range(length))
        expect = crc16(data, poly, init, xorout, refin, refout)
        got = await run_message(dut, data, poly, init, xorout, refin, refout)
        sb.eq(got, expect, f"random[{case}] len {length}")
    sb.note()


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def test_busy_ignores_start_and_clear_aborts(dut):
    sb = Scoreboard()
    await boot(dut)
    await program(dut, 0x1021, 0xFFFF, 0, False, False)
    await clear(dut)
    await FallingEdge(dut.clk)
    dut.din.value = 0x31
    dut.start.value = 1
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.start.value = 0
    dut.din.value = 0xFF
    dut.start.value = 1
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.start.value = 0
    saw_done = 0
    for _ in range(8):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        if int(dut.done.value):
            saw_done += 1
        if int(dut.busy.value) == 0:
            break
    else:
        raise AssertionError("CRC engine stayed busy")
    sb.eq(saw_done, 1, "one done pulse")
    expect = crc16(b"\x31", 0x1021, 0xFFFF, 0, False, False)
    sb.eq(dut.result.value, expect, "start while busy ignored")

    await FallingEdge(dut.clk)
    dut.din.value = 0x32
    dut.start.value = 1
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.start.value = 0
    dut.clear.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    sb.eq(dut.busy.value, 0, "clear cancels a byte in flight")
    sb.eq(dut.result.value, 0xFFFF, "clear reloads init")
    await FallingEdge(dut.clk)
    dut.clear.value = 0
    sb.note()


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def test_reset_clears_engine(dut):
    sb = Scoreboard()
    await boot(dut)
    await program(dut, 0x8005, 0x0000, 0x1234, True, True)
    await clear(dut)
    await FallingEdge(dut.clk)
    dut.din.value = 0x55
    dut.start.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    sb.eq(dut.busy.value, 1, "busy after start")
    dut.rst_n.value = 0
    await Timer(1, unit="ns")
    sb.eq(dut.busy.value, 0, "reset clears busy")
    sb.eq(dut.done.value, 0, "reset clears done")
    # xorout is not reset inside the engine; the register file resets it.
    sb.eq(dut.result.value, 0xFFFF ^ 0x1234, "reset CRC remainder")
    dut.rst_n.value = 1
    dut.start.value = 0
    await RisingEdge(dut.clk)
    sb.note()
