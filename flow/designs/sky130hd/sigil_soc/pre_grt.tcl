# PRE_GLOBAL_ROUTE_TCL for sigil_soc_top on sky130hd.
#
# 1. Re-apply ROUTING_LAYER_ADJUSTMENT. ORFS applies it only in
#    floorplan.tcl, so without this a change to it only takes effect
#    from a new floorplan.
set_global_routing_layer_adjustment \
  $::env(MIN_ROUTING_LAYER)-$::env(MAX_ROUTING_LAYER) $::env(ROUTING_LAYER_ADJUSTMENT)

# 2. Block met1-met3 over the OpenRAM macro arrays. The sky130ram LEF
#    OBS is the macros' detailed met1-met3 geometry (tens of thousands
#    of rectangles covering only 6-14 % of the macro), so global and
#    detailed routing both treat the gaps inside the macro as routing
#    space: with only the LEF OBS, detailed routing reached ~1M
#    violations (mostly met1/met2 shorts) after its first iteration.
#    The blockage covers each macro minus an edge band deep enough to
#    keep all signal pins (and their LEF OBS) reachable: per master,
#    the deepest signal-pin extent from each edge (measured from the
#    LEF) plus 2-3 um. On met3 it also leaves out the two columns of
#    met4 power straps from pdn.tcl, whose via3s land on the met3
#    vdd/gnd pins.
#    master {left bottom right top} edge bands (um), macro coordinates
source [file join [file dirname [info script]] sram_macros.tcl]
set sigil_sram_band {
  sky130_sram_1rw1r_64x256_8  {78 76 77 19}
  sky130_sram_1rw1r_128x256_8 {127 76 3 29}
  sky130_sram_1rw1r_44x64_8   {58 51 57 29}
}
# met3 keep-out x ranges around the strap groups (relative to the
# group origins in pdn.tcl: straps span a-0.555..a+7.2, b-1.0..b+8.6)
set sigil_strap_keepout { {-2.5 9.5} {-3.0 10.5} }

set sigil_obs_block [ord::get_db_block]
set sigil_obs_dbu [$sigil_obs_block getDbUnitsPerMicron]
set sigil_obs_n 0
foreach sigil_inst [$sigil_obs_block getInsts] {
  set sigil_master [$sigil_inst getMaster]
  if { ![$sigil_master isBlock] } { continue }
  set sigil_mname [$sigil_master getName]
  lassign [dict get $sigil_sram_band $sigil_mname] bl bb br bt
  lassign [dict get $sigil_sram_pdn $sigil_mname] sigil_a sigil_b
  set sigil_bbox [$sigil_inst getBBox]
  set sigil_llx [expr { double([$sigil_bbox xMin]) / $sigil_obs_dbu }]
  set sigil_lly [expr { double([$sigil_bbox yMin]) / $sigil_obs_dbu }]
  set sigil_w [expr { double([$sigil_master getWidth]) / $sigil_obs_dbu }]
  set sigil_h [expr { double([$sigil_master getHeight]) / $sigil_obs_dbu }]
  switch [$sigil_inst getOrient] {
    R0   { set sigil_fx 0; set sigil_fy 0 }
    MX   { set sigil_fx 0; set sigil_fy 1 }
    MY   { set sigil_fx 1; set sigil_fy 0 }
    R180 { set sigil_fx 1; set sigil_fy 1 }
    default { utl::error PDN 9003 "pre_grt.tcl: unsupported orientation for [$sigil_inst getName]" }
  }
  set x1 $bl; set x2 [expr { $sigil_w - $br }]
  set y1 $bb; set y2 [expr { $sigil_h - $bt }]
  # met3 pieces: [x1,x2] minus the strap keep-outs (macro coordinates)
  lassign $sigil_strap_keepout ka kb
  set cuts [list [list [expr { $sigil_a + [lindex $ka 0] }] [expr { $sigil_a + [lindex $ka 1] }]] \
                 [list [expr { $sigil_b + [lindex $kb 0] }] [expr { $sigil_b + [lindex $kb 1] }]]]
  set met3_x {}
  set cur $x1
  foreach c [lsort -real -index 0 $cuts] {
    lassign $c c1 c2
    if { $c1 > $cur } { lappend met3_x [list $cur [expr { min($c1, $x2) }]] }
    set cur [expr { max($cur, $c2) }]
  }
  if { $cur < $x2 } { lappend met3_x [list $cur $x2] }
  foreach {layer xs} [list met1 [list [list $x1 $x2]] met2 [list [list $x1 $x2]] met3 $met3_x] {
    set tl [[ord::get_db_tech] findLayer $layer]
    foreach xr $xs {
      lassign [sigil_mapx {*}$xr] ax1 ax2
      lassign [sigil_mapy $y1 $y2] ay1 ay2
      odb::dbObstruction_create $sigil_obs_block $tl \
        [expr { round($ax1 * $sigil_obs_dbu) }] [expr { round($ay1 * $sigil_obs_dbu) }] \
        [expr { round($ax2 * $sigil_obs_dbu) }] [expr { round($ay2 * $sigil_obs_dbu) }]
      incr sigil_obs_n
    }
  }
}
utl::info PDN 9004 "pre_grt.tcl: $sigil_obs_n met1-met3 routing blockages over the SRAM macros"
