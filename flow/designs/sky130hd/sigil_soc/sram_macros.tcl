# OpenRAM macro data shared by pdn.tcl and pre_grt.tcl (sigil_soc_top
# on sky130hd). See pdn.tcl for the macro power-pin layout.

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
