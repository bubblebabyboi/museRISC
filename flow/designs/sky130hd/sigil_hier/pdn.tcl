# sigil_soc_top (hierarchical sky130hd flow) power grid.
#
# Top-level std-cell grid = the platform one (met1 rails, met4
# vertical and met5 horizontal stripes, met5 pins). The hard blocks
# (sigil_cpu, sigil_crypto_top) use no met5 and export their met4
# VDD/VSS straps as pins (block_pdn.tcl, sigil_cpu/post_pdn.tcl), so
# the met5 stripes run across them and the block grid below adds the
# via4 connections onto those pins.

add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^VDD$} -power
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {VPWR}
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {VPB}
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {^VSS$} -ground
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {VGND}
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {VNB}
global_connect

set_voltage_domain -name {CORE} -power {VDD} -ground {VSS}

define_pdn_grid -name {grid} -voltage_domains {CORE} -pins {met5}
add_pdn_stripe -grid {grid} -layer {met1} -width {0.48} -pitch {5.44} -offset {0} -followpins
add_pdn_stripe -grid {grid} -layer {met4} -width {1.600} -pitch {27.140} -offset {13.570}
add_pdn_stripe -grid {grid} -layer {met5} -width {1.600} -pitch {27.200} -offset {13.600}
add_pdn_connect -grid {grid} -layers {met1 met4}
add_pdn_connect -grid {grid} -layers {met4 met5}

define_pdn_grid -name {blocks} -voltage_domains {CORE} -macro \
  -cells {sigil_cpu sigil_crypto_top} -halo {2.0 2.0 2.0 2.0} -grid_over_boundary
add_pdn_connect -grid {blocks} -layers {met4 met5}
