# fam.tcl <dcp>: worst setup slack of the PMP and vstart families (#53 100 MHz final F0 check)
open_checkpoint [lindex $argv 0]
proc w {name args} {
  if {[catch {get_timing_paths -setup -max_paths 1 -nworst 1 {*}$args} p]} { puts "FAM $name: no such objects"; return }
  if {[llength $p] == 0} { puts "FAM $name: no path"; return }
  set e [get_property ENDPOINT_PIN $p]
  puts "FAM $name: slack [get_property SLACK $p] levels [get_property LOGIC_LEVELS $p] from [get_property STARTPOINT_PIN $p] to $e"
}
set c u_cpu/u_core
w "from pmpaddr/pmpcfg (PMP data/fetch/walker check)" -from [get_cells -quiet "$c/u_csr/pmpaddr_q_reg* $c/u_csr/pmpcfg_q_reg*"]
w "through pmp_allow_data" -through [get_nets -quiet -hier -filter {NAME =~ *pmp_allow_data*}]
w "through PMP walker allow" -through [get_nets -quiet -hier -regexp -filter {NAME =~ ".*pmp_allow_(walk|ptw|b|c).*"}]
w "PMP fetch check -> fetch side" -from [get_cells -quiet "$c/u_csr/pmpaddr_q_reg* $c/u_csr/pmpcfg_q_reg*"] -to [get_cells -quiet -hier -regexp -filter {NAME =~ ".*(u_icache/.*|/ifid_.*_q_reg.*|/pc_r_reg.*)"}]
w "from vstart_q (vstart EX hold / VLS start)" -from [get_cells -quiet "$c/u_csr/vstart_q_reg*"]
w "from vl_q" -from [get_cells -quiet "$c/u_csr/vl_q_reg*"]
w "to vstart_q" -to [get_cells -quiet "$c/u_csr/vstart_q_reg*"]
w "from idex (EX) to pc/ifid/idex CE (EX hold)" -from [get_cells -quiet "$c/idex_*_q_reg*"] -to [get_pins -quiet -of [get_cells -quiet "$c/idex_*_q_reg* $c/ifid_*_q_reg*"] -filter {REF_PIN_NAME == CE}]
puts FAM_DONE
