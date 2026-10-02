onerror {quit -code 1}
set BreakOnAssertion 2
onbreak {quit -code 1}
log -r /*
run -all
# Passing benches call std.env.finish; reaching this line is not a pass.
quit -code 1
