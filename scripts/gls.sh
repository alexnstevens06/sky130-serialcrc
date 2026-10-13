#!/usr/bin/env bash
# Gate-level simulation of the routed netlist with tb_top, at 50%, 30% and 70%
# clock duty cycle. Functional cell models (unit delay), no SDF: timing is
# signed off by STA. The netlist has CLK_HZ=66 MHz baked in, so the reset-baud
# checks expect divisor 572 (0x023C) instead of 86.
#   scripts/gls.sh <librelane run dir>
set -euo pipefail
RUN=${1:?run dir}
PDK_ROOT=${PDK_ROOT:-$HOME/.ciel}
V=$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/verilog
NL=$(ls "$RUN"/final/nl/*.nl.v)
OUT=build/gls; mkdir -p "$OUT"
fail=0
for d in 50 30 70; do
  hi=$d; lo=$((100 - d))
  sed -e "s/tt_um_alexstevens_serialcrc #(.CLK_HZ(10_000_000), .BAUD(115_200)) dut/tt_um_alexstevens_serialcrc dut/" \
      -e "s/always #50 clk = ~clk;.*/always begin #$lo clk = 1'b1; #$hi clk = 1'b0; end  \/\/ $d% duty/" \
      -e "s/expect_reg(A_BAUD_LO, 8'd86, \"BAUD_LO reset (115200)\")/expect_reg(A_BAUD_LO, 8'h3C, \"BAUD_LO reset (115200 @ 66 MHz)\")/" \
      -e "s/expect_reg(A_BAUD_HI, 8'h00, \"BAUD_HI reset\")/expect_reg(A_BAUD_HI, 8'h02, \"BAUD_HI reset\")/" \
      -e "s/expect_reg(A_BAUD_LO, 8'd86, \"BAUD after reset\")/expect_reg(A_BAUD_LO, 8'h3C, \"BAUD after reset\")/" \
      tb/tb_top.v > "$OUT/tb_top_gl_$d.v"
  iverilog -g2005 -Wno-timescale -DFUNCTIONAL -DUNIT_DELAY=#1 -o "$OUT/gl_$d.vvp" -s tb_top \
      "$OUT/tb_top_gl_$d.v" "$NL" "$V/primitives.v" "$V/sky130_fd_sc_hd.v"
  nice -n 19 vvp -n "$OUT/gl_$d.vvp" > "$OUT/gl_$d.log" 2>&1 || true
  if grep -q '^PASS' "$OUT/gl_$d.log"; then echo "[PASS] GLS duty $d%: $(grep '^PASS' "$OUT/gl_$d.log")"
  else echo "[FAIL] GLS duty $d%"; grep -m10 -i "error\|fail" "$OUT/gl_$d.log"; fail=1; fi
done
exit $fail
