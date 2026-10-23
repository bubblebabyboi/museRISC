# Per-corner signoff STA of a routed ORFS block: 6_final.odb + the
# OpenRCX 6_final.spef (typical RC, the only extraction rules of the
# sky130hd platform) against one sky130_fd_sc_hd corner library.
# The OpenRAM macros only have a TT_1p8V_25C liberty, so they keep TT
# timing in every corner.
# Run with openroad -exit -no_init corner_sta.tcl in the ORFS image,
# one process per corner, e.g. (sigil-sky130 ~/sb/sta.sh):
#   docker run ... -e RES=<results dir> -e CORNER=ss -e OUT=<dir> \
#     -e PDKLIB=<dir> -e MODEL=1 <image> openroad -exit -no_init corner_sta.tcl
# env: RES (results dir), STAGE (see below), CORNER (ss|tt|ff|orfs), OUT (report dir),
#      PDKLIB (dir with the sky130_fd_sc_hd corner .libs), BLOCK_LIBS (see below),
#      MODEL (1: also write a timing model <design>_<corner>.lib to OUT)
set res $::env(RES); set corner $::env(CORNER); set out $::env(OUT)
set plat /OpenROAD-flow-scripts/flow/platforms
array set sc {
  ss   sky130_fd_sc_hd__ss_100C_1v60.lib
  tt   sky130_fd_sc_hd__tt_025C_1v80.lib
  ff   sky130_fd_sc_hd__ff_n40C_1v95.lib
}
if { $corner == "orfs" } {
  read_liberty $plat/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
} else {
  read_liberty $::env(PDKLIB)/$sc($corner)
}
foreach m [glob -nocomplain -directory $plat/sky130ram sky130_sram_*] {
  set n [file tail $m]
  if { [file exists $m/${n}_TT_1p8V_25C.lib] } {
    read_liberty $m/${n}_TT_1p8V_25C.lib
  }
}
# BLOCK_LIBS (optional, top level): the hard blocks' timing models,
# space-separated; %c in a path is replaced by the corner (tt for
# "orfs"), e.g. .../sigil_cpu_%c.lib (corner models written by this
# script with MODEL=1 on the routed block).
if { [info exists ::env(BLOCK_LIBS)] && $::env(BLOCK_LIBS) != "" } {
  set bc [expr { $corner == "orfs" ? "tt" : $corner }]
  foreach l $::env(BLOCK_LIBS) {
    read_liberty [string map [list %c $bc] $l]
  }
}
# STAGE (optional, default 6_final): an earlier stage (e.g. 4_cts) is
# timed with placement-estimated parasitics instead of the SPEF.
set stage [expr { [info exists ::env(STAGE)] && $::env(STAGE) != "" ? $::env(STAGE) : "6_final" }]
read_db $res/$stage.odb
read_sdc $res/$stage.sdc
if { $stage == "6_final" } {
  read_spef $res/6_final.spef
} else {
  source $plat/sky130hd/setRC.tcl
  estimate_parasitics -placement
}
set_propagated_clock [all_clocks]

# (report_check_types first: the violation counters need its preamble)
report_check_types -max_slew -max_capacitance -max_fanout -violators -digits 3
set f [open $out/sta_$corner.summary w]
proc both { f s } { puts $s; puts $f $s }
both $f "corner $corner stage $stage design [[ord::get_db_block] getName]"
foreach mm {max min} {
  set ws [sta::format_time [sta::worst_slack_cmd $mm] 3]
  set tns [sta::format_time [sta::total_negative_slack_cmd $mm] 3]
  set nv [sta::endpoint_violation_count $mm]
  both $f "[expr { $mm == "max" ? "setup" : "hold " }] ws $ws ns tns $tns ns violating_endpoints $nv"
}
both $f "max_slew_violations [sta::max_slew_violation_count] max_cap_violations [sta::max_capacitance_violation_count] max_fanout_violations [sta::max_fanout_violation_count]"
# Setup split by endpoint: block output ports (checked against the
# boundary budget of constraint.sdc) vs internal endpoints (register
# and macro pins); worst slack of each, also when it is positive (from
# the 5000 worst endpoints).
foreach kind {outputs internal} {
  set sws($kind) "-"
  set snv($kind) 0
  set stns($kind) 0.0
}
foreach pe [find_timing_paths -path_delay max -group_path_count 5000 \
              -endpoint_path_count 1 -sort_by_slack] {
  set kind [expr { [string match "*/*" [get_full_name [get_property $pe endpoint]]] ? "internal" : "outputs" }]
  set s [get_property $pe slack]
  if { $sws($kind) eq "-" || $s < $sws($kind) } {
    set sws($kind) $s
  }
}
foreach pe [find_timing_paths -path_delay max -slack_max 0 \
              -group_path_count 1000000 -endpoint_path_count 1] {
  set kind [expr { [string match "*/*" [get_full_name [get_property $pe endpoint]]] ? "internal" : "outputs" }]
  incr snv($kind)
  set stns($kind) [expr { $stns($kind) + [get_property $pe slack] }]
}
foreach kind {outputs internal} {
  set w [expr { $sws($kind) eq "-" ? "-" : [format %.3f $sws($kind)] }]
  both $f "setup to $kind ws $w ns tns [format %.3f $stns($kind)] ns violating_endpoints $snv($kind)"
}
close $f

report_worst_slack -max -digits 3
report_worst_slack -min -digits 3
report_tns -digits 3
report_checks -path_delay max -group_path_count 5 -fields {slew cap input_pins fanout} -digits 3
report_checks -path_delay min -group_path_count 5 -fields {slew cap input_pins fanout} -digits 3
report_clock_skew -digits 3
if { $corner != "orfs" } {
  report_power
}
if { [info exists ::env(MODEL)] && $::env(MODEL) == 1 && $corner != "orfs" } {
  set_clock_latency -source 0 [all_clocks]
  write_timing_model $out/[[ord::get_db_block] getName]_$corner.lib
}
