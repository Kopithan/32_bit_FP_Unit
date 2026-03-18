create_clock -name {clk_50} -period 20.000 [get_ports {CLOCK_50}]
derive_clock_uncertainty

# Ignore timing on ISSP virtual pins
set_false_path -from [get_ports {source}]
set_false_path -to   [get_ports {probe}]
set_false_path -from [get_ports {RESET_N}]