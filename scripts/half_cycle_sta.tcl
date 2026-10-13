# usage: env RUN, PDK, CORNER(lib corner e.g. ss_100C_1v60), RC (nom|min|max)
set run $::env(RUN)
set lib $::env(PDK)/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__$::env(CORNER).lib
read_liberty $lib
read_verilog [glob $run/final/pnl/*.pnl.v]
link_design tt_um_alexstevens_serialcrc
read_spef [glob $run/final/spef/$::env(RC)/*.spef]
read_sdc $run/../../serialcrc.sdc
set_propagated_clock [all_clocks]
set rr [all_registers -rise_clock clk]
set ff [all_registers -fall_clock clk]
puts "NEGFLOPS [llength [get_cells $ff]] POSFLOPS [llength [get_cells $rr]]"
foreach {name from to} [list rise_to_fall $rr $ff fall_to_rise $ff $rr] {
  foreach pd {max min} {
    puts "== $name $pd"
    report_checks -path_delay $pd -from $from -to $to -format end
  }
}
puts "== critical_full"
report_checks -path_delay max -format full -fields {}
