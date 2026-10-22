# Bus-skew check on the routed CL (the timing summary does not cover
# set_bus_skew constraints of the clock-converter CDC IP).
set_param general.maxThreads 4
open_checkpoint [lindex $argv 0]
report_bus_skew -warn_on_violation -file [lindex $argv 1]
puts "BUSSKEW done"
