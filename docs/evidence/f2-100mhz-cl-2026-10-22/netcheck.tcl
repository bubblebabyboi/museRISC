# Read-only net-name check on the CL post-synth DCP: for each #53
# FPGA_TIMING / VRF_OREG generate block, nets carrying its label (the
# FPGA branch) versus its else-branch label (the default branch).
set_param general.maxThreads 2
open_checkpoint [lindex $argv 0]
foreach {on off} {g_ireg g_ireg_off g_dreg g_dreg_off g_mc_req g_mc_req_off g_vls_end g_vls_end_off g_port_sel g_port_sel_off g_dl g_dl_off g_wr_attempt g_wr_attempt_off g_pmp_par g_pmp_par_off g_oreg g_noreg} {
  set n1 [get_nets -quiet -hier -filter "NAME =~ *${on}.*"]
  set n0 [get_nets -quiet -hier -filter "NAME =~ *${off}.*"]
  puts [format "NETCHECK %-13s nets=%-5d %-17s nets=%-5d e.g. %s" $on [llength $n1] $off [llength $n0] [lindex $n1 0]]
}
puts "NETCHECK done"
