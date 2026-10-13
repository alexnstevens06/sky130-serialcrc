# Place-and-route results (LibreLane), 66 MHz dual-edge

Branch `rtl/dual-edge-66mhz` (off `pnr/librelane-signoff` @ 6832ff0). Final run: `librelane/runs/de2`
(run outputs are gitignored). Made with `scripts/harden.sh` (`nice -n 19`, idle I/O priority, `--cpus=4`),
`librelane/config.json` and `librelane/serialcrc.sdc`.

| Item | Value |
|---|---|
| LibreLane | v3.0.14 (Docker `ghcr.io/librelane/librelane:3.0.14`), Classic flow |
| PDK | sky130A (ciel 8afc8346), `sky130_fd_sc_hd` |
| Clock | 15.15 ns (66 MHz), both edges used: 16 falling-edge flops (`u_crc.crc_h`), 250 rising-edge flops |
| Die area | 334.88 x 111.52 um (TinyTapeout 1x2), core area 29,068 um^2 |
| Core utilization | 65.0% (2,546 std cells, excluding fill/tap) |
| Worst setup slack | +2.34 ns (max_ss_100C_1v60, rise->fall half-cycle path), 0 violations |
| Worst hold slack | +0.038 ns (max_ss_100C_1v60, rise->rise), 0 violations |
| Routing / Magic / KLayout DRC | 0 / 0 / 0 |
| LVS | Clean |
| Antenna | 0 nets / 0 pins |
| XOR (Magic vs KLayout GDS) / power grid | 0 / 0 |
| Max slew / max cap violations | 0 / 0 |
| Max fanout violations | 106 (limit 10; no slew or cap impact) |

## Constraints (`librelane/serialcrc.sdc`, used for both PnR and sign-off)
- `create_clock` at 15.15 ns, waveform {0 7.575}, so rise->fall and fall->rise paths are timed against 7.575 ns.
- Clock uncertainty: 0.30 ns setup, 0.10 ns hold (all paths).
- Duty-cycle distortion margin: half-cycle paths get an extra 5% of the period (0.758 ns) as inter-clock
  uncertainty (`-rise_from/-fall_to` and `-fall_from/-rise_to`): 1.058 ns setup and 0.858 ns hold. The effective
  half-cycle setup budget is about 6.5 ns before library setup time.
- Input and output delay: max 3.79 ns, min 0.5 ns. Inputs driven by `buf_2`, 35 fF load. Max fanout 10, max transition 1.5 ns.

## Per-corner slack (ns)
"All paths" is the sign-off STA worst slack. The half-cycle columns come from `scripts/half_cycle_sta.tcl`
(OpenSTA on the final netlist and SPEF, from rising-edge registers to falling-edge registers and back).

| Corner | Setup (all) | Hold (all) | Setup R->F | Setup F->R | Hold R->F | Hold F->R | Clock skew |
|---|---|---|---|---|---|---|---|
| min_ff_n40C_1v95 | 5.255 | 0.174 | 5.27 | 5.25 | 7.05 | 7.09 | 0.343 |
| nom_ff_n40C_1v95 | 5.229 | 0.176 | 5.24 | 5.23 | 7.05 | 7.09 | 0.343 |
| max_ff_n40C_1v95 | 5.207 | 0.179 | 5.21 | 5.21 | 7.06 | 7.09 | 0.344 |
| min_tt_025C_1v80 | 4.435 | 0.176 | 4.52 | 4.43 | 7.23 | 7.32 | 0.366 |
| nom_tt_025C_1v80 | 4.398 | 0.164 | 4.48 | 4.40 | 7.24 | 7.32 | 0.365 |
| max_tt_025C_1v80 | 4.369 | 0.152 | 4.43 | 4.37 | 7.24 | 7.32 | 0.366 |
| min_ss_100C_1v60 | 2.491 | 0.073 | 2.49 | 2.52 | 7.71 | 7.92 | 0.423 |
| nom_ss_100C_1v60 | 2.411 | 0.055 | 2.41 | 2.45 | 7.72 | 7.91 | 0.421 |
| max_ss_100C_1v60 | 2.337 | 0.038 | 2.34 | 2.40 | 7.73 | 7.91 | 0.421 |

The half-cycle paths set the worst setup slack at every corner. Their hold slack is large because the capture
edge is half a period away from the launch edge.

**Duty-cycle tolerance.** The worst half-cycle slack at ss is 2.34 ns, on top of the 0.758 ns (5%) already
reserved. So the design tolerates about (2.34 + 0.758) / 15.15, roughly 20% duty-cycle distortion
(a 30/70 clock) at the slow corner, before setup on a half-cycle path fails.

