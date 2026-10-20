# muserisc_soc_top @ 40 MHz on sky130hd (estimate run; fmax is read
# from the reported slack). I/O delays are budget placeholders, as
# in the nangate45 SDC.
create_clock [get_ports clk_i] -period 25.0 -name core_clock
set_clock_uncertainty -setup 0.5 [get_clocks core_clock]
set_clock_uncertainty -hold 0.1 [get_clocks core_clock]
set_input_delay  5.0 -clock core_clock [all_inputs]
set_output_delay 5.0 -clock core_clock [all_outputs]
# boot_pc_i is a static strap: the core reads it combinationally
# from reset until the first PC update after reset release, so it
# must be stable from before reset release through that cycle
# (there is no reset synchronizer in muserisc_soc_top yet).
set_false_path -from [get_ports boot_pc_i]
