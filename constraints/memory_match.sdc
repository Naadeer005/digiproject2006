create_clock -name clk50 -period 20.000 [get_ports {MAX10_CLK1_50}]
derive_clock_uncertainty
# Board switches/buttons are asynchronous. Only their first synchronizer
# stage (and asynchronous reset assertion) is exempted; internal paths remain timed.
set_false_path -from [get_ports {KEY[*] SW[*]}]
# VGA feeds an analog resistor DAC rather than a receiving clocked device.
# Budget 10 ns from the 50 MHz edge for board output settling.
set_output_delay -clock clk50 -max 10.000 [get_ports {VGA_R[*] VGA_G[*] VGA_B[*] VGA_HS VGA_VS}]
set_output_delay -clock clk50 -min 0.000 [get_ports {VGA_R[*] VGA_G[*] VGA_B[*] VGA_HS VGA_VS}]
