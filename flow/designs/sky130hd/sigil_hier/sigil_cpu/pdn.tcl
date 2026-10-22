# sigil_cpu hard block power grid (PDN_TCL of sigil_cpu/config.mk).
#
# Block std-cell grid as in ../block_pdn.tcl (met1 rails, met4 straps
# exported as VDD/VSS pins; no met5 in the block). The OpenRAM macros
# get the met4 straps over their met3 vdd/gnd pin columns and the met4
# obstruction over the undeclared GDS met4 strip from the flat flow
# (../../sigil_soc/pdn.tcl, data in ../../sigil_soc/sram_macros.tcl);
# here those straps only drop via3 onto the macro pins, and they are
# also exported as met4 VDD/VSS pins (sigil_export_sram_straps below)
# so the top-level met5 stripes connect them, as they connect the
# std-cell straps.

source [file join [file dirname [info script]] .. block_pdn.tcl]
source [file join [file dirname [info script]] .. .. sigil_soc sram_macros.tcl]

set sigil_block [ord::get_db_block]
set sigil_dbu [$sigil_block getDbUnitsPerMicron]
set sigil_met4 [[ord::get_db_tech] findLayer met4]
set sigil_ngrid 0
foreach sigil_inst [$sigil_block getInsts] {
  set sigil_master [$sigil_inst getMaster]
  if { ![$sigil_master isBlock] } { continue }
  set sigil_mname [$sigil_master getName]
  if { ![dict exists $sigil_sram_pdn $sigil_mname] } {
    utl::error PDN 9001 "sigil_cpu pdn.tcl: no macro grid for master $sigil_mname"
  }
  lassign [dict get $sigil_sram_pdn $sigil_mname] sigil_a sigil_b sigil_obs
  set sigil_orient [$sigil_inst getOrient]
  set sigil_bb [$sigil_inst getBBox]
  set sigil_llx [expr { double([$sigil_bb xMin]) / $sigil_dbu }]
  set sigil_lly [expr { double([$sigil_bb yMin]) / $sigil_dbu }]
  set sigil_w [expr { double([$sigil_master getWidth]) / $sigil_dbu }]
  set sigil_h [expr { double([$sigil_master getHeight]) / $sigil_dbu }]
  switch $sigil_orient {
    R0     { set sigil_fx 0; set sigil_fy 0 }
    MX     { set sigil_fx 0; set sigil_fy 1 }
    MY     { set sigil_fx 1; set sigil_fy 0 }
    R180   { set sigil_fx 1; set sigil_fy 1 }
    default {
      utl::error PDN 9002 "sigil_cpu pdn.tcl: [$sigil_inst getName] has orientation $sigil_orient (only R0/MX/MY/R180 supported)"
    }
  }
  lassign $sigil_obs ox1 oy1 ox2 oy2
  lassign [sigil_mapx $ox1 $ox2] ax1 ax2
  lassign [sigil_mapy $oy1 $oy2] ay1 ay2
  odb::dbObstruction_create $sigil_block $sigil_met4 \
    [expr { round($ax1 * $sigil_dbu) }] [expr { round($ay1 * $sigil_dbu) }] \
    [expr { round($ax2 * $sigil_dbu) }] [expr { round($ay2 * $sigil_dbu) }]

  set sigil_g "sigil_sram_grid_[incr sigil_ngrid]"
  define_pdn_grid -name $sigil_g -voltage_domains {CORE} -macro \
    -instances [list [sigil_glob_quote [$sigil_inst getName]]] \
    -halo {2.0 2.0 2.0 2.0}
  foreach {sigil_org sigil_straps} [list $sigil_a $sigil_sram_left $sigil_b $sigil_sram_right] {
    foreach sigil_s $sigil_straps {
      lassign $sigil_s net x1 x2
      add_pdn_stripe -grid $sigil_g -layer {met4} -nets [list $net] \
        -width [format %.3f [expr { $x2 - $x1 }]] -pitch 5000 \
        -offset [format %.3f [expr { $sigil_org + ($x1 + $x2) / 2.0 }]]
    }
  }
  add_pdn_connect -grid $sigil_g -layers {met3 met4}
}
