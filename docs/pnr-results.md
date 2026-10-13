# Place-and-route results (LibreLane), 66 MHz

Final run: `librelane/runs/attempt3` (run outputs are gitignored). Made with `scripts/harden.sh`
(`nice -n 19`, idle I/O priority, `--cpus=4`), `librelane/config.json` and `librelane/serialcrc.sdc`.

| Item | Value |
|---|---|
| LibreLane | v3.0.14 (Docker `ghcr.io/librelane/librelane:3.0.14`), Classic flow |
| PDK | sky130A (ciel 8afc8346), `sky130_fd_sc_hd` |
| Clock | 15.15 ns (66 MHz), 50% duty cycle, single-edge (posedge) design |
| Die area | 334.88 x 111.52 um (TinyTapeout 1x2), core area 29,068 um^2 |
| Core utilization | 61.2% (2,419 std cells, excluding fill/tap) |
| Worst setup slack | +3.79 ns (max_ss_100C_1v60), 0 violations |
| Worst hold slack | +0.084 ns (max_ss_100C_1v60), 0 violations |
| Routing / Magic / KLayout DRC | 0 / 0 / 0 |
| LVS | Clean |
| Antenna | 0 nets / 0 pins |
| XOR (Magic vs KLayout GDS) | 0 |
| Max slew / max cap violations | 0 / 0 |
| Max fanout violations | 89 (limit 10, see below) |

## Per-corner slack and clock skew (sign-off STA, ns)

| Corner | Setup WS | Hold WS | Worst clock skew |
|---|---|---|---|
| min_ff_n40C_1v95 | 9.382 | 0.183 | 0.328 |
| nom_ff_n40C_1v95 | 9.355 | 0.184 | 0.331 |
| max_ff_n40C_1v95 | 9.326 | 0.184 | 0.335 |
| min_tt_025C_1v80 | 8.453 | 0.202 | 0.339 |
| nom_tt_025C_1v80 | 8.412 | 0.192 | 0.342 |
| max_tt_025C_1v80 | 8.372 | 0.179 | 0.346 |
| min_ss_100C_1v60 | 4.069 | 0.116 | 0.362 |
| nom_ss_100C_1v60 | 3.907 | 0.100 | 0.365 |
| max_ss_100C_1v60 | 3.790 | 0.084 | 0.368 |

## Critical path (max_ss_100C_1v60)
Start point `_1539_` (`u_rx.cnt[0]`, the UART RX baud counter), end point `_1544_` (a `u_rx.cnt` bit),
posedge to posedge. The launch clock arrives at 0.89 ns and data arrives at 11.63 ns, so the data path is 10.74 ns.
Required time is 15.42 ns (period plus capture clock latency, minus 0.30 ns uncertainty and 0.28 ns setup).
The path is the counter terminal-count compare (three `or4` levels, about 5.3 ns), then two high-fanout
buffers (21 loads each) into the counter reload logic.

## Constraints (`librelane/serialcrc.sdc`, used for both PnR and sign-off)
- `create_clock` at 15.15 ns, waveform {0 7.575}. Any rise-to-fall or fall-to-rise path is timed against 7.575 ns.
- Clock uncertainty: 0.30 ns setup, 0.10 ns hold. Clock transition: 0.15 ns.
- Input and output delay: max 3.79 ns (25% of the period), min 0.5 ns.
- Inputs driven by `sky130_fd_sc_hd__buf_2`, 35 fF output load.
- Max fanout 10, max transition 1.5 ns.

Repair settings: post-GPL and post-GRT design repair, post-GRT resizer timing, slew/cap repair margins 40% / 30%,
setup/hold slack margins 0.2/0.15 ns (placement) and 0.1/0.1 ns (after global routing), 200 um max wire length.

## Duty-cycle and skew margins
All flops are posedge-triggered; `negedge` appears only on the asynchronous `rst_n`. So there are no
half-cycle paths, and duty-cycle distortion does not change any setup or hold check. Only flop minimum pulse
width matters, and it is far below the 7.575 ns half period at every corner. The worst clock-tree skew is
0.33 to 0.37 ns (table above), covered by the 0.30 ns setup uncertainty plus 3.79 ns of slack.
For reference, a half-cycle path would have about 6.9 ns of budget at ss, and the worst full-cycle path needs 10.74 ns.

## Floating nets (RSZ-0020)
The two nets the resizer reports as "floating" are `VPWR` and `VGND`. Power nets have no signal driver in the
resizer netlist view, so this warning is expected and is not a real connectivity fault. The PDN checker
(0 power-grid violations) and LVS (clean) confirm both rails are fully connected. Nothing needed fixing.

## Remaining fanout violations
89 nets exceed the fanout limit of 10, for example the 21-load `fanout*` buffers and the CTS leaf clock
buffers (up to 25 sinks). They leave no slew or cap violations and timing is met at every corner, so they
were left in place. Lowering them further would need stricter fanout repair or register duplication in the RTL.

## Run history
| Run | Change | Result |
|---|---|---|
| attempt1 | 10 MHz, generic SDC | Passed. 687 slew, 98 fanout, 7 cap violations |
| attempt2 | 66 MHz SDC, stronger repair, max transition 0.75 ns | Setup +4.16 ns. 439 slew, 88 fanout, 1 cap violations |
| attempt3 | Max transition aligned to library 1.5 ns, fanout 10, larger repair margins | Setup +3.79 ns, hold +0.084 ns. 0 slew, 0 cap, 89 fanout violations |

RTL change: the top-level `CLK_HZ` default is now 66_000_000, so the reset baud divisor gives 115200 baud
at 66 MHz (div 572). `info.yaml` `clock_hz` is now 66000000. The testbenches still set `CLK_HZ=10_000_000`
explicitly. `make test`: tb_crc16 4439 checks, tb_uart 689 checks, tb_top 178 checks, all passing.

## What dual-edge operation would need (not implemented)
The design is single-edge, so nothing was restructured. To use both edges:
- **Blocks that would change:** the UART RX/TX bit counters and oversampling (`uart_rx`, `uart_tx`),
  the SPI edge-detect and shift logic (`spi_slave`, `sync2`), and possibly the CRC engine (2 bits per clock by
  splitting the LFSR update across both edges). `regfile` can stay posedge.
- **Half-cycle budget:** 7.575 ns minus 0.30 ns uncertainty minus about 0.3 ns setup leaves about 6.9 ns at ss.
  The current critical path is 10.74 ns at ss, so a half-cycle version of the UART counter compare would miss by
  about 3.8 ns. It would need to be pipelined (a registered terminal-count flag, or a down-counter with a
  precomputed zero flag) and the high-fanout nets duplicated. The CRC update path would need a separate check.
- **Hold and min pulse width:** paths between opposite edges get half a cycle of hold separation, which helps, but
  same-edge paths inside each domain keep full hold risk, and the ff-corner hold margin is already only 0.08 to 0.2 ns.
  Duty-cycle distortion or skew directly reduces the half-cycle budget (each 1% of distortion costs about 0.15 ns).
  Min pulse width must hold at the distorted phase at ss.
- **CTS and duty cycle:** CTS would have to balance both edges. Clock buffers have asymmetric rise/fall delays,
  which shows up as duty-cycle distortion at the leaves, so symmetric clock buffers and an explicit duty-cycle check
  would be needed. The TinyTapeout clock input duty cycle is not guaranteed, so this needs margin.
- **Tests:** the testbenches would need checks on both clock phases and a duty-cycle-skewed clock stimulus,
  plus gate-level simulation with SDF, because RTL simulation hides half-cycle races.
