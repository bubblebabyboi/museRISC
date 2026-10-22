# Per-layer global-routing derating for the sigil_hier blocks and top
# (PRE_GLOBAL_ROUTE_TCL, directly or via sigil_cpu/pre_grt.tcl).
#
# The sky130hd platform derates every layer by 0.2
# (platforms/sky130hd/fastroute.tcl). With that, FastRoute put 41 % of
# the crypto block's wire on met1 (3.24 of 7.83 m at 35 %
# utilization) while met3/met4 stayed 30-33 % used, and detailed
# routing started with 186k-264k violations, 64 % of them met1
# shorts. sky130hd cell pins are on li1, so met1 is also every pin's
# access layer (OpenLane reserves it almost entirely for that). Derate
# met1 hard so global routing assigns the trunks to met2-met4.
# SIGIL_GRT_ADJ overrides the list {layer adjustment ...}.
set sigil_grt_adj [expr { [info exists ::env(SIGIL_GRT_ADJ)] ? $::env(SIGIL_GRT_ADJ) :
  {met1 0.7 met2 0.25 met3 0.2 met4 0.2 met5 0.2} }]
foreach {l a} $sigil_grt_adj {
  if { [[ord::get_db_tech] findLayer $l] == "NULL" } { continue }
  set_global_routing_layer_adjustment $l $a
}
utl::info GRT 9030 "grt_layers.tcl: layer adjustments $sigil_grt_adj"
