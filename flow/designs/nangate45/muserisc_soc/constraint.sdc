# muserisc_soc_top @ 100 MHz (nangate45, issue #11 slice).
# External RAM ports are block-level async-SRAM interfaces;
# I/O delays are budget placeholders until a pad/SRAM-macro
# chip top exists.
create_clock [get_ports clk_i] -period 10.0 -name core_clock
set_clock_uncertainty -setup 0.5 [get_clocks core_clock]
set_clock_uncertainty -hold 0.05 [get_clocks core_clock]
set_input_delay  2.0 -clock core_clock [all_inputs]
set_output_delay 2.0 -clock core_clock [all_outputs]
# boot_pc_i is a static strap: the core reads it combinationally
# from reset until the first PC update after reset release, so it
# must be stable from before reset release through that cycle
# (there is no reset synchronizer in muserisc_soc_top yet).
set_false_path -from [get_ports boot_pc_i]
# Same repair guardband as muse_crypto (not signoff; liberty
# limits via scripts/orfs_liberty_check.sh remain the gate).
set_max_capacitance 21 [current_design]
