create_clock -name clk -period 20.000 [get_ports {clk}]
create_generated_clock -name dram_clk -source [get_ports {clk}] [get_ports {DRAM_CLK}]
derive_clock_uncertainty
