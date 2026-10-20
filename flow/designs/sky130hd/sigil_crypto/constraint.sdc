# sigil_crypto @ 50 MHz (sky130hd, conservative first target).
create_clock [get_ports clk] -period 20.0 -name core_clock
set_clock_uncertainty -setup 1.0 [get_clocks core_clock]
set_clock_uncertainty -hold 0.1 [get_clocks core_clock]
set_input_delay  4.0 -clock core_clock [all_inputs]
set_output_delay 4.0 -clock core_clock [all_outputs]
