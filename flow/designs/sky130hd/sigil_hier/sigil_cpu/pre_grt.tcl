# PRE_GLOBAL_ROUTE_TCL of sigil_cpu: per-layer derating
# (../grt_layers.tcl) and the met1-met3 blockages over the OpenRAM
# arrays (../../sigil_soc/pre_grt.tcl, whose first step re-applies a
# uniform ROUTING_LAYER_ADJUSTMENT, so it runs first).
source [file join [file dirname [info script]] .. .. sigil_soc pre_grt.tcl]
source [file join [file dirname [info script]] .. grt_layers.tcl]
