# POST_PDN_TCL of sigil_cpu: export the met4 straps that pdn.tcl puts
# over the OpenRAM macros as VDD/VSS block pins, like the std-cell
# grid's met4 straps (-pins met4 in ../block_pdn.tcl). pdngen does not
# make instance-grid straps pins; without this the macros' supply
# would only reach the block's pins through the macro-internal grid,
# which does not exist (the OpenRAM supply pins are isolated met3
# squares). The top level's met5 stripes drop via4 onto all of them.
set sigil_block [ord::get_db_block]
set sigil_met4 [[ord::get_db_tech] findLayer met4]
set sigil_srams {}
foreach inst [$sigil_block getInsts] {
  if { [[$inst getMaster] isBlock] } { lappend sigil_srams [$inst getBBox] }
}
set sigil_npins 0
foreach netname {VDD VSS} {
  set net [$sigil_block findNet $netname]
  set bterm [$sigil_block findBTerm $netname]
  if { $bterm == "NULL" } {
    utl::error PDN 9010 "post_pdn.tcl: no $netname block pin (expected from -pins met4)"
  }
  foreach sw [$net getSWires] {
    foreach box [$sw getWires] {
      if { [$box isVia] } { continue }
      if { [$box getTechLayer] != $sigil_met4 } { continue }
      set x1 [$box xMin]; set y1 [$box yMin]; set x2 [$box xMax]; set y2 [$box yMax]
      # only the straps lying over a macro (the std-cell straps are
      # pins already and stop at the macro halos)
      set over 0
      foreach bb $sigil_srams {
        # (5 um tolerance: instance-grid straps may run into the halo)
        set tol [expr { 5 * [$sigil_block getDbUnitsPerMicron] }]
        if { $x1 >= [$bb xMin] - $tol && $x2 <= [$bb xMax] + $tol &&
             $y1 >= [$bb yMin] - $tol && $y2 <= [$bb yMax] + $tol } {
          set over 1
          break
        }
      }
      if { !$over } { continue }
      set bp [odb::dbBPin_create $bterm]
      odb::dbBox_create $bp $sigil_met4 $x1 $y1 $x2 $y2
      $bp setPlacementStatus FIRM
      incr sigil_npins
    }
  }
}
utl::info PDN 9011 "post_pdn.tcl: exported $sigil_npins met4 OpenRAM straps as VDD/VSS pins"
