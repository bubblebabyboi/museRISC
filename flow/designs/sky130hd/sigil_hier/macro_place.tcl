# MACRO_PLACEMENT_TCL of sigil_soc_top (hierarchical sky130hd flow):
# fixed positions of the two hard blocks (SIGIL_CPU_XY and
# SIGIL_CRYPTO_XY, floorplan in config.mk). Instances are found by
# master name, so the flattened instance names do not matter.
set sigil_pos [dict create \
  sigil_cpu        $::env(SIGIL_CPU_XY) \
  sigil_crypto_top $::env(SIGIL_CRYPTO_XY)]
set sigil_block [ord::get_db_block]
set sigil_dbu [$sigil_block getDbUnitsPerMicron]
set sigil_seen {}
foreach inst [$sigil_block getInsts] {
  set m [[$inst getMaster] getName]
  if { ![dict exists $sigil_pos $m] } { continue }
  lassign [dict get $sigil_pos $m] x y
  $inst setOrient R0
  $inst setOrigin [expr { round($x * $sigil_dbu) }] [expr { round($y * $sigil_dbu) }]
  $inst setPlacementStatus FIRM
  lappend sigil_seen $m
  utl::info MPL 9020 "macro_place.tcl: [$inst getName] ($m) at ($x, $y) R0"
}
foreach m [dict keys $sigil_pos] {
  if { [lsearch -exact $sigil_seen $m] < 0 } {
    utl::error MPL 9021 "macro_place.tcl: no instance of $m"
  }
}
