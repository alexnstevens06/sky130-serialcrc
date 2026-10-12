#!/usr/bin/env python3
"""Summarise a Verilator coverage.dat file for RTL sources only.

Usage: cov_summary.py merged.dat rtl/

Reads the raw Verilator coverage database (stable across Verilator 5.x) and
prints, per source file, how many line/branch and toggle coverage points were
hit at least once.
"""
import re
import sys
from collections import OrderedDict

REC = re.compile(r"^C '(.*)' (\d+)\s*$")


def parse_keys(s):
    out = {}
    for item in s.split("\x01"):
        if "\x02" in item:
            k, v = item.split("\x02", 1)
            out[k] = v
    return out


def kind(page):
    page = page.split("/")[0]
    if "toggle" in page:
        return "toggle"
    if "user" in page:
        return "user"
    return "line"          # v_line, v_branch, v_line/expr ...


def pct(h, n):
    return 100.0 * h / n if n else 100.0


def main():
    dat, prefix = sys.argv[1], sys.argv[2]
    files = OrderedDict()
    with open(dat, encoding="latin-1") as fh:
        for raw in fh:
            m = REC.match(raw)
            if not m:
                continue
            keys, count = parse_keys(m.group(1)), int(m.group(2))
            f = keys.get("f", "")
            if prefix not in f:
                continue
            f = f[f.find(prefix):]
            d = files.setdefault(f, {"line": [0, 0], "toggle": [0, 0]})
            k = kind(keys.get("page", ""))
            if k not in d:
                continue
            d[k][1] += 1
            if count > 0:
                d[k][0] += 1
    tot = {"line": [0, 0], "toggle": [0, 0]}
    print(f"{'file':36s} {'line/branch points':>22s} {'toggle points':>22s}")
    for f in sorted(files):
        d = files[f]
        cols = []
        for k in ("line", "toggle"):
            h, n = d[k]
            tot[k][0] += h
            tot[k][1] += n
            cols.append(f"{h:5d}/{n:<5d} {pct(h, n):6.1f}%")
        print(f"{f:36s} {cols[0]:>22s} {cols[1]:>22s}")
    cols = [f"{tot[k][0]:5d}/{tot[k][1]:<5d} {pct(*tot[k]):6.1f}%" for k in ("line", "toggle")]
    print(f"{'TOTAL (' + prefix + ')':36s} {cols[0]:>22s} {cols[1]:>22s}")
    allh = tot["line"][0] + tot["toggle"][0]
    alln = tot["line"][1] + tot["toggle"][1]
    print(f"COVERAGE line={pct(*tot['line']):.1f}% toggle={pct(*tot['toggle']):.1f}% "
          f"all={pct(allh, alln):.1f}%")


if __name__ == "__main__":
    main()
