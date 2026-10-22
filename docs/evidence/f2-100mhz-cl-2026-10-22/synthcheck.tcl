# Read-only check of the CL post-synth DCP: are the FPGA_TIMING and
# VRF_OREG structures in the netlist?
set_param general.maxThreads 2
open_checkpoint [lindex $argv 0]
foreach pat {*g_ireg.* *g_dreg.* *g_oreg.* *g_mc_req.* *g_port_sel.* *g_dl.* *g_vls_end.* *g_pmp_par.* *g_wr_attempt.* *g_ireg_off.* *g_dreg_off.* *g_noreg.*} {
  set c [get_cells -quiet -hier -filter "NAME =~ $pat && IS_PRIMITIVE"]
  puts "SYNTHCHECK $pat primitives=[llength $c] e.g. [lindex $c 0]"
}
set r [get_cells -quiet -hier -filter {NAME =~ *mt_q_reg* && IS_SEQUENTIAL}]
puts "SYNTHCHECK mt_q regs=[llength $r] e.g. [lindex $r 0]"
set r [get_cells -quiet -hier -filter {NAME =~ *it_q_reg* && IS_SEQUENTIAL}]
puts "SYNTHCHECK it_q regs=[llength $r]"
set r [get_cells -quiet -hier -filter {NAME =~ *out_q_reg* && IS_SEQUENTIAL && NAME =~ *vregfile*}]
puts "SYNTHCHECK vrf out_q regs=[llength $r] e.g. [lindex $r 0]"
