# Nets of the max-slew / max-cap violations of a routed ORFS block
# (TT platform lib + the OpenRCX 6_final.spef): driver, loads, antenna
# diodes, bounding box of the pins and the net's pin / wire capacitance
# (report_net). A wire capacitance far above ~0.2 fF per um of bounding
# box points at a routing detour, which repair_design (placement
# Steiner tree) does not see. Run on a finished variant:
#   docker run ... -v <results dir>:/res:ro -e RES=/res <ORFS image> \
#     openroad -exit -no_init slew_nets.tcl
set plat /OpenROAD-flow-scripts/flow/platforms
read_liberty $plat/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
foreach m [glob -directory $plat/sky130ram sky130_sram_*] {
  set n [file tail $m]
  if { [file exists $m/${n}_TT_1p8V_25C.lib] } {
    read_liberty $m/${n}_TT_1p8V_25C.lib
  }
}
set res $::env(RES)
read_db $res/6_final.odb
read_sdc $res/6_final.sdc
read_spef $res/6_final.spef
set_propagated_clock [all_clocks]
set blk [ord::get_db_block]
set dbu [$blk getDbUnitsPerMicron]
with_output_to_variable txt {
  report_check_types -max_slew -max_capacitance -violators -digits 3
}
puts $txt
set nets [dict create]
foreach line [split $txt "\n"] {
  if { [regexp {^(\S+)\s+\S+\s+\S+\s+\S+\s+\(VIOLATED\)} $line -> p] } {
    set pin [sta::find_pin $p]
    if { $pin eq "NULL" || $pin eq "" } {
      continue
    }
    set net [get_nets -quiet -of_objects $pin]
    if { $net ne "" } {
      dict set nets [get_full_name $net] 1
    }
  }
}
foreach nn [dict keys $nets] {
  set dn [$blk findNet $nn]
  set nd 0
  set nl 0
  set drv "?"
  set dloc ""
  set x1 1e18
  set y1 1e18
  set x2 -1e18
  set y2 -1e18
  foreach it [$dn getITerms] {
    set inst [$it getInst]
    set mn [[$inst getMaster] getName]
    if { [string match "sky130_fd_sc_hd__diode*" $mn] } {
      incr nd
    } elseif { ![$it isOutputSignal] } {
      incr nl
    }
    lassign [$inst getLocation] lx ly
    if { [$it isOutputSignal] } {
      set drv "[$inst getName] ($mn)"
      set dloc "([expr { $lx / $dbu }], [expr { $ly / $dbu }])"
    }
    set x1 [expr { min($x1, $lx) }]
    set x2 [expr { max($x2, $lx) }]
    set y1 [expr { min($y1, $ly) }]
    set y2 [expr { max($y2, $ly) }]
  }
  puts [format "NET %s driver %s at %s, %d loads, %d diodes, pin bbox %.0f x %.0f um" \
    $nn $drv $dloc $nl $nd [expr { ($x2 - $x1) / double($dbu) }] \
    [expr { ($y2 - $y1) / double($dbu) }]]
  report_net -digits 3 $nn
}
