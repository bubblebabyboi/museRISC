# Per OpenRAM macro: met3-met4 power vias (pdngen via4_5_*) inside the macro
# and the macro power-pin squares (LEF, met3) they land on: a via on a pin
# square of its own net only = ok; on a square of the other net = short.
read_db $::env(ODB)
set blk [ord::get_db_block]
set dbu [$blk getDbUnitsPerMicron]
foreach inst [$blk getInsts] {
  set m [$inst getMaster]
  if {![$m isBlock]} continue
  set bb [$inst getBBox]
  set o [$inst getOrient]
  set fx [expr {$o eq "MY" || $o eq "R180"}]; set fy [expr {$o eq "MX" || $o eq "R180"}]
  set W [$m getWidth]; set H [$m getHeight]
  set rects {}
  foreach mt [$m getMTerms] {
    set n [$mt getName]
    if {$n ne "vdd" && $n ne "gnd"} continue
    set net [expr {$n eq "vdd" ? "VDD" : "VSS"}]
    foreach mp [$mt getMPins] {
      foreach g [$mp getGeometry] {
        set l [$g getTechLayer]
        if {$l eq "NULL" || [$l getName] ne "met3"} continue
        if {$fx} { set x1 [expr {[$bb xMin]+$W-[$g xMax]}]; set x2 [expr {[$bb xMin]+$W-[$g xMin]}] } else { set x1 [expr {[$bb xMin]+[$g xMin]}]; set x2 [expr {[$bb xMin]+[$g xMax]}] }
        if {$fy} { set y1 [expr {[$bb yMin]+$H-[$g yMax]}]; set y2 [expr {[$bb yMin]+$H-[$g yMin]}] } else { set y1 [expr {[$bb yMin]+[$g yMin]}]; set y2 [expr {[$bb yMin]+[$g yMax]}] }
        lappend rects [list $net $x1 $y1 $x2 $y2]
      }
    }
  }
  set res {}
  foreach netname {VDD VSS} {
    set ok 0; set short 0; set nopin 0
    foreach sw [[$blk findNet $netname] getSWires] {
      foreach b [$sw getWires] {
        if {![$b isVia]} continue
        set v [$b getTechVia]; if {$v eq "NULL"} { set v [$b getBlockVia] }
        if {![string match "via4_5_*" [$v getName]]} continue
        set cx [expr {([$b xMin]+[$b xMax])/2}]; set cy [expr {([$b yMin]+[$b yMax])/2}]
        if {$cx < [$bb xMin] || $cx > [$bb xMax] || $cy < [$bb yMin] || $cy > [$bb yMax]} continue
        set own 0; set other 0
        foreach r $rects {
          lassign $r rn x1 y1 x2 y2
          if {[$b xMax] <= $x1 || [$b xMin] >= $x2 || [$b yMax] <= $y1 || [$b yMin] >= $y2} continue
          if {$rn eq $netname} { set own 1 } else { set other 1 }
        }
        if {$other} { incr short } elseif {$own} { incr ok } else { incr nopin }
      }
    }
    lappend res "$netname via3 on own pins $ok, touching other-net pins $short, on no pin $nopin"
  }
  puts "[$inst getName] ([$m getName] $o): [join $res {; }]"
}
