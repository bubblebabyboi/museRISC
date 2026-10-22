# POST_GLOBAL_ROUTE_TCL of the sigil_hier blocks: one more max slew /
# max cap repair after the global-route stage's antenna repair.
# global_route.tcl runs repair_design (with SLEW_MARGIN / CAP_MARGIN)
# and repair_timing first and the antenna repair last; the antenna
# repair then hangs its diodes on long nets that repair_design had
# just brought under the margin. In the crypto block (w34m, 40 %
# margins) the worst net after the antenna repair was a buffer driving
# one gate over a long route with 32 diodes on it: 1.24 ns estimated
# slew (83 % of the 1.5 ns limit; routed and extracted, slews come out
# 1.02-1.64x the estimate, see drv_ratio.tcl). This repeats the
# stage's repair_design sequence (repair_design_helper, legalization,
# incremental global route of the changed nets) on the final netlist.
# Nets it splits get no new global-route antenna check; the post-route
# antenna rounds (MAX_REPAIR_ANTENNAS_ITER_DRT) cover them.
# Sourced by global_route.tcl after its antenna repair and parasitics
# estimate, before 5_1_grt.odb is written.
# NOT USED: it works on a saved 5_1_grt.odb in a fresh `make run`
# (w34m test), but inside the global-route stage (run w34n) its
# repair_design stopped with "[ERROR EST-0104] inconsistent parasitics
# state". No config sets it; the crypto block (w34m) routed with 0
# max-slew / max-cap violations without it.
proc sigil_post_grt_drv { tag } {
  report_check_types -max_slew -max_capacitance -max_fanout > /dev/null
  puts "sigil post-GRT repair $tag: max slew [sta::max_slew_violation_count],\
    max cap [sta::max_capacitance_violation_count],\
    max fanout [sta::max_fanout_violation_count],\
    setup WS [sta::format_time [sta::worst_slack_cmd max] 3],\
    hold WS [sta::format_time [sta::worst_slack_cmd min] 3]"
}
set sigil_post_grt_cong ""
if { [lsearch -exact $::env(GLOBAL_ROUTE_ARGS) -allow_congestion] >= 0 } {
  set sigil_post_grt_cong -allow_congestion
}
log_cmd estimate_parasitics -global_routing
sigil_post_grt_drv "before"
repair_design_helper
log_cmd global_route -start_incremental {*}$sigil_post_grt_cong
detailed_placement_helper
log_cmd global_route -end_incremental {*}$sigil_post_grt_cong \
  -congestion_report_file $::env(REPORTS_DIR)/congestion_post_grt_repair.rpt
log_cmd check_placement -verbose
log_cmd estimate_parasitics -global_routing
sigil_post_grt_drv "after"
