#!/usr/bin/env python3
"""Condense a Yosys `stat -liberty` report into a short summary."""
import re
import sys

TT_TILE_UM2 = 161.0 * 111.52   # TinyTapeout 1x1 tile, die area (approx.)


def main():
    text = open(sys.argv[1]).read()
    # Use the top-level (last) statistics block.
    area = re.findall(r"Chip area for (?:top )?module '[^']*':\s*([\d.]+)", text)
    if not area:
        area = re.findall(r"([\d.]+)\s+chip area", text, re.I)
    area = float(area[-1]) if area else float("nan")
    cells = {}
    for m in re.finditer(r"^\s*(\d+)\s+(?:[\d.E+-]+\s+)?(sky130_fd_sc_hd__\w+)\s*$", text, re.M):
        cells[m.group(2)] = cells.get(m.group(2), 0) + int(m.group(1))
    if not cells:
        for m in re.finditer(r"^\s*(sky130_fd_sc_hd__\w+)\s+(\d+)\s*$", text, re.M):
            cells[m.group(1)] = cells.get(m.group(1), 0) + int(m.group(2))
    total = sum(cells.values())
    flops = sum(n for c, n in cells.items() if re.search(r"__(df|dl|sdf|edf)", c))
    print(f"standard cells : {total}")
    print(f"flip-flops     : {flops}")
    print(f"chip area      : {area:.1f} um^2 (sky130_fd_sc_hd, tt_025C_1v80, pre-placement)")
    print(f"TT 1x1 tile    : {100.0 * area / TT_TILE_UM2:.1f}% of {TT_TILE_UM2:.0f} um^2 "
          f"(cell area only; ~60% is a typical max placement density)")
    print("top cells      : " + ", ".join(f"{c.replace('sky130_fd_sc_hd__', '')} x{n}"
                                          for c, n in sorted(cells.items(), key=lambda x: -x[1])[:8]))


if __name__ == "__main__":
    main()
