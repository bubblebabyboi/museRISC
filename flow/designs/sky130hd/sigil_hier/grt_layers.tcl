# Per-layer global-routing derating for the sigil_hier blocks
# (PRE_GLOBAL_ROUTE_TCL, directly or via sigil_cpu/pre_grt.tcl).
# SIGIL_GRT_ADJ = {layer adjustment ...}; the default is the sky130hd
# platform's uniform 0.2 (platforms/sky130hd/fastroute.tcl), which
# ../sigil_soc/pre_grt.tcl would otherwise replace with
# ROUTING_LAYER_ADJUSTMENT.
#
# Tried and dropped (docs/evidence/w7-sky130-hier-2026-10-22.log):
# reserving met1 for pin access (met1 0.7 / 0.5, as OpenLane does).
# FastRoute then detours instead of using met3/met4 more: the crypto
# block's global demand rose 18 % and overflowed (40,801 gcells at
# 42 % utilization, 15,856 at 30 %), where the uniform 0.2 run had none.
set sigil_grt_adj [expr { [info exists ::env(SIGIL_GRT_ADJ)] ? $::env(SIGIL_GRT_ADJ) :
  {met1 0.2 met2 0.2 met3 0.2 met4 0.2 met5 0.2} }]
foreach {l a} $sigil_grt_adj {
  if { [[ord::get_db_tech] findLayer $l] == "NULL" } { continue }
  set_global_routing_layer_adjustment $l $a
}
utl::info GRT 9030 "grt_layers.tcl: layer adjustments $sigil_grt_adj"
