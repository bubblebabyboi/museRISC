# PRE_GLOBAL_ROUTE_TCL: re-apply ROUTING_LAYER_ADJUSTMENT at global
# route. ORFS applies it in floorplan.tcl, so without this a change to
# it only takes effect from a new floorplan.
set_global_routing_layer_adjustment \
  $::env(MIN_ROUTING_LAYER)-$::env(MAX_ROUTING_LAYER) $::env(ROUTING_LAYER_ADJUSTMENT)
