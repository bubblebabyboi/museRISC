# Extra post-detailed-route antenna repair rounds on a routed ORFS
# block (5_2_route.odb), for a run whose MAX_REPAIR_ANTENNAS_ITER_DRT
# rounds (detail_route.tcl) ended with a few antenna nets left. Same
# loop as detail_route.tcl: repair_antennas (diodes) + incremental
# detailed_route with the flow's arguments, until check_antennas is
# clean or SIGIL_ANT_ROUNDS rounds; then the same final checks and
# 5_2_route.odb is rewritten in place (run in a copy of the variant's
# results, `make run RUN_SCRIPT=<this> FLOW_VARIANT=<copy>`; make then
# continues with 5_3_fillcell .. finish .. abstract).
source $::env(SCRIPTS_DIR)/load.tcl
load_design 5_2_route.odb 5_1_grt.sdc
set_propagated_clock [all_clocks]
set rounds [expr { [info exists ::env(SIGIL_ANT_ROUNDS)] ? $::env(SIGIL_ANT_ROUNDS) : 6 }]
set args [list -output_drc $::env(REPORTS_DIR)/5_route_drc.rpt \
  -output_maze $::env(RESULTS_DIR)/maze.log \
  -droute_end_iter 64 -verbose 1 -drc_report_iter_step 5]
set n [check_antennas]
puts "sigil antenna fix: start with $n antenna nets"
set i 0
while { $n > 0 && $i < $rounds } {
  incr i
  if { [repair_antennas] } {
    detailed_route {*}$args
  }
  set n [check_antennas]
  puts "sigil antenna fix: round $i -> $n antenna nets"
}
check_antennas -report_file $::env(REPORTS_DIR)/drt_antennas.log
if { ![design_is_routed] } {
  error "Design has unrouted nets."
}
report_design_area
write_db $::env(RESULTS_DIR)/5_2_route.odb
puts "sigil antenna fix: done after $i rounds, $n antenna nets"
