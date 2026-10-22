# CDC / bus-skew / clock-interaction check of the public AFI's routed DCP
# (#73 AXI lens): are the core<->clk_main_a0 crossings (DDR_CDC, OCL_CDC)
# constrained and met?
open_checkpoint /home/ubuntu/plat-b3a/fpga/cl_sigil/build/checkpoints/cl_sigil.2026_10_22-070909.post_route.dcp
set out /home/ubuntu/oops/axi/vivado
file mkdir $out
report_clock_interaction -delay_type min_max -significant_digits 3 -file $out/clock_interaction.rpt
report_bus_skew -max_paths 50 -file $out/bus_skew.rpt
report_cdc -details -file $out/cdc_details.rpt
report_cdc -file $out/cdc_summary.rpt
report_timing_summary -max_paths 5 -file $out/timing_summary.rpt
report_exceptions -ignored -file $out/exceptions_ignored.rpt
report_methodology -file $out/methodology.rpt
puts "CDC CHECK DONE"
