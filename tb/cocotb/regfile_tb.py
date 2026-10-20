"""Cycle-accurate register-file tests.

These hit the read side effects that a legal SPI frame stretches across many
clocks: a UART byte arriving after UART_DATA has been captured, STATUS
snapshot clear, and autofeed winning over a same-cycle CRC_DATA write.
"""

import cocotb
from cocotb.triggers import FallingEdge, RisingEdge, Timer

from simlib import Scoreboard, apply_reset


async def _idle(dut):
    dut.addr.value = 0
    dut.rd_req.value = 0
    dut.rd_done.value = 0
    dut.wr_en.value = 0
    dut.wr_data.value = 0
    dut.tx_busy.value = 0
    dut.rx_strobe.value = 0
    dut.rx_byte.value = 0
    dut.rx_frame_err.value = 0
    dut.crc_busy.value = 0
    dut.crc_done_pulse.value = 0
    dut.crc_result.value = 0xFFFF


async def boot(dut):
    await _idle(dut)
    await apply_reset(dut)
    await _idle(dut)


async def write(dut, addr, data):
    await FallingEdge(dut.clk)
    dut.addr.value = addr
    dut.wr_data.value = data
    dut.wr_en.value = 1
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.wr_en.value = 0


async def strobe(dut, byte):
    await FallingEdge(dut.clk)
    dut.rx_byte.value = byte
    dut.rx_strobe.value = 1
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.rx_strobe.value = 0


async def peek(dut, addr):
    await FallingEdge(dut.clk)
    dut.addr.value = addr
    await Timer(1, unit="ns")
    return int(dut.rd_data.value)


async def status_of(dut):
    return await peek(dut, 0x02)


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def test_reset_state(dut):
    sb = Scoreboard()
    await boot(dut)
    sb.eq(await peek(dut, 0x03), 86, "BAUD_LO parameter default")
    sb.eq(await peek(dut, 0x01), 0, "CTRL reset")
    sb.eq(dut.rx_valid.value, 0, "rx_valid reset")
    sb.eq(dut.irq.value, 0, "irq reset")
    sb.note()


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def test_uart_pop_mid_read(dut):
    """A byte that arrives after the read captured UART_DATA stays pending."""
    sb = Scoreboard()
    await boot(dut)
    await strobe(dut, 0x11)

    await FallingEdge(dut.clk)
    dut.addr.value = 0x05
    dut.rd_req.value = 1
    await Timer(1, unit="ns")
    sb.eq(dut.rd_data.value, 0x11, "read captures the pending byte")
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.rd_req.value = 0

    await strobe(dut, 0x22)
    sb.eq(dut.rx_valid.value, 1, "new byte sets rx_valid before pop completes")

    await FallingEdge(dut.clk)
    dut.addr.value = 0x05
    dut.rd_done.value = 1
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.rd_done.value = 0
    await Timer(1, unit="ns")
    sb.eq(dut.rx_valid.value, 1, "pop does not drop the newer byte")
    sb.eq(dut.rd_data.value, 0x22, "UART_DATA holds the newer byte")
    sb.eq(await status_of(dut), 0x02, "mid-read byte is not an overrun")
    sb.note()


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def test_pop_and_strobe_same_cycle(dut):
    sb = Scoreboard()
    await boot(dut)
    await strobe(dut, 0x11)
    await FallingEdge(dut.clk)
    dut.addr.value = 0x05
    dut.rd_req.value = 1
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.rd_req.value = 0
    dut.rd_done.value = 1
    dut.rx_strobe.value = 1
    dut.rx_byte.value = 0x22
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.rd_done.value = 0
    dut.rx_strobe.value = 0
    await Timer(1, unit="ns")
    sb.eq(dut.rx_valid.value, 1, "same-cycle strobe keeps rx_valid")
    sb.eq(dut.rd_data.value, 0x22, "same-cycle strobe keeps the new byte")
    sb.eq(await status_of(dut), 0x02, "same-cycle strobe is not an overrun")
    sb.note()


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def test_overrun_and_status_snapshot(dut):
    sb = Scoreboard()
    await boot(dut)
    await strobe(dut, 0x01)
    await strobe(dut, 0x02)
    sb.eq(await status_of(dut), 0x0A, "overrun plus rx_valid")
    sb.eq(await peek(dut, 0x05), 0x02, "newest byte kept")

    await FallingEdge(dut.clk)
    dut.addr.value = 0x02
    dut.rd_req.value = 1
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.rd_req.value = 0
    dut.rx_frame_err.value = 1
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.rx_frame_err.value = 0
    dut.rd_done.value = 1
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.rd_done.value = 0
    # Overrun was in the snapshot and clears. frame_err landed later and stays.
    sb.eq(await status_of(dut), 0x22, "late frame_err survives STATUS clear")
    sb.note()


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def test_autofeed_priority_and_busy_gate(dut):
    sb = Scoreboard()
    await boot(dut)
    await write(dut, 0x01, 0x04)
    await FallingEdge(dut.clk)
    dut.addr.value = 0x0C
    dut.wr_en.value = 1
    dut.wr_data.value = 0x22
    dut.rx_strobe.value = 1
    dut.rx_byte.value = 0x11
    dut.crc_busy.value = 0
    await Timer(1, unit="ns")
    sb.eq(dut.crc_start.value, 1, "autofeed starts the engine")
    sb.eq(dut.crc_din.value, 0x11, "autofeed byte wins over CRC_DATA")
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.wr_en.value = 0
    dut.rx_strobe.value = 0

    dut.crc_busy.value = 1
    dut.wr_en.value = 1
    dut.rx_strobe.value = 1
    await Timer(1, unit="ns")
    sb.eq(dut.crc_start.value, 0, "CRC_DATA and autofeed ignored while busy")
    dut.wr_en.value = 0
    dut.rx_strobe.value = 0
    dut.crc_busy.value = 0

    await FallingEdge(dut.clk)
    dut.addr.value = 0x0D
    dut.wr_data.value = 0x01
    dut.wr_en.value = 1
    await Timer(1, unit="ns")
    sb.eq(dut.crc_clear.value, 1, "CRC_CMD bit0 pulses clear")
    dut.wr_data.value = 0x00
    await Timer(1, unit="ns")
    sb.eq(dut.crc_clear.value, 0, "CRC_CMD bit0=0 does not clear")
    dut.wr_en.value = 0
    sb.note()


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def test_tx_ignored_while_busy(dut):
    sb = Scoreboard()
    await boot(dut)
    await FallingEdge(dut.clk)
    dut.tx_busy.value = 1
    dut.addr.value = 0x05
    dut.wr_data.value = 0x22
    dut.wr_en.value = 1
    await Timer(1, unit="ns")
    sb.eq(dut.tx_start.value, 0, "TX write ignored while busy")
    dut.tx_busy.value = 0
    await Timer(1, unit="ns")
    sb.eq(dut.tx_start.value, 1, "TX write accepted while idle")
    sb.eq(dut.tx_data.value, 0x22, "TX data")
    dut.wr_en.value = 0
    sb.note()
