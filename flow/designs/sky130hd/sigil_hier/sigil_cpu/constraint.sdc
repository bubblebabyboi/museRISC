# sigil_cpu hard block @ 25 MHz (same clock as the flat sky130hd
# sigil_soc_top run). Boundary budget: each block input arrives
# 12 ns after the clock edge and each output must be valid 12 ns
# before the next one, leaving >= 16 ns for the top-level path
# between a block pin and the fabric registers / pins. The block
# timing model (write_timing_model) carries the real pin-to-register
# delays into the top-level STA, so the top timing is checked with
# the block's routed timing, not with this budget.
create_clock [get_ports clk_i] -period 40.0 -name core_clock
set_clock_uncertainty -setup 0.5 [get_clocks core_clock]
set_clock_uncertainty -hold 0.1 [get_clocks core_clock]
set_input_delay  12.0 -clock core_clock [delete_from_list [all_inputs] [get_ports clk_i]]
set_output_delay 12.0 -clock core_clock [all_outputs]
# boot_pc_i is a static strap (see ../../sigil_soc/constraint.sdc).
set_false_path -from [get_ports boot_pc_i]
