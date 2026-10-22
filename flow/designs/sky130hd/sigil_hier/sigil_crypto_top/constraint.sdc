# sigil_crypto_top hard block @ 25 MHz (SoC clock; see
# ../sigil_cpu/constraint.sdc for the boundary budget).
create_clock [get_ports clk] -period 40.0 -name core_clock
set_clock_uncertainty -setup 0.5 [get_clocks core_clock]
set_clock_uncertainty -hold 0.1 [get_clocks core_clock]
set_input_delay  12.0 -clock core_clock [delete_from_list [all_inputs] [get_ports clk]]
set_output_delay 12.0 -clock core_clock [all_outputs]
