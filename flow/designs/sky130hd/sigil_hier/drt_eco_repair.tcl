# Post-route electrical/timing ECO of a routed ORFS block (5_2_route.odb).
# The flow's last repair_design / repair_timing run in the global-route
# stage with global-route parasitics, before the GRT and post-DRT
# antenna repairs add their diodes; the routed block then has max-slew /
# max-cap violations and setup misses that only show with the
# extracted (OpenRCX) parasitics. This step times the routed design
# with the SPEF of its finish stage (SIGIL_ECO_SPEF; nets the resizer
# changes are re-estimated from placement, as the global routes stored
# in 5_2_route.odb predate the post-route antenna diodes), repairs slew /
# cap (repair_design with margins) and setup (repair_timing; hold too
# if any hold check fails), legalizes the new cells, re-routes the
# changed nets (incremental global route, then detailed_route with the
# flow's arguments, which only re-routes what changed), re-runs the
# antenna repair loop, extracts the routed result with OpenRCX (the
# finish stage's rules) and checks it. Up to SIGIL_ECO_ROUNDS rounds
# (default 1), stopping at the first round whose extracted timing has
# no setup / hold / max-slew / max-cap violation and no antenna net;
# 5_2_route.odb is rewritten after every round. Run in a copy of the
# variant's results with
# `make run RUN_SCRIPT=<this> FLOW_VARIANT=<copy> SIGIL_ECO_SPEF=<spef>`;
# make then continues with 5_3_fillcell .. finish .. abstract.
# (s116b ran the single-round version of commit 2d0e70a, without the
# OpenRCX check.)
source $::env(SCRIPTS_DIR)/load.tcl
load_design 5_2_route.odb 5_1_grt.sdc
proc sigil_env { name default } {
  return [expr { [info exists ::env($name)] && $::env($name) ne "" ? $::env($name) : $default }]
}
set slew_margin [sigil_env SIGIL_SLEW_MARGIN 20]
set cap_margin [sigil_env SIGIL_CAP_MARGIN 20]
set setup_margin [sigil_env SIGIL_SETUP_MARGIN 0.3]
set hold_margin [sigil_env SIGIL_HOLD_MARGIN 0.05]
set ant_rounds [sigil_env SIGIL_ANT_ROUNDS 8]
set eco_rounds [sigil_env SIGIL_ECO_ROUNDS 1]
set allow_congestion ""
if { [lsearch -exact $::env(GLOBAL_ROUTE_ARGS) -allow_congestion] >= 0 } {
  set allow_congestion -allow_congestion
}
proc sigil_report { tag } {
  report_check_types -max_slew -max_capacitance -max_fanout -digits 3 > /dev/null
  puts "sigil eco $tag: setup WNS [sta::format_time [sta::worst_slack_cmd max] 3] TNS [sta::format_time [sta::total_negative_slack_cmd max] 3] ([sta::endpoint_violation_count max] endpoints), hold WNS [sta::format_time [sta::worst_slack_cmd min] 3] ([sta::endpoint_violation_count min]), max slew [sta::max_slew_violation_count], max cap [sta::max_capacitance_violation_count], max fanout [sta::max_fanout_violation_count]"
}
proc sigil_clean { } {
  report_check_types -max_slew -max_capacitance -max_fanout -digits 3 > /dev/null
  return [expr { [sta::endpoint_violation_count max] == 0
    && [sta::endpoint_violation_count min] == 0
    && [sta::max_slew_violation_count] == 0
    && [sta::max_capacitance_violation_count] == 0 }]
}
set_propagated_clock [all_clocks]
log_cmd estimate_parasitics -placement
sigil_report "placement parasitics"
log_cmd read_spef $::env(SIGIL_ECO_SPEF)
sigil_report "extracted parasitics (before)"
if { [env_var_exists_and_non_empty DONT_USE_CELLS] } {
  set_dont_use $::env(DONT_USE_CELLS)
}
set_placement_padding -global \
  -left $::env(CELL_PAD_IN_SITES_DETAIL_PLACEMENT) \
  -right $::env(CELL_PAD_IN_SITES_DETAIL_PLACEMENT)
define_process_corner -ext_model_index 0 X
set_extraction_rules_file $::env(RCX_RULES)

set args [list -output_drc $::env(REPORTS_DIR)/5_route_drc.rpt \
  -output_maze $::env(RESULTS_DIR)/maze.log \
  -droute_end_iter 64 -verbose 1 -drc_report_iter_step 5]
for { set r 1 } { $r <= $eco_rounds } { incr r } {
  # (incremental global routing tracks every net the repairs and the
  # legalization change, from -start_incremental on)
  log_cmd global_route -start_incremental {*}$allow_congestion
  log_cmd repair_design -slew_margin $slew_margin -cap_margin $cap_margin -verbose
  detailed_placement_helper
  log_cmd global_route -end_incremental {*}$allow_congestion
  sigil_report "round $r after repair_design"

  log_cmd global_route -start_incremental {*}$allow_congestion
  log_cmd repair_timing -setup -setup_margin $setup_margin -verbose
  if { [sta::endpoint_violation_count min] > 0 } {
    log_cmd repair_timing -hold -hold_margin $hold_margin -verbose
  }
  detailed_placement_helper
  log_cmd check_placement -verbose
  log_cmd global_route -end_incremental {*}$allow_congestion
  sigil_report "round $r after repair_timing"

  log_cmd detailed_route {*}$args
  set n [check_antennas]
  set i 0
  while { $n > 0 && $i < $ant_rounds } {
    incr i
    if { [repair_antennas] } {
      detailed_route {*}$args
    }
    set n [check_antennas]
    puts "sigil eco: round $r antenna round $i -> $n antenna nets"
  }
  if { ![design_is_routed] } {
    error "Design has unrouted nets."
  }
  write_db $::env(RESULTS_DIR)/5_2_route.odb

  # OpenRCX of the routed result (as the finish stage), timed again
  log_cmd extract_parasitics
  set spef $::env(RESULTS_DIR)/5_2_route_eco$r.spef
  log_cmd write_spef $spef
  log_cmd read_spef $spef
  sigil_report "round $r routed (OpenRCX)"
  puts "sigil eco: round $r done, $n antenna nets after $i antenna rounds"
  if { $n == 0 && [sigil_clean] } {
    break
  }
}
check_antennas -report_file $::env(REPORTS_DIR)/drt_antennas.log
report_design_area
puts "sigil eco: done after [expr { min($r, $eco_rounds) }] round(s)"
