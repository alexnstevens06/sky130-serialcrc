#!/usr/bin/env python3
"""Summarise a Verilator lcov .info file for RTL sources only.

Usage: cov_summary.py merged.info rtl/
Prints per-file line coverage and coverage-point (line + toggle + branch
bins) coverage, plus totals.
"""
import sys
from collections import OrderedDict


def main():
    info, prefix = sys.argv[1], sys.argv[2]
    files = OrderedDict()
    cur = None
    with open(info) as fh:
        for raw in fh:
            line = raw.strip()
            if line.startswith("SF:"):
                path = line[3:]
                cur = files.setdefault(path, {"lines": {}, "pts": [0, 0]}) if prefix in path else None
            elif cur is None:
                continue
            elif line.startswith("DA:"):
                ln, hits = line[3:].split(",")[:2]
                cur["lines"][int(ln)] = cur["lines"].get(int(ln), 0) + int(hits)
            elif line.startswith("BRDA:"):
                hits = line.split(",")[3]
                cur["pts"][1] += 1
                if hits not in ("-", "0"):
                    cur["pts"][0] += 1
    tl = th = tp = tph = 0
    print(f"{'file':40s} {'lines':>16s} {'points':>16s}")
    for path, d in files.items():
        n = len(d["lines"])
        h = sum(1 for v in d["lines"].values() if v > 0)
        ph, pn = d["pts"]
        tl += n; th += h; tp += pn; tph += ph
        name = path[path.find(prefix):]
        lp = 100.0 * h / n if n else 100.0
        pp = 100.0 * ph / pn if pn else 100.0
        print(f"{name:40s} {h:4d}/{n:<4d} {lp:6.1f}% {ph:4d}/{pn:<4d} {pp:6.1f}%")
    lp = 100.0 * th / tl if tl else 0.0
    pp = 100.0 * tph / tp if tp else 0.0
    print(f"{'TOTAL (rtl/)':40s} {th:4d}/{tl:<4d} {lp:6.1f}% {tph:4d}/{tp:<4d} {pp:6.1f}%")
    print(f"COVERAGE line={lp:.1f}% points={pp:.1f}%")


if __name__ == "__main__":
    main()
