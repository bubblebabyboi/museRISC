# #53: the whole failing-path picture of an F0 design, not just the worst
# path. Sourced by f0_ooc.tcl after route_design (uses its $out), or run
# standalone on a checkpoint from the repo root:
#   vivado -mode batch -source fpga/f0/f0_timing_reports.tcl \
#     -tclargs <dcp> <out_dir> [<cuts.tcl>, e.g. fpga/f0/f0_cuts.tcl]
# Writes into <out_dir>:
#   impl_fail_paths.rpt      worst path to each failing endpoint (first 500)
#   impl_fail_endpoints.tsv  every failing endpoint: slack, levels, delays,
#                            start/end pin and register group, hierarchies
#                            and RTL-named nets the path runs through
#   impl_fail_groups.rpt     failing endpoints by end register group and pin
#                            (D, CE, R, ...) and by start -> end group pair,
#                            then report_timing -from/-to summaries for the
#                            100 worst pairs
#   impl_fail_hier.rpt       failing endpoints by owning hierarchy (depth 1-4)
#   impl_design_analysis.rpt report_design_analysis -timing, 100 worst paths
#   impl_logic_levels.rpt    logic level distribution over the failing paths
# <cuts.tcl> sets `cuts` to a list of {name {net-regexp ...}} steps. Each
# step false-paths everything through the matching nets (cumulatively)
# and writes the reports again into <out_dir>/cut<N>-<name>: what would
# still fail once those paths are fixed, before changing any RTL.

# Register group of a start/end cell: drop bit/entry indices, LUTRAM
# primitives and the replication / RAM-slice suffixes synthesis and
# phys_opt add.
proc f0_reg_group {cell} {
  regsub {/(SP|DP|RAM[A-H](_D1)?)$} $cell {} cell
  regsub {(_rep(__[0-9]+)?|_replica(_[0-9]+)?|__[0-9]+)$} $cell {} cell
  regsub -all {_reg(\[[0-9]+\])+} $cell {_reg} cell
  regsub {(\[[0-9]+\])+$} $cell {} cell
  regsub {(_bram_[0-9]+|(_r[0-9]+)?(_[0-9]+){4})$} $cell {} cell
  return $cell
}

# Accumulate one failing endpoint into table array $tab under $key.
proc f0_add {tab key slack lvl sp ep} {
  upvar $tab t
  if {![info exists t(n,$key)]} {
    set t(n,$key) 0; set t(wns,$key) $slack; set t(tns,$key) 0.0; set t(lvl,$key) 0
    lappend t(keys) $key
  }
  incr t(n,$key)
  set t(tns,$key) [expr {$t(tns,$key) + $slack}]
  if {$slack < $t(wns,$key)} { set t(wns,$key) $slack }
  if {$lvl > $t(lvl,$key)} { set t(lvl,$key) $lvl }
  lappend t(sp,$key) $sp
  lappend t(ep,$key) $ep
}

# Print table $tab worst WNS first (or by key if bykey); returns the keys.
proc f0_table {fh tab title {bykey 0}} {
  upvar $tab t
  puts $fh "$title\n"
  puts $fh [format "%8s %6s %10s %4s  %s" WNS count TNS lvl group]
  set rows {}
  foreach k $t(keys) { lappend rows [list $t(wns,$k) $k] }
  if {$bykey} { set rows [lsort -index 1 $rows] } else { set rows [lsort -real -index 0 $rows] }
  set keys {}
  foreach r $rows {
    set k [lindex $r 1]
    puts $fh [format "%8.3f %6d %10.1f %4d  %s" $t(wns,$k) $t(n,$k) $t(tns,$k) \
      $t(lvl,$k) [string map {\t "  ->  "} $k]]
    lappend keys $k
  }
  puts $fh ""
  return $keys
}

