# Verified against Quartus 25.1std bundled DE10_LITE_Golden_Top/platform_setup.tcl.
# Production board device is 10M50DAF484C7G; the old template names an ES device.
set_location_assignment PIN_P11 -to MAX10_CLK1_50
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to MAX10_CLK1_50
foreach {port pin} {
  KEY[0] B8 KEY[1] A7
} {
  set_location_assignment PIN_$pin -to $port
  set_instance_assignment -name IO_STANDARD "3.3 V SCHMITT TRIGGER" -to $port
}
foreach {port pin} {
  SW[0] C10 SW[1] C11 SW[2] D12 SW[3] C12 SW[4] A12
  SW[5] B12 SW[6] A13 SW[7] A14 SW[8] B14 SW[9] F15
  VGA_R[0] AA1 VGA_R[1] V1 VGA_R[2] Y2 VGA_R[3] Y1
  VGA_G[0] W1 VGA_G[1] T2 VGA_G[2] R2 VGA_G[3] R1
  VGA_B[0] P1 VGA_B[1] T1 VGA_B[2] P4 VGA_B[3] N2
  VGA_HS N3 VGA_VS N1
} {
  set_location_assignment PIN_$pin -to $port
  set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to $port
}
foreach port {VGA_R[*] VGA_G[*] VGA_B[*] VGA_HS VGA_VS} {
  set_instance_assignment -name CURRENT_STRENGTH_NEW "8MA" -to $port
}
