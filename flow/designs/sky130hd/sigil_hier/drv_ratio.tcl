# Slew of selected driver pins of a routed ORFS block under the
# global-route parasitic estimate (what the flow's last repair_design,
# in the global-route stage, sees) and under the extracted 6_final.spef.
# Used to size SLEW_MARGIN / CAP_MARGIN (sigil_crypto_top/config.mk).
# Run on a finished variant:
#   make DESIGN_CONFIG=... FLOW_VARIANT=<variant> run RUN_SCRIPT=<this> \
#     RUN_LOG_NAME_STEM=drv_ratio DRV_PINS=<file, one pin name per line>
# (e.g. the driver pins of the finish report's max-slew / max-cap
# violators). Prints the violation counts in both modes and one line
#   R <pin> slew <estimate ns> <extracted ns>
# per pin.
source $::env(SCRIPTS_DIR)/load.tcl
load_design 5_2_route.odb 5_1_grt.sdc
set_propagated_clock [all_clocks]
set pins {}
set f [open $::env(DRV_PINS)]
while { [gets $f l] >= 0 } {
  if { $l ne "" } { lappend pins $l }
}
close $f
proc snap { tag } {
  global pins res
  foreach p $pins {
    set pin [get_pins [string map {"[" "\\[" "]" "\\]"} $p]]
    set res($tag,$p) [get_property $pin slew_max]
  }
}
estimate_parasitics -global_routing
report_check_types -max_slew -max_capacitance -max_fanout > /dev/null
puts "grt-estimate: max slew [sta::max_slew_violation_count] max cap [sta::max_capacitance_violation_count]"
snap grt
read_spef $::env(RESULTS_DIR)/6_final.spef
report_check_types -max_slew -max_capacitance -max_fanout > /dev/null
puts "spef: max slew [sta::max_slew_violation_count] max cap [sta::max_capacitance_violation_count]"
snap spef
foreach p $pins {
  puts [format "R %-45s slew %s %s" $p $res(grt,$p) $res(spef,$p)]
}
