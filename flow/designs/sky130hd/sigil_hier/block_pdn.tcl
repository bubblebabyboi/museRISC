# Power grid of a sigil_hier hard block (sky130hd), PDN_TCL of the
# block configs. Caravel-style macro grid: met1 rails and met4
# vertical straps, the met4 straps exported as the block's VDD/VSS
# pins (-pins met4). The block routes signals on met1-met4 only, so
# met5 stays free above it: the top-level met5 stripes cross the block
# and drop via4 onto these pins (../sigil_hier/pdn.tcl). Strap
# width/pitch are the platform's (platforms/sky130hd/pdn.tcl).

add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^VDD$} -power
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {VPWR}
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {VPB}
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^vdd$}
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {^VSS$} -ground
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {VGND}
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {VNB}
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {^gnd$}
global_connect

set_voltage_domain -name {CORE} -power {VDD} -ground {VSS}

define_pdn_grid -name {block} -voltage_domains {CORE} -pins {met4}
add_pdn_stripe -grid {block} -layer {met1} -width {0.48} -pitch {5.44} -offset {0} -followpins
add_pdn_stripe -grid {block} -layer {met4} -width {1.600} -pitch {27.140} -offset {13.570}
add_pdn_connect -grid {block} -layers {met1 met4}
