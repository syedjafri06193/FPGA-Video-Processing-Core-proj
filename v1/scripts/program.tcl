# Program the board over the single USB cable.
#
#   vivado -mode batch -source scripts/program.tcl
#
# Equivalent to Hardware Manager -> Open Target -> Auto Connect -> Program.
# If this fails on Linux with a permissions error, the cable drivers are not
# installed:
#   <vivado>/data/xicom/cable_drivers/lin64/install_script/install_drivers/install_drivers

set bitfile ./build/video_core.bit

if {![file exists $bitfile]} {
    puts "ERROR: $bitfile not found -- run scripts/build.tcl first"
    exit 1
}

open_hw_manager
connect_hw_server
open_hw_target

set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev

set_property PROGRAM.FILE $bitfile $dev
program_hw_devices $dev
refresh_hw_device $dev

puts "programmed $bitfile"
puts ""
puts "If the monitor stays dark, work down the list in docs/bringup.md --"
puts "start with led\[0\] (MMCM locked) and the measured pixel clock on the"
puts "seven-segment display (hold btn\[1\])."

close_hw_manager
