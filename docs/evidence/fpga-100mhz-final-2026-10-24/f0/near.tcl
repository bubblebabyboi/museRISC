# near.tcl <dcp> <out.tsv> <slack_limit>: worst path per endpoint with slack < limit, with
# start/end register group and family flags (PMP via g_pmp_par / pmp_allow, vstart).
set dcp [lindex $argv 0]; set out [lindex $argv 1]; set lim [lindex $argv 2]
source near_procs.tcl
open_checkpoint $dcp
set paths [get_timing_paths -setup -max_paths 5000 -nworst 1 -unique_pins -slack_lesser_than $lim]
set fh [open $out w]
puts $fh "slack\tlevels\tstart\tend\tpmp\tvstart\tpmp_nets"
foreach p $paths {
  set s [get_property SLACK $p]
  set lv [get_property LOGIC_LEVELS $p]
  set sc [get_cells -of [get_property STARTPOINT_PIN $p]]
  set ec [get_cells -of [get_property ENDPOINT_PIN $p]]
  set epin [get_property REF_PIN_NAME [get_property ENDPOINT_PIN $p]]
  set nets [get_nets -of $p]
  set pm {}
  foreach n $nets { if {[regexp {g_pmp_par|pmp_allow|pmp_hit|pmpaddr|pmpcfg} $n]} { lappend pm $n } }
  set vs [expr {[regexp {vstart} "$sc $nets"] ? 1 : 0}]
  puts $fh "$s\t$lv\t[f0_reg_group $sc]\t[f0_reg_group $ec]/$epin\t[expr {[llength $pm] > 0 || [regexp {pmp} $sc]}]\t$vs\t[lrange $pm 0 2]"
}
close $fh
puts "NEAR_DONE [llength $paths]"
