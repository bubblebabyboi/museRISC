# Area / instance summary of a routed ORFS design (6_final.odb):
# die, core, hard blocks / macros, std cells by kind (fill / tap /
# decap / antenna diode / other), wire length per layer.
# usage (ORFS image): ODB=<6_final.odb> openroad -exit -no_init area.tcl
read_db $::env(ODB)
set block [ord::get_db_block]
set dbu [$block getDbUnitsPerMicron]
proc um2 { a } { return [format %.0f [expr { $a / double($::dbu) / double($::dbu) }]] }
set die [$block getDieArea]; set core [$block getCoreArea]
puts "die [expr {[$die xMin]/$dbu}] [expr {[$die yMin]/$dbu}] [expr {[$die xMax]/$dbu}] [expr {[$die yMax]/$dbu}] area_um2 [um2 [expr {double([$die dx])*[$die dy]}]]"
puts "core [expr {[$core xMin]/$dbu}] [expr {[$core yMin]/$dbu}] [expr {[$core xMax]/$dbu}] [expr {[$core yMax]/$dbu}] area_um2 [um2 [expr {double([$core dx])*[$core dy]}]]"
array set n {}; array set a {}
foreach k {block fill tap decap diode other} { set n($k) 0; set a($k) 0.0 }
foreach inst [$block getInsts] {
  set m [$inst getMaster]
  set ar [expr { double([$m getWidth]) * [$m getHeight] }]
  set nm [$m getName]
  if { [$m isBlock] } { set k block; puts "block [$inst getName] $nm [$inst getOrigin] [um2 $ar]" } \
  elseif { [string match "*__fill_*" $nm] || [string match "*__fakediode*" $nm] } { set k fill } \
  elseif { [string match "*__tap*" $nm] } { set k tap } \
  elseif { [string match "*__decap*" $nm] } { set k decap } \
  elseif { [string match "*__diode*" $nm] } { set k diode } \
  else { set k other }
  incr n($k); set a($k) [expr { $a($k) + $ar }]
}
foreach k {block fill tap decap diode other} { puts "insts $k $n($k) area_um2 [um2 $a($k)]" }
set sc [expr { $a(tap) + $a(decap) + $a(diode) + $a(other) }]
puts "std_cells_excl_fill [expr {$n(tap)+$n(decap)+$n(diode)+$n(other)}] area_um2 [um2 $sc]"
puts "std_cells_excl_fill_decap [expr {$n(tap)+$n(diode)+$n(other)}] area_um2 [um2 [expr {$sc - $a(decap)}]]"
# wire length per routing layer (from the routed wires)
array set wl {}
foreach net [$block getNets] {
  set w [$net getWire]
  if { $w == "NULL" } continue
  set dec [odb::dbWireDecoder]
  $dec begin $w
  set prev ""
  while { 1 } {
    set op [$dec next]
    if { $op == $odb::dbWireDecoder_END_DECODE } break
    if { $op == $odb::dbWireDecoder_PATH || $op == $odb::dbWireDecoder_JUNCTION || $op == $odb::dbWireDecoder_SHORT || $op == $odb::dbWireDecoder_VWIRE } { set prev "" }
    if { $op == $odb::dbWireDecoder_POINT || $op == $odb::dbWireDecoder_POINT_EXT } {
      set p [$dec getPoint]
      set l [[$dec getLayer] getName]
      if { $prev ne "" && [lindex $prev 2] eq $l } {
        set d [expr { abs([lindex $p 0]-[lindex $prev 0]) + abs([lindex $p 1]-[lindex $prev 1]) }]
        if { ![info exists wl($l)] } { set wl($l) 0 }
        set wl($l) [expr { $wl($l) + $d }]
      }
      set prev [list [lindex $p 0] [lindex $p 1] $l]
    }
    if { $op == $odb::dbWireDecoder_TECH_VIA || $op == $odb::dbWireDecoder_VIA } {
      if { $prev ne "" } { set prev [list [lindex $prev 0] [lindex $prev 1] [[$dec getLayer] getName]] }
    }
  }
}
set tot 0
foreach l [lsort [array names wl]] { puts "wire $l [format %.0f [expr {$wl($l)/double($dbu)}]] um"; set tot [expr {$tot + $wl($l)}] }
puts "wire total [format %.0f [expr {$tot/double($dbu)}]] um"
