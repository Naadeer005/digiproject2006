project_open memory_match
create_timing_netlist
read_sdc
update_timing_netlist
report_timing -setup -npaths 10 -detail full_path -file build/critical_paths.txt
report_ucp -file build/unconstrained_paths.txt
delete_timing_netlist
project_close
