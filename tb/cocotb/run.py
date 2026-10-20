#!/usr/bin/env python3
"""Build and run the cocotb suites under Icarus Verilog.

Icarus is the simulator because the CRC engine updates a register on the
falling edge. Verilator needs its timing mode for that path; the existing
coverage job already runs the Verilog testbenches there.
"""

import os
import sys
from pathlib import Path


def main():
    try:
        from cocotb_tools.check_results import get_results
        from cocotb_tools.runner import get_runner
    except ImportError:
        print(
            "cocotb is not installed. pip install -r tb/cocotb/requirements.txt",
            file=sys.stderr,
        )
        return 1

    tb_dir = Path(__file__).resolve().parent
    sys.path.insert(0, str(tb_dir))
    from crc_model import assert_catalogue

    assert_catalogue()

    root = tb_dir.parents[1]
    rtl = root / "rtl"
    chip_sources = [
        rtl / "sync2.v",
        rtl / "spi_slave.v",
        rtl / "uart_tx.v",
        rtl / "uart_rx.v",
        rtl / "crc16_engine.v",
        rtl / "regfile.v",
        rtl / "tt_um_alexstevens_serialcrc.v",
    ]
    suites = (
        ("regfile", "regfile", [rtl / "regfile.v"], "regfile_tb"),
        ("crc", "crc16_engine", [rtl / "crc16_engine.v"], "crc_tb"),
        (
            "uart",
            "uart_loopback",
            [rtl / "uart_tx.v", rtl / "uart_rx.v", tb_dir / "hdl" / "uart_loopback.v"],
            "uart_tb",
        ),
        ("chip", "tt_um_alexstevens_serialcrc", chip_sources, "chip_tb"),
    )
    waves = os.environ.get("WAVES", "0") not in ("", "0")
    for name, toplevel, sources, module in suites:
        runner = get_runner("icarus")
        build_dir = root / "build" / "cocotb" / name
        runner.build(
            sources=sources,
            hdl_toplevel=toplevel,
            build_dir=build_dir,
            timescale=("1ns", "1ps"),
            build_args=["-g2005", "-Wall", "-Wno-timescale"],
            always=True,
            waves=waves,
        )
        xml = runner.test(
            hdl_toplevel=toplevel,
            test_module=module,
            build_dir=build_dir,
            timescale=("1ns", "1ps"),
            waves=waves,
        )
        tests, failed = get_results(xml)
        print(f"[cocotb] {name}: {tests - failed} passed, {failed} failed ({tests} tests)")
        if failed:
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
