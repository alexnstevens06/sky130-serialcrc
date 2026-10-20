# Generic-cell synthesis for gate-level simulation. No liberty file and no
# PDK: `synth` maps to Yosys internal gates ($_AND_, $_DFF_*, ...). Icarus
# simulates those with the matching simcells.v models. CLK_HZ/BAUD match
# tb_top so the elaborated reset baud is 86.
yosys -import
set top $::env(TOP)
set out $::env(OUT)
foreach f $::env(RTL) { read_verilog -defer $f }
chparam -set CLK_HZ $::env(CLK_HZ) -set BAUD $::env(BAUD) $top
hierarchy -check -top $top
synth -top $top -flatten
opt_clean -purge
setundef -zero
opt_clean -purge
stat
write_verilog -noattr -noexpr -nohex $out/netlist.v
