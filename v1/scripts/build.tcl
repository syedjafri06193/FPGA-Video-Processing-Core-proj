# Scripted build (design.md section 6.5).
#
#   vivado -mode batch -source scripts/build.tcl
#   vivado -mode batch -source scripts/build.tcl -tclargs 720p teal_orange
#
# Vivado's GUI project files are XML blobs that do not diff, so the repository
# holds only source and this script builds from it.
#
# Two things here are non-negotiable:
#
#   * the build fails if the XDC still has <PIN> placeholders, because a
#     bitstream built against guessed pins can drive a signal into a monitor's
#     output;
#   * the build fails on negative slack.  A design that misses timing may well
#     put a picture on the screen and then sparkle, or work on your bench and
#     not on someone else's, and shipping that is worse than not shipping.

set mode  [expr {$argc > 0 ? [lindex $argv 0] : "720p"}]
set grade [expr {$argc > 1 ? [lindex $argv 1] : "teal_orange"}]

set proj_name video_core
set part      xc7s50csga324-1
set outdir    ./build
set lutdir    ./sim/vectors/lut

switch -- $mode {
    480p  { set mode_id 0 }
    720p  { set mode_id 1 }
    1080p { set mode_id 2 }
    default {
        puts "ERROR: unknown mode '$mode' (expected 480p, 720p or 1080p)"
        exit 1
    }
}

file mkdir $outdir

# ---- guard: the constraints must name real pins -------------------------
set xdc constraints/boolean.xdc
set fh [open $xdc r]
set xdc_text [read $fh]
close $fh
if {[string first "<PIN>" $xdc_text] >= 0} {
    puts "ERROR: $xdc still contains <PIN> placeholders."
    puts "       Fill them in from Real Digital's master XDC before building."
    puts "       Guessed pin assignments on a TMDS pair can damage hardware."
    exit 1
}

# ---- guard: the LUT banks must exist ------------------------------------
for {set i 0} {$i < 8} {incr i} {
    set f "$lutdir/${grade}_bank${i}.mem"
    if {![file exists $f]} {
        puts "ERROR: missing $f"
        puts "       Run: python3 model/make_lut.py"
        exit 1
    }
}

puts "building $proj_name: mode=$mode (MODE=$mode_id) grade=$grade part=$part"

create_project -in_memory -part $part

read_verilog [glob ./rtl/*.v]
read_xdc $xdc

# The .mem files are read by $readmemh at elaboration, so they have to be
# visible to synthesis as well as to simulation.
add_files -fileset [current_fileset] [glob $lutdir/${grade}_bank*.mem]

synth_design -top top -part $part \
    -generic MODE=$mode_id \
    -generic LUT0=$lutdir/${grade}_bank0.mem \
    -generic LUT1=$lutdir/${grade}_bank1.mem \
    -generic LUT2=$lutdir/${grade}_bank2.mem \
    -generic LUT3=$lutdir/${grade}_bank3.mem \
    -generic LUT4=$lutdir/${grade}_bank4.mem \
    -generic LUT5=$lutdir/${grade}_bank5.mem \
    -generic LUT6=$lutdir/${grade}_bank6.mem \
    -generic LUT7=$lutdir/${grade}_bank7.mem

opt_design
place_design
phys_opt_design
route_design

report_timing_summary -file $outdir/timing.rpt
report_utilization    -file $outdir/util.rpt
report_clock_utilization -file $outdir/clocks.rpt
report_drc            -file $outdir/drc.rpt

# ---- gate: timing ---------------------------------------------------------
set wns [get_property SLACK [get_timing_paths -delay_type max]]
set whs [get_property SLACK [get_timing_paths -delay_type min]]
puts [format "WNS %.3f ns   WHS %.3f ns" $wns $whs]

if {$wns < 0 || $whs < 0} {
    puts "ERROR: timing not met (WNS $wns, WHS $whs)."
    puts "       See $outdir/timing.rpt.  The usual suspect at 74.25 MHz is the"
    puts "       TMDS encoder's disparity feedback loop -- section 11 has the fix."
    exit 1
}

write_bitstream -force $outdir/$proj_name.bit
puts "wrote $outdir/$proj_name.bit"
