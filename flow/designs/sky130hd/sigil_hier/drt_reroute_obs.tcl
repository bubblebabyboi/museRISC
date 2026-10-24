# Re-route a routed ORFS block with obstructions for the OpenRAM macro
# metal that the macros' LEF does not declare (#11 signoff).
#
# The OpenRAM LEFs shipped with ORFS (platforms/sky130ram) obstruct only
# part of the macros' drawn metal: per macro 1.0-5.1k um^2 of met1,
# 0.6-2.6k of met2, 0.9-5.9k of met3 and all of its met4 are neither a
# LEF pin nor a LEF OBS shape (signoff/sram_obs.rb). DRT cannot see that
# metal and routed through it: in the s116d CPU block GDS, signal wires
# over the macros touch it, joining macro pins (101 nets above the stock
# macros' own count, 48 of them vdd with gnd; signoff/macro_short.rb).
#
# Run in a copy of the block variant's results (5_2_route.odb = the routed,
# ECO'd block) with
#   make run RUN_SCRIPT=<this> FLOW_VARIANT=<copy> SIGIL_SRAM_OBS_TCL=<file>
# where <file> (signoff/sram_missing_obs.rb on the block GDS) sets
# sigil_sram_obs to the missing metal as {layer x1 y1 x2 y2} rectangles in
# block DBU. This script adds them as routing obstructions, removes the
# routing of every signal net (special nets / PDN stay), and routes again
# as the flow does: PRE_GLOBAL_ROUTE_TCL, pin access, global route
# (GLOBAL_ROUTE_ARGS), detailed route and the post-route antenna loop
# (MAX_REPAIR_ANTENNAS_ITER_DRT). The netlist and placement are the
# variant's (no repair_design / repair_timing here; drt_eco_repair.tcl can
# follow if the extracted timing needs it). Writes 5_2_route.odb and the
# OpenRCX SPEF 5_2_route_reroute.spef, and reports the extracted timing.
source $::env(SCRIPTS_DIR)/load.tcl
load_design 5_2_route.odb 5_1_grt.sdc

set block [ord::get_db_block]
set tech [ord::get_db_tech]
source $::env(SIGIL_SRAM_OBS_TCL)
set n 0
set layers [dict create]
foreach r $sigil_sram_obs {
  lassign $r ln x1 y1 x2 y2
  if { ![dict exists $layers $ln] } {
    dict set layers $ln [$tech findLayer $ln]
  }
  odb::dbObstruction_create $block [dict get $layers $ln] $x1 $y1 $x2 $y2
  incr n
}
puts "sigil reroute: $n obstructions for the OpenRAM metal missing from the LEF"

set nw 0
foreach net [$block getNets] {
  if { [$net isSpecial] } {
    continue
  }
  set w [$net getWire]
  if { $w ne "NULL" && $w ne "" } {
    odb::dbWire_destroy $w
    incr nw
  }
}
puts "sigil reroute: removed the routing of $nw signal nets"

if { [env_var_exists_and_non_empty PRE_GLOBAL_ROUTE_TCL] } {
  source $::env(PRE_GLOBAL_ROUTE_TCL)
}
set pa_args ""
append_env_var pa_args VIA_IN_PIN_MIN_LAYER -via_in_pin_bottom_layer 1
append_env_var pa_args VIA_IN_PIN_MAX_LAYER -via_in_pin_top_layer 1
log_cmd pin_access {*}$pa_args
log_cmd global_route -congestion_report_file $::env(REPORTS_DIR)/congestion_reroute.rpt \
  -congestion_iterations 30 {*}$::env(GLOBAL_ROUTE_ARGS)

set_propagated_clock [all_clocks]
set_placement_padding -global \
  -left $::env(CELL_PAD_IN_SITES_DETAIL_PLACEMENT) \
  -right $::env(CELL_PAD_IN_SITES_DETAIL_PLACEMENT)
if { [env_var_exists_and_non_empty DONT_USE_CELLS] } {
  set_dont_use $::env(DONT_USE_CELLS)
}

set dr_args ""
append_env_var dr_args OR_SEED -or_seed 1
append_env_var dr_args OR_K -or_k 1
append_env_var dr_args VIA_IN_PIN_MIN_LAYER -via_in_pin_bottom_layer 1
append_env_var dr_args VIA_IN_PIN_MAX_LAYER -via_in_pin_top_layer 1
append_env_var dr_args DISABLE_VIA_GEN -disable_via_gen 0
append_env_var dr_args REPAIR_PDN_VIA_LAYER -repair_pdn_vias 1
set all_args [concat [list -output_drc $::env(REPORTS_DIR)/5_route_drc.rpt \
  -output_maze $::env(RESULTS_DIR)/maze.log -droute_end_iter 64 -verbose 1 \
  -drc_report_iter_step 5] $dr_args]
log_cmd detailed_route {*}$all_args

set ant_rounds $::env(MAX_REPAIR_ANTENNAS_ITER_DRT)
set i 0
set na [check_antennas]
while { $na > 0 && $i < $ant_rounds } {
  incr i
  if { [repair_antennas] } {
    detailed_route {*}$all_args
  }
  set na [check_antennas]
  puts "sigil reroute: antenna round $i -> $na antenna nets"
}
check_antennas -report_file $::env(REPORTS_DIR)/drt_antennas.log
if { ![design_is_routed] } {
  error "Design has unrouted nets."
}
write_db $::env(RESULTS_DIR)/5_2_route.odb

define_process_corner -ext_model_index 0 X
set_extraction_rules_file $::env(RCX_RULES)
log_cmd extract_parasitics
set spef $::env(RESULTS_DIR)/5_2_route_reroute.spef
log_cmd write_spef $spef
log_cmd read_spef $spef
report_check_types -max_slew -max_capacitance -max_fanout -digits 3 > /dev/null
puts "sigil reroute: setup WNS [sta::format_time [sta::worst_slack_cmd max] 3] TNS [sta::format_time [sta::total_negative_slack_cmd max] 3] ([sta::endpoint_violation_count max] endpoints), hold WNS [sta::format_time [sta::worst_slack_cmd min] 3] ([sta::endpoint_violation_count min]), max slew [sta::max_slew_violation_count], max cap [sta::max_capacitance_violation_count], max fanout [sta::max_fanout_violation_count]; $na antenna nets"
report_design_area