## Critical path (max_ss_100C_1v60, rise -> fall)
`u_crc.crc[15]` (`_1512_`, rising edge) -> `xor2` (feedback bit crc[15] ^ sh[7]) -> `fanout52` buffer (21 loads,
the poly-select net) -> `nand2` -> `xnor2` -> `u_crc.crc_h[1]` (`_1481_`, falling edge).
Data arrives at 4.88 ns (launch clock latency 0.90 ns, so the data path is 3.98 ns). Required time is 7.22 ns:
7.575 ns plus 0.99 ns capture latency, minus 1.06 ns inter-clock uncertainty and 0.29 ns setup. Slack is +2.34 ns.
The worst fall->rise path (`crc_h` -> `u_crc.crc[13]`) is +2.40 ns.

## RTL changes
- `crc16_engine.v`: two LFSR steps per clock. On every falling edge, `crc_h` captures one step of `crc` (bit `sh[7]`).
  On the rising edge, `crc` takes the second step from `crc_h` (bit `sh[6]`). A byte now takes 4 clocks instead of 8.
  `crc_h` has no reset: it is recomputed on every falling edge and only used while busy. This keeps `rst_n` off the
  falling-edge flops. With a reset, run de1 failed by 0.40 ns on the rst_n -> negedge-flop recovery check.
- `uart_rx.v`, `uart_tx.v`: the bit-timer done test is now a registered flag `cz` (meaning cnt == 0), computed a
  cycle ahead from `cnt == 1` or `div == 0` (`div[15:1] == 0` for the half-bit start). This replaces the 16-bit
  compare that was the old critical path. The resizer splits the remaining high-fanout nets.
- SPI (`spi_slave.v`, `sync2.v`) and `regfile.v` are unchanged and posedge-only. A falling-edge first synchronizer
  stage would halve metastability settling time for no throughput gain, so it was not used.
- `SPEC.md`: CRC_DATA now takes 4 clocks (2 bits/clock on both edges).
- `tb/tb_top.v`: the `crc_busy` pin-cycle expectation changed from 5*9*8 to 5*9*4. This is the only existing
  assertion changed, and it changed because CRC throughput doubled by design.

## Verification
- `make test` (RTL, Icarus): tb_crc16 4439 checks, tb_uart 689 checks, tb_top 178 checks, tb_dualedge 139 checks. All pass.
- New `tb/tb_dualedge.v`:
  - CRC-16/CCITT-FALSE, ARC, MODBUS and XMODEM over "123456789", checking 4 clocks per byte.
  - UART tx -> rx loopback at divisors 3 to 8.
  - All of this at 30%, 50% and 70% clock duty cycle.
  - A phase check that `crc_h` changes only on falling edges and `crc` only on rising edges.
- Gate-level simulation (`scripts/gls.sh librelane/runs/de2`): `tb_top` on the routed netlist (`final/nl`) with the
  sky130 functional cell models, at 50%, 30% and 70% duty. 178 checks pass at each. The reset-baud checks expect
  divisor 572 because the netlist is built with CLK_HZ = 66 MHz. This is functional, unit-delay simulation without
  SDF; timing is signed off by STA above.

## Run history
| Run | Change | Result |
|---|---|---|
| attempt1 | 10 MHz, generic SDC | Passed. 687 slew violations |
| attempt2 | 66 MHz SDC, stronger repair | Setup +4.16 ns. 439 slew violations |
| attempt3 | Single-edge 66 MHz closure | Setup +3.79 ns, hold +0.084 ns |
| de1 | Dual-edge CRC, UART done flags, 5% DCD margin | Failed: -0.40 ns (rst_n recovery to falling-edge flops), 16 violations |
| de2 | Reset removed from `crc_h` | Passed: setup +2.34 ns, hold +0.038 ns, DRC/LVS/antenna clean |

## Floating nets (RSZ-0020)
The two nets the resizer reports as floating are `VPWR` and `VGND`. Power nets have no signal driver in the
resizer netlist view, so this is expected. The power-grid check and LVS confirm both rails are connected.

## Remaining risks
- Hold margin at ss on full-cycle paths is +0.038 ns (above the 0.10 ns hold uncertainty already applied).
- 106 fanout-limit violations remain (21-load buffers, CTS leaves). There are no slew or cap violations.
- The TinyTapeout clock input duty cycle is not guaranteed by the shared clock mux. The design is checked with
  5% distortion margin, and the arithmetic above gives roughly 20% of headroom at ss.
