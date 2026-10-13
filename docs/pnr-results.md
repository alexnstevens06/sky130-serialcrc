# Place-and-route results (LibreLane)

Run: `librelane/runs/attempt1` (run outputs are gitignored), made with `scripts/harden.sh` and `librelane/config.json`.

| Item | Value |
|---|---|
| LibreLane | v3.0.14 (Docker image `ghcr.io/librelane/librelane:3.0.14`), Classic flow |
| PDK | sky130A (ciel 8afc8346), `sky130_fd_sc_hd` |
| Target | TinyTapeout 1x2 tile, 10 MHz (CLOCK_PERIOD 100 ns) |
| Die area | 334.88 x 111.52 um (37,346 um^2) |
| Core area | 29,067.9 um^2 |
| Core utilization | 67.8% (PL_TARGET_DENSITY_PCT 55) |
| Std cells (excluding fill/tap) | 2,632 |
| Worst setup slack | +72.76 ns (max_ss_100C_1v60), setup TNS 0 |
| Worst hold slack | +0.094 ns (min_ff_n40C_1v95), hold TNS 0 |
| Routing DRC | 0 (after 5 detailed-route iterations) |
| Magic DRC / KLayout DRC | 0 / 0 |
| LVS | Clean (0 errors, 0 unmatched pins/nets/devices) |
| Antenna violations | 0 nets / 0 pins (heuristic diode insertion enabled) |
| XOR (Magic vs KLayout GDS) | 0 differences |
| Power-grid violations | 0 |

## Open items (not sign-off failures)
- Max-slew violations: 687 in the worst corner (max_ss_100C_1v60), 282 at nom_tt.
- Max-fanout violations: 98. Max-cap violations: 7 (ss corners only).
- Both PnR and sign-off STA used the generic fallback SDC (no `PNR_SDC_FILE`/`SIGNOFF_SDC_FILE`).
- RSZ-0020 reported 2 floating nets.

The manufacturability report (Antenna, LVS, DRC) shows Passed for all three.
