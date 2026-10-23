# SoC pin and clock-cell summary of a routed ORFS design (6_final.odb):
# signal / supply bterms, signal pin shapes per layer, clkbuf/clkinv count.
# usage (ORFS image): ODB=<6_final.odb> openroad -exit -no_init io.tcl
read_db $::env(ODB)
set block [ord::get_db_block]
set n 0; set p 0; array set ly {}
foreach bt [$block getBTerms] {
  if { [$bt getSigType] == "POWER" || [$bt getSigType] == "GROUND" } { incr p; continue }
  incr n
  foreach bp [$bt getBPins] { foreach b [$bp getBoxes] { set l [[$b getTechLayer] getName]; if {![info exists ly($l)]} {set ly($l) 0}; incr ly($l) } }
}
puts "signal bterms $n, power/ground bterms $p, signal pin shapes by layer: [array get ly]"
set cb 0
foreach inst [$block getInsts] { set m [[$inst getMaster] getName]; if { [string match "*clkbuf*" $m] || [string match "*clkinv*" $m] } { incr cb } }
puts "clock buffers/inverters (clkbuf/clkinv masters) $cb"
