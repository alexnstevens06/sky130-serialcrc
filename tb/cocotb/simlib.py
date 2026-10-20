"""Shared cocotb helpers for the SerialCRC suites."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge

async def clocked(dut, period_ns=10):
    # Started per test: cocotb cancels start_soon tasks when that test ends.
    cocotb.start_soon(Clock(dut.clk, period_ns, unit="ns").start())


async def apply_reset(dut, cycles=4):
    await clocked(dut)
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, cycles)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


class Scoreboard:
    def __init__(self):
        self.checks = 0

    def eq(self, got, exp, what):
        self.checks += 1
        got = int(got)
        exp = int(exp)
        if got != exp:
            raise AssertionError(f"{what}: got 0x{got:X} expected 0x{exp:X}")

    def true(self, cond, what):
        self.checks += 1
        if not cond:
            raise AssertionError(what)

    def note(self):
        cocotb.log.info("%d checks", self.checks)
