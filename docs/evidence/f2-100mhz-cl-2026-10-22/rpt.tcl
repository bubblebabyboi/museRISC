# Post-route reports for the 100 MHz CL build (read-only on the DCP):
# the build-3a / oops-fix set (timing summary -max_paths 5, CL
# utilisation) plus a per-clock table, the worst setup paths of the
# core, clk_main_a0, DDR and HBM AXI clocks, the worst inter-clock
# paths into/out of the core clock and a near-critical grouping of the
# core clock's endpoints.
set_param general.maxThreads 4
open_checkpoint [lindex $argv 0]
set out [lindex $argv 1]
file mkdir $out
report_timing_summary -max_paths 5 -file $out/post_route_timing_summary.rpt
report_utilization -hierarchical -hierarchical_depth 3 -cells [get_cells WRAPPER/CL] -file $out/post_route_util_hier.rpt
report_utilization -cells [get_cells WRAPPER/CL] -file $out/post_route_util_cl.rpt
report_clock_utilization -file $out/post_route_clock_util.rpt

proc slk {p} {
  if {[llength $p] == 0} { return "    -  " }
  set s [get_property SLACK $p]
  if {$s eq ""} { return "  inf  " }
  return [format "%7.3f" $s]
}
set fh [open $out/clock_summary.txt w]
puts $fh [format "%-46s %8s %8s  %-9s %-9s %-9s %-9s" clock period_ns MHz setup_in setup_all hold_in hold_all]
puts $fh "(setup_in/hold_in: paths launched and captured by the clock; setup_all/hold_all: every path captured by it, inter-clock included)"
foreach clk [lsort [get_clocks]] {
  set per [get_property PERIOD $clk]
  set pi [get_timing_paths -quiet -setup -from $clk -to $clk -max_paths 1 -nworst 1]
  set pa [get_timing_paths -quiet -setup -to $clk -max_paths 1 -nworst 1]
  set hi [get_timing_paths -quiet -hold -from $clk -to $clk -max_paths 1 -nworst 1]
  set ha [get_timing_paths -quiet -hold -to $clk -max_paths 1 -nworst 1]
  if {[llength $pa] == 0 && [llength $pi] == 0} continue
  set mhz [expr {$per > 0 ? 1000.0 / $per : 0}]
  puts $fh [format "%-46s %8.3f %8.2f  %-9s %-9s %-9s %-9s" $clk $per $mhz [slk $pi] [slk $pa] [slk $hi] [slk $ha]]
}
close $fh

set core clk_out2_clk_mmcm_b
foreach clk [list $core clk_main_a0 mmcm_clkout0 clk_out1_clk_mmcm_hbm] {
  if {[llength [get_clocks -quiet $clk]] == 0} continue
  report_timing -to [get_clocks $clk] -setup -max_paths 10 -nworst 1 -unique_pins -file $out/worst_setup_to_$clk.rpt
  report_timing -to [get_clocks $clk] -hold -max_paths 5 -nworst 1 -unique_pins -file $out/worst_hold_to_$clk.rpt
}
# Inter-clock paths touching the core clock.
set others [get_clocks -quiet -filter "NAME != $core"]
report_timing -from [get_clocks $core] -to $others -setup -max_paths 10 -nworst 1 -file $out/inter_from_core.rpt
report_timing -from $others -to [get_clocks $core] -setup -max_paths 10 -nworst 1 -file $out/inter_to_core.rpt

# Core clock near-critical endpoints, grouped by start -> end hierarchy.
proc grp {n} {
  set parts [split $n /]
  return [join [lrange $parts 0 [expr {min([llength $parts] - 2, 7)}]] /]
}
foreach {clk lim fname} [list $core 1.0 core_near_critical.txt clk_main_a0 0.5 main_a0_near_critical.txt] {
  set paths [get_timing_paths -quiet -setup -to [get_clocks $clk] -max_paths 20000 -nworst 1 -slack_lesser_than $lim]
  array unset cnt; array unset worst
  array set cnt {}; array set worst {}
  foreach p $paths {
    set s [get_property STARTPOINT_PIN $p]; set e [get_property ENDPOINT_PIN $p]
    set k "[grp $s] -> [grp $e]"
    set sl [get_property SLACK $p]
    if {![info exists cnt($k)]} { set cnt($k) 0; set worst($k) $sl }
    incr cnt($k)
    if {$sl < $worst($k)} { set worst($k) $sl }
  }
  set fh [open $out/$fname w]
  puts $fh "$clk: endpoints with setup slack < $lim ns: [llength $paths] (worst path per endpoint, grouped start -> end)"
  set rows {}
  foreach k [array names cnt] { lappend rows [list $worst($k) $cnt($k) $k] }
  foreach r [lsort -real -index 0 $rows] {
    puts $fh [format "%8.3f %6d  %s" {*}$r]
  }
  close $fh
}
puts "RPT100B done"
