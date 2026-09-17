## =====================================================================
##  Boolean Board (Spartan-7 XC7S50-CSGA324-1) constraints
##
##  !!  PIN NUMBERS MARKED <PIN> ARE PLACEHOLDERS.  FILL THEM IN FROM
##  !!  REAL DIGITAL'S MASTER XDC BEFORE BUILDING.
##
##  This is deliberate.  The design document is emphatic about it and it is
##  right: a wrong pin assignment on a differential TMDS pair at best does
##  nothing, and at worst drives a signal into the monitor's output.  Guessing
##  pin numbers from a forum post is not a risk worth taking with hardware, so
##  this file ships with the placeholders visible and scripts/build.tcl refuses
##  to build until they are gone.
##
##  Get the master XDC from realdigital.org (Boolean Board -> Documentation).
##  It arrives fully commented out; uncomment the lines you need and rename the
##  ports to match top.v exactly -- the names below are what the RTL uses, and
##  a mismatch is silently ignored by the tools, which is the single most
##  common M0 failure.
##
##  The one pin confirmed from Real Digital's own reference manual is the
##  100 MHz oscillator, which is on a multi-region clock-capable pin:
##      https://www.realdigital.org/doc/02013cd17602c8af749f00561f88ae21
##  Verify even that against your own board revision.
## =====================================================================

## ---------------------------------------------------------------- clock
set_property -dict { PACKAGE_PIN F14  IOSTANDARD LVCMOS33 } [get_ports clk_100mhz]
create_clock -period 10.000 -name sys_clk -waveform {0.000 5.000} [get_ports clk_100mhz]

## ------------------------------------------------------- HDMI / TMDS out
## TMDS_33 is a true differential standard: declare both halves of each pair
## and let the OBUFDS in serializer_10to1.v drive them.  Nothing may sit
## between the OSERDESE2 and the OBUFDS, and Vivado places that automatically.
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD TMDS_33 } [get_ports tmds_clk_p]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD TMDS_33 } [get_ports tmds_clk_n]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD TMDS_33 } [get_ports {tmds_d_p[0]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD TMDS_33 } [get_ports {tmds_d_n[0]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD TMDS_33 } [get_ports {tmds_d_p[1]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD TMDS_33 } [get_ports {tmds_d_n[1]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD TMDS_33 } [get_ports {tmds_d_p[2]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD TMDS_33 } [get_ports {tmds_d_n[2]}]

## Channel map, for when the picture comes up with the wrong colours:
##   tmds_d[0] = Blue  + ctrl {vsync, hsync}    <- swapped blue means no sync
##   tmds_d[1] = Green
##   tmds_d[2] = Red                            <- R/B swap is the classic

## ------------------------------------------------------------- switches
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {sw[0]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {sw[1]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {sw[2]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {sw[3]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {sw[4]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {sw[5]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {sw[6]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {sw[7]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {sw[8]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {sw[9]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {sw[10]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {sw[11]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {sw[12]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {sw[13]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {sw[14]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {sw[15]}]

## Switch map (ctrl_regs.v):
##   sw[1:0]  mode  0=pass 1=lut 2=edges 3=overlay
##   sw[2]    LUT bypass          sw[3]    glow overlay
##   sw[6:4]  pattern select      sw[7]    freeze animation
##   sw[15:8] edge threshold

## -------------------------------------------------------------- buttons
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {btn[0]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {btn[1]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {btn[2]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {btn[3]}]

## btn[0] forces the threshold to 0x40; btn[1] swaps the display between the
## frame counter and the measured pixel clock.

## ----------------------------------------------------------------- LEDs
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {led[3]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {led[4]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {led[5]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {led[6]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {led[7]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {led[8]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {led[9]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {led[10]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {led[11]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {led[12]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {led[13]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {led[14]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {led[15]}]

## led[0] is the MMCM lock, which is question one in the bring-up playbook.

## ------------------------------------------------- seven-segment display
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {seg[0]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {seg[1]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {seg[2]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {seg[3]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {seg[4]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {seg[5]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {seg[6]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {seg[7]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {an[0]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {an[1]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {an[2]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {an[3]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {an[4]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {an[5]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {an[6]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports {an[7]}]

## ----------------------------------------------------------------- UART
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD LVCMOS33 } [get_ports uart_rxd]

## ------------------------------------------------------ timing exceptions
## The two video clocks come from one MMCM and are phase related, so Vivado
## analyses paths between them.  Check the clock interaction report: if they
## appear as asynchronous, the OSERDES paths are not being analysed at all and
## a "passing" timing report means nothing (section 11).
##
## The reset synchronisers and the freq_counter handshake are the only genuine
## asynchronous crossings in the design.
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *sync_reg*}]
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *gate_meta*}]
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *rx_meta*}]
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *hz_meta*}]

## ------------------------------------------------------------- bitstream
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO     [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