# All reports above for the current timing into directory $out.
proc f0_fail_reports {out} {
  file mkdir $out
  # One timing path per failing endpoint (setup).
  set t0 [clock seconds]
  set paths [get_timing_paths -setup -max_paths 200000 -nworst 1 -slack_lesser_than 0]
  puts "F0_REPORTS failing_endpoints=[llength $paths]"
  set fh [open $out/impl_fail_endpoints.tsv w]
  puts $fh [join {slack levels datapath logic net start_pin end_pin start_group end_group through nets} \t]
  if {![llength $paths]} { close $fh; return }
  report_timing -max_paths 500 -nworst 1 -unique_pins -slack_lesser_than 0 \
    -file $out/impl_fail_paths.rpt

  array set ends {keys {}}; array set pairs {keys {}}; array set hier {keys {}}
  foreach p $paths slack [get_property SLACK $paths] lvl [get_property LOGIC_LEVELS $paths] \
      dp [get_property DATAPATH_DELAY $paths] dl [get_property DATAPATH_LOGIC_DELAY $paths] \
      dn [get_property DATAPATH_NET_DELAY $paths] \
      sp [get_property STARTPOINT_PIN $paths] ep [get_property ENDPOINT_PIN $paths] {
    set ec [get_cells -of_objects $ep]
    set sg [f0_reg_group [get_cells -of_objects $sp]]
    regsub {\[[0-9]+\]$} [get_property REF_PIN_NAME $ep] {} epin
    set eg [f0_reg_group $ec]/$epin
    set thru [lsort -unique [get_property PARENT [get_cells -of_objects $p]]]
    # Nets that kept their RTL name (not synthesis-generated), in path order.
    set nets {}
    foreach n [get_nets -of_objects $p] {
      if {![regexp {_n_[0-9]+$|/p_[0-9]+_(in|out)(\[[0-9]+\])?$} $n]} { lappend nets $n }
    }
    puts $fh [join [list $slack $lvl $dp $dl $dn $sp $ep $sg $eg [join $thru ,] [join $nets ,]] \t]
    f0_add ends $eg $slack $lvl $sp $ep
    f0_add pairs "$sg\t$eg" $slack $lvl $sp $ep
    set owner [split [get_property PARENT $ec] /]
    for {set k 0} {$k < 4 && $k < [llength $owner]} {incr k} {
      f0_add hier [join [lrange $owner 0 $k] /] $slack $lvl {} {}
    }
  }
  close $fh
  puts "F0_REPORTS endpoint table [expr {[clock seconds] - $t0}]s"

  set fh [open $out/impl_fail_groups.rpt w]
  f0_table $fh ends "Failing endpoints ([llength $paths]) by end register group"
  set worst [f0_table $fh pairs "By start -> end register group pair (worst path per endpoint)"]
  puts $fh "report_timing -from/-to summaries, 100 worst pairs"
  close $fh
  foreach k [lrange $worst 0 99] {
    set fh [open $out/impl_fail_groups.rpt a]
    puts $fh "\n=== [string map {\t "  ->  "} $k]"
    close $fh
    report_timing -from [get_pins [lsort -unique $pairs(sp,$k)]] \
      -to [get_pins [lsort -unique $pairs(ep,$k)]] -max_paths 5 -nworst 1 \
      -path_type summary -file $out/impl_fail_groups.rpt -append
  }

  set fh [open $out/impl_fail_hier.rpt w]
  f0_table $fh hier "Failing endpoints ([llength $paths]) by hierarchy owning the endpoint (depth 1-4)" 1
  close $fh

  report_design_analysis -timing -max_paths 100 -file $out/impl_design_analysis.rpt
  report_design_analysis -logic_level_distribution \
    -logic_level_dist_paths [expr {max(1000, [llength $paths])}] \
    -file $out/impl_logic_levels.rpt
  puts "F0_REPORTS done [expr {[clock seconds] - $t0}]s"
}

if {[info exists out]} {
  f0_fail_reports $out
} else {
  open_checkpoint [lindex $argv 0]
  set out [lindex $argv 1]
  f0_fail_reports $out
  if {[llength $argv] > 2} {
    source [lindex $argv 2]
    set n 0
    foreach c $cuts {
      lassign $c name res
      set nets {}
      foreach re $res {
        set nets [concat $nets [get_nets -quiet -hier -regexp -filter "NAME =~ \"$re\""]]
      }
      puts "F0_REPORTS cut[incr n] $name: [llength $nets] nets"
      if {[llength $nets]} { set_false_path -through $nets }
      f0_fail_reports $out/cut$n-$name
    }
  }
}
