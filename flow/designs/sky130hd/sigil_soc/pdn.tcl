# sigil_soc_top on sky130hd: power grid (PDN_TCL in config.mk).
#
# The standard-cell grid is the platform one (platforms/sky130hd/
# pdn.tcl): met1 rails, met4 vertical and met5 horizontal stripes.
# The platform macro grids do not fit the OpenRAM macros used here
# (sky130ram sky130_sram_1rw1r_{64x256,128x256,44x64}_8):
#  - their supply pins are named vdd/gnd, which the platform
#    global connections do not match;
#  - those pins are only small met3 squares (0.49 x 0.49 um), with
#    no met4 pins for the platform's met4-met5 macro connection.
#    In every one of the three macros the squares line up in two
#    groups of five full-height columns (the "left" and "right"
#    groups below; the two mixed vdd/gnd columns between them are
#    not used);
#  - the GDS has met4 (signal routing) in a strip along the bottom
#    edge that the LEF does not declare (LEF OBS stops at met3).
# So each macro gets its own grid of met4 straps placed exactly over
# its pin columns (via3 to the met3 pins, via4 to the core met5
# stripes), and a met4 routing obstruction over the undeclared strip,
# which also cuts the straps there. Strap edges are listed in the
# macro's own coordinates (pdngen applies the placed orientation to
# instance grids; the obstruction box is mirrored here).

####################################
# global connections
####################################
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^VDD$} -power
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^VDDPE$}
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^VDDCE$}
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {VPWR}
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {VPB}
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^vdd$}
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {^VSS$} -ground
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {^VSSE$}
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {VGND}
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {VNB}
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {^gnd$}
global_connect

####################################
# voltage domains
####################################
set_voltage_domain -name {CORE} -power {VDD} -ground {VSS}

####################################
# standard cell grid (platform)
####################################
define_pdn_grid -name {grid} -voltage_domains {CORE} -pins {met5}
add_pdn_stripe -grid {grid} -layer {met1} -width {0.48} -pitch {5.44} -offset {0} -followpins
add_pdn_stripe -grid {grid} -layer {met4} -width {1.600} -pitch {27.140} -offset {13.570}
add_pdn_stripe -grid {grid} -layer {met5} -width {1.600} -pitch {27.200} -offset {13.600}
add_pdn_connect -grid {grid} -layers {met1 met4}
add_pdn_connect -grid {grid} -layers {met4 met5}

####################################
# OpenRAM macro grids
####################################
# Per master: left-group origin a (first gnd column), right-group
# origin b (first vdd column), undeclared met4 box {x1 y1 x2 y2}
# (from the macro GDS, layer 71/20), all in um, macro coordinates.
set sigil_sram_pdn {
  sky130_sram_1rw1r_64x256_8  {110.205 923.08 {97.57 3.14 870.745 60.475}}
  sky130_sram_1rw1r_128x256_8 {160.655 973.53 {140.18 3.14 975.63 47.055}}
  sky130_sram_1rw1r_44x64_8   {84.875 352.83 {71.78 3.14 358.27 31.195}}
}
# Straps {net x1 x2} relative to the group origin. Column offsets
# (pin left edges) are the same in all three macros:
#   left : gnd 0, vdd 2.125, vdd 4.285, gnd 6.195, vdd 7.555
#   right: vdd 0, gnd 1.36, vdd 3.27, vdd 5.43, gnd 7.555
# Straps are >= 1.6 um wide (via4 needs 1.18 um of met4) and cover
# their 0.49 um pins; the two adjacent vdd columns share one strap.
# pdngen drops or trims a strap that runs closer than ~0.6 um to
# another one (seen at 0.35 and 0.57 um), so one column per group
# is left unstrapped (left vdd 7.555, right gnd 1.36): each group
# gets three straps, >= 0.67 um apart.
set sigil_sram_left  { {VSS -0.555 1.045} {VDD 1.975 4.925} {VSS 5.6 7.2} }
set sigil_sram_right { {VDD -1.0 0.6} {VDD 3.12 6.07} {VSS 7.0 8.6} }

# -instances is matched as a glob pattern; instance names from
# the netlist contain literal backslashes and brackets.
proc sigil_glob_quote { name } {
  return [string map {\\ \\\\ [ \\[ ] \\] * \\* ? \\?} $name]
}
# x/y interval in macro coordinates -> absolute placed interval
proc sigil_mapx { x1 x2 } {
  upvar sigil_fx fx sigil_llx llx sigil_w w
  if { $fx } { return [list [expr { $llx + $w - $x2 }] [expr { $llx + $w - $x1 }]] }
  return [list [expr { $llx + $x1 }] [expr { $llx + $x2 }]]
}
proc sigil_mapy { y1 y2 } {
  upvar sigil_fy fy sigil_lly lly sigil_h h
  if { $fy } { return [list [expr { $lly + $h - $y2 }] [expr { $lly + $h - $y1 }]] }
  return [list [expr { $lly + $y1 }] [expr { $lly + $y2 }]]
}


set sigil_block [ord::get_db_block]
set sigil_dbu [$sigil_block getDbUnitsPerMicron]
set sigil_met4 [[ord::get_db_tech] findLayer met4]
set sigil_ngrid 0
foreach sigil_inst [$sigil_block getInsts] {
  set sigil_master [$sigil_inst getMaster]
  if { ![$sigil_master isBlock] } { continue }
  set sigil_mname [$sigil_master getName]
  if { ![dict exists $sigil_sram_pdn $sigil_mname] } {
    utl::error PDN 9001 "sigil pdn.tcl: no macro grid for master $sigil_mname"
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
      utl::error PDN 9002 "sigil pdn.tcl: [$sigil_inst getName] has orientation $sigil_orient (only R0/MX/MY/R180 supported)"
    }
  }
  # met4 routing obstruction over the undeclared GDS met4 strip
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
      # pdngen places instance-grid stripes in the macro's own
      # (unrotated) frame, then applies the placed orientation;
      # -offset is the strap centre from the macro's left edge.
      add_pdn_stripe -grid $sigil_g -layer {met4} -nets [list $net] \
        -width [format %.3f [expr { $x2 - $x1 }]] -pitch 5000 \
        -offset [format %.3f [expr { $sigil_org + ($x1 + $x2) / 2.0 }]]
    }
  }
  add_pdn_connect -grid $sigil_g -layers {met3 met4}
  add_pdn_connect -grid $sigil_g -layers {met4 met5}
}
