# sigil_soc_top @ 40 MHz on sky130hd (estimate run; fmax is read
# from the reported slack). I/O delays are budget placeholders, as
# in the nangate45 SDC.
create_clock [get_ports clk_i] -period 25.0 -name core_clock
set_clock_uncertainty -setup 0.5 [get_clocks core_clock]
set_clock_uncertainty -hold 0.1 [get_clocks core_clock]
set_input_delay  5.0 -clock core_clock [all_inputs]
set_output_delay 5.0 -clock core_clock [all_outputs]
# boot_pc_i is a static strap: the core reads it combinationally
# from reset until the first PC update after the (synchronized)
# reset release, so it must be stable from before rst_ni rises
# through that cycle.
set_false_path -from [get_ports boot_pc_i]
# rst_ni only reaches the two-flop reset synchronizer in
# sigil_soc_top (asynchronous assert, synchronous release); every
# other async-reset flop is driven from the synchronizer output and
# is timed (recovery/removal) against core_clock.
set_false_path -from [get_ports rst_ni]
