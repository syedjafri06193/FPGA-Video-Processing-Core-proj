# FPGA Video Processing Core — Design & Build Guide

**Target board:** Real Digital Boolean Board (Spartan-7 XC7S50-1CSGA324)
**Scope:** Real-time HDMI video pipeline implementing 3×3 Sobel edge detection and 3D-LUT color grading
**Status of this document:** planning + reference. Written for someone starting from zero FPGA experience.

---

## Table of contents

1. [Executive summary and revised scope](#1-executive-summary-and-revised-scope)
2. [Hardware reality check](#2-hardware-reality-check)
3. [System architecture](#3-system-architecture)
4. [Clocking plan](#4-clocking-plan)
5. [Resource budget](#5-resource-budget)
6. [Environment setup](#6-environment-setup)
7. [Repository layout](#7-repository-layout)
8. [Milestone ladder](#8-milestone-ladder)
9. [Module designs and reference RTL](#9-module-designs-and-reference-rtl)
10. [Verification strategy](#10-verification-strategy)
11. [Timing closure notes](#11-timing-closure-notes)
12. [Debugging playbook](#12-debugging-playbook)
13. [Stretch goals](#13-stretch-goals)
14. [References](#14-references)

---

## 1. Executive summary and revised scope

### What changed from the original pitch

The original project statement was:

> Real-time HDMI video pipeline on Spartan-7 implementing edge detection and LUT-based color grading at 1080p60.

Two findings force a revision:

**The Boolean Board has no HDMI input.** Real Digital's specification lists the board's video interface as an HDMI *source* (output only), up to 1080p. There is no sink, no TMDS receiver front end, and no way to add one through the Pmod headers at usable bandwidth. "HDMI in → process → HDMI out" is not buildable on this hardware.

**1080p60 is not achievable on a -1 speed grade 7-series part.** This is not a marginal overclock; it fails on the clock tree, not just the SERDES. See section 2.

### Revised project statement

> Real-time video processing pipeline on Spartan-7 driving a DVI/HDMI display at 720p60, implementing 3×3 Sobel edge detection and 3D-LUT color grading on a procedurally generated video source, with runtime-selectable processing modes.

This is an honest, defensible, and genuinely interesting project. It keeps every algorithmically interesting part of the original. The things it drops (HDMI receive, 1080p60) were the two parts that were not physically possible on this board anyway.

If you want a "1080p" line on the résumé, note that **1080p30 uses exactly the same 74.25 MHz pixel clock as 720p60** — identical clocking infrastructure, identical everything except the timing constants. You can support both from the same bitstream with a mode switch. That is a legitimate 1080p claim.

### What you keep

- A full DVI/HDMI transmitter written from scratch: video timing generation, TMDS 8b/10b encoding, DC balancing, 10:1 serialization via `OSERDESE2`.
- A 3×3 convolution engine with BRAM line buffers and proper border handling.
- A 17³ 3D LUT with trilinear interpolation, including the 8-bank BRAM trick that makes it single-cycle.
- Real timing closure work at 74.25 MHz across two clock domains.
- A simulation flow with a Python golden model and PNG in/out.

That is a substantial portfolio project. Nobody looking at it will care that the pixels came from a pattern generator instead of a laptop.

---

## 2. Hardware reality check

### 2.1 Boolean Board specification

| Item | Value |
|---|---|
| FPGA | Xilinx Spartan-7 XC7S50, package CSGA324, **speed grade -1** |
| Logic cells | 52,160 |
| Slices | 8,150 |
| CLB flip-flops | 65,200 |
| 6-input LUTs | ~32,600 |
| Block RAM | 2,700 Kbit = **75 × BRAM36** (or 150 × BRAM18) |
| DSP48E1 slices | 120 |
| Clock management tiles | 5 (MMCM/PLL) |
| External clock | Single 100 MHz oscillator |
| Video | **HDMI source only** (output). No HDMI input. |
| Memory | 16 MB QSPI flash. **No DDR.** |
| I/O | 16 switches, 16 LEDs, 4 buttons, 2 RGB LEDs, 8-digit 7-segment, 4 Pmod ports, servo headers, XADC potentiometer, BLE radio, PWM audio |
| Power/program | Single USB port (also USB-UART) |

Two consequences worth internalizing early:

- **No DDR memory.** This sounds limiting but is actually fine, because neither Sobel nor a 3D LUT needs a frame buffer. Sobel needs 3 lines; a LUT needs zero. The entire pipeline is *streaming*: pixels enter, pixels leave, nothing is stored longer than 3 scanlines. You never need a memory controller, an AXI interconnect, or a VDMA. This is what makes the project tractable for a beginner.
- **Only 2.7 Mbit of BRAM.** A single 1280×720 24-bit frame is 27.6 Mbit. You cannot store a frame on-chip. This constrains how you generate source video (section 9.5).

### 2.2 Why 1080p60 is impossible on this part

DVI/HDMI transmits 10 bits per pixel per channel (8 data bits expanded to 10 by TMDS encoding). So:

| Mode | Pixel clock | Serial rate / channel | Required 5× clock |
|---|---|---|---|
| 640×480p60 | 25.175 MHz | 251.75 Mb/s | 125.9 MHz |
| 1280×720p60 | 74.25 MHz | 742.5 Mb/s | 371.25 MHz |
| 1920×1080p30 | 74.25 MHz | 742.5 Mb/s | 371.25 MHz |
| **1920×1080p60** | **148.5 MHz** | **1485 Mb/s** | **742.5 MHz** |

Now the 7-series -1 speed grade limits:

| Resource | -1 limit | -2 limit |
|---|---|---|
| `OSERDESE2` DDR output rate | 950 Mb/s | 1250 Mb/s |
| `BUFG` (global clock buffer) | 464 MHz | 628 MHz |
| `BUFIO` (I/O clock buffer) | 600 MHz | 680 MHz |
| `BUFR` (regional clock buffer) | 315 MHz | 375 MHz |

For 1080p60 you need a 742.5 MHz clock distributed to the `OSERDESE2` primitives. That exceeds `BUFG` (464 MHz) by 60% and exceeds even `BUFIO` (600 MHz), which is the fastest clock buffer available. **There is no clock resource on the device that can carry 742.5 MHz.** The 1485 Mb/s data rate separately exceeds the OSERDES limit by 56%.

You will find forum threads and vendor IP (Digilent's `rgb2dvi`, for example) claiming 1080p60 support on -1 Artix-7 parts, and people reporting it works on their bench. It is an out-of-spec overclock on at least two independent axes. It may work at room temperature on one board and fail at 70 °C on another. Do not build a project whose headline claim depends on it.

For 720p60 / 1080p30, the 5× clock is 371.25 MHz — comfortably under the 464 MHz `BUFG` limit, and the 742.5 Mb/s serial rate is under the 950 Mb/s OSERDES limit. Everything is in spec with real margin.

**Decision: target 720p60. Support 640×480p60 and 1080p30 as additional modes.**

### 2.3 If you later want real HDMI input

Not on this board. Options, in rough order of sanity:

| Option | Cost | Notes |
|---|---|---|
| **Add a camera instead** | $10–30 | OV7670, OV5640, or a Pmod camera. Real live video, a fraction of the bandwidth, connectors that can actually carry it. Your Sobel and LUT cores don't care where pixels come from. Best value by far. |
| **Digilent Zybo Z7 / Arty Z7** | ~$250–300 | HDMI in *and* out. Zynq, so you inherit an ARM processing system and a much larger learning curve. |
| **Digilent Nexys Video** | ~$500 | HDMI in and out, DDR3, Artix-7. Closest thing to a purpose-built board for the original project. |
| **HDMI receiver over Pmod** | — | Don't. TMDS at 720p is 742 Mb/s per differential pair. 0.1" headers with no controlled impedance will not carry that reliably, and debugging the result would be miserable. |

---

## 3. System architecture

### 3.1 Block diagram

```
 ┌──────────────────────────────────────────────────────────────────────┐
 │                          clk_pix domain (74.25 MHz)                  │
 │                                                                      │
 │  ┌────────────┐    ┌────────────┐                                    │
 │  │  video     │───▶│  pattern / │                                    │
 │  │  timing    │ de │  image     │─── rgb ──┬──────────────────┐      │
 │  │  generator │ hs │  source    │          │                  │      │
 │  └────────────┘ vs └────────────┘          ▼                  ▼      │
 │        │  │                        ┌──────────────┐   ┌─────────────┐│
 │        │  │                        │ line buffer  │   │  delay      ││
 │        │  │                        │  (2 × BRAM)  │   │  match      ││
 │        │  │                        └──────┬───────┘   │  FIFO/SR    ││
 │        │  │                               │           └──────┬──────┘│
 │        │  │                               ▼                  │       │
 │        │  │                        ┌──────────────┐          │       │
 │        │  │                        │  3×3 window  │          │       │
 │        │  │                        │  + luma      │          │       │
 │        │  │                        └──────┬───────┘          │       │
 │        │  │                               ▼                  ▼       │
 │        │  │                        ┌──────────────┐   ┌─────────────┐│
 │        │  │                        │   Sobel      │   │  3D LUT     ││
 │        │  │                        │   |Gx|+|Gy|  │   │  17³ tri-   ││
 │        │  │                        │   threshold  │   │  linear     ││
 │        │  │                        └──────┬───────┘   └──────┬──────┘│
 │        │  │                          edge │              rgb │       │
 │        │  │                               └────────┬─────────┘       │
 │        │  │                                        ▼                 │
 │        │  │                                 ┌─────────────┐          │
 │        │  │                                 │   blend /   │          │
 │        │  │  (de/hs/vs delayed to match) ──▶│   mode mux  │          │
 │        │  │                                 └──────┬──────┘          │
 │        ▼  ▼                                        ▼                 │
 │  ┌──────────────────────────────────────────────────────────┐        │
 │  │  TMDS encoders  ×3   (blue+ctrl, green, red)             │        │
 │  └────────────────────────┬─────────────────────────────────┘        │
 └───────────────────────────┼──────────────────────────────────────────┘
                             │  3 × 10 bit
 ┌───────────────────────────┼──────────────────────────────────────────┐
 │                clk_5x domain (371.25 MHz)                            │
 │  ┌────────────────────────▼─────────────────────────────────┐        │
 │  │  OSERDESE2 10:1 serializers ×4  (D0,D1,D2 + clock)       │        │
 │  └────────────────────────┬─────────────────────────────────┘        │
 └───────────────────────────┼──────────────────────────────────────────┘
                             ▼
                     OBUFDS ×4 → HDMI connector → monitor

 ┌─────────────────────────────────────────────────────────────┐
 │  control: switches / buttons / UART → mode, threshold, LUT   │
 └─────────────────────────────────────────────────────────────┘
```

### 3.2 Key architectural decisions

**Sobel and the LUT are parallel branches, not a chain.** Edge detection runs on luma derived from the *ungraded* image, because color grading can crush the local contrast the gradient operator depends on. The RGB pixel takes a delay-matched path through the LUT. Both branches rejoin at the blend stage. Getting the delay matching right is one of the fiddlier parts of the design — see section 9.7.

**Everything is registered at module boundaries.** No combinational logic crosses a module interface. This costs you a few cycles of latency (irrelevant — a frame is 1,237,500 cycles) and buys you timing closure at 74.25 MHz almost for free.

**The `de` / `hsync` / `vsync` signals travel alongside the pixels through every stage.** They must be delayed by exactly the same number of cycles as the pixel data or the image will be shifted, sheared, or blank. Build a small `delay_line` module parameterized on width and depth and use it everywhere. Do not hand-count registers.

**Two clock domains only.** `clk_pix` (74.25 MHz) and `clk_5x` (371.25 MHz), both from one MMCM, phase-aligned. The only crossing is inside `OSERDESE2`, which handles it internally via its `CLK`/`CLKDIV` ports. You never write a CDC synchronizer for the video path. (Control registers from a slow UART domain are a separate, much easier crossing.)

### 3.3 Pixel data contract

Every module in the video path uses the same interface:

```verilog
input  wire        clk,
input  wire        rst,
input  wire [23:0] px_in,     // {R[7:0], G[7:0], B[7:0]}
input  wire        de_in,     // data enable: 1 during active video
input  wire        hs_in,
input  wire        vs_in,
output reg  [23:0] px_out,
output reg         de_out,
output reg         hs_out,
output reg         vs_out
```

No handshaking, no backpressure, no valid/ready. The pipeline runs free at the pixel rate and never stalls. This is a huge simplification and it is only possible because there is no memory controller in the path.

---

## 4. Clocking plan

The board has a single 100 MHz oscillator. One MMCM generates both video clocks.

### 4.1 MMCM settings

**For 720p60 and 1080p30** (pixel = 74.25 MHz, serial = 371.25 MHz):

| Parameter | Value |
|---|---|
| `CLKIN1_PERIOD` | 10.000 (100 MHz) |
| `DIVCLK_DIVIDE` (D) | 5 |
| `CLKFBOUT_MULT_F` (M) | 37.125 |
| PFD frequency | 100 / 5 = 20 MHz ✓ (must be 10–450 MHz) |
| VCO frequency | 100 × 37.125 / 5 = **742.5 MHz** ✓ (must be 600–1200 MHz for -1) |
| `CLKOUT0_DIVIDE_F` | 2 → **371.25 MHz** (`clk_5x`) |
| `CLKOUT1_DIVIDE` | 10 → **74.25 MHz** (`clk_pix`) |

That 742.5 MHz VCO is internal to the MMCM and perfectly legal — VCOs run far faster than clock buffers. What you must never do is route 742.5 MHz onto a `BUFG`.

**For 640×480p60** (pixel = 25 MHz, serial = 125 MHz). Note: the exact standard is 25.175 MHz; 25.000 MHz is within tolerance and every monitor accepts it.

| Parameter | Value |
|---|---|
| `DIVCLK_DIVIDE` | 1 |
| `CLKFBOUT_MULT_F` | 10.000 |
| VCO | 1000 MHz ✓ |
| `CLKOUT0_DIVIDE_F` | 8 → 125 MHz (`clk_5x`) |
| `CLKOUT1_DIVIDE` | 40 → 25 MHz (`clk_pix`) |

### 4.2 Instantiation

Use the Clocking Wizard IP rather than instantiating `MMCME2_ADV` by hand. In Vivado: **IP Catalog → FPGA Features and Design → Clocking → Clocking Wizard**. Set input 100 MHz, two outputs, enter the target frequencies, and check the "Actual" column matches exactly. Enable the `locked` output and hold your design in reset until it asserts.

Critical: `clk_pix` and `clk_5x` must come from the **same MMCM** so they are phase-related. Two separate MMCMs will drift and the OSERDES output will be garbage.

If you want runtime resolution switching later, the Clocking Wizard has a Dynamic Reconfiguration (DRP) option. Skip it for now — build one resolution at a time.

### 4.3 Video timing constants

These are CEA-861 / VESA standard. Getting a single number wrong here produces a monitor that says "no signal" with no further clue, so copy carefully.

| | 640×480p60 | 1280×720p60 | 1920×1080p30 |
|---|---|---|---|
| Pixel clock | 25.175 MHz | 74.25 MHz | 74.25 MHz |
| H active | 640 | 1280 | 1920 |
| H front porch | 16 | 110 | 88 |
| H sync width | 96 | 40 | 44 |
| H back porch | 48 | 220 | 148 |
| **H total** | **800** | **1650** | **2200** |
| V active | 480 | 720 | 1080 |
| V front porch | 10 | 5 | 4 |
| V sync width | 2 | 5 | 5 |
| V back porch | 33 | 20 | 36 |
| **V total** | **525** | **750** | **1125** |
| HSync polarity | negative | positive | positive |
| VSync polarity | negative | positive | positive |

Sanity check: 1650 × 750 × 60 = 74,250,000 ✓ and 2200 × 1125 × 30 = 74,250,000 ✓

---

## 5. Resource budget

Estimates for 720p60 on XC7S50 (75 BRAM36, 120 DSP, ~32,600 LUTs).

| Block | BRAM36 | DSP | LUTs (approx) | Notes |
|---|---|---|---|---|
| MMCM + reset | 0 | 0 | ~50 | |
| Video timing generator | 0 | 0 | ~150 | Two counters and comparators |
| Pattern generator | 0 | 0 | ~400 | Procedural; see 9.5 |
| Stored test image (optional) | 8 | 0 | ~100 | 256×144, 8-bit palette |
| Line buffers (2 lines × 24 bit) | 2 | 0 | ~100 | 1280×24 = 30.7 kbit per line |
| 3×3 window shift registers | 0 | 0 | ~250 | |
| Luma conversion | 0 | 3 | ~50 | Or 0 DSP with shift-add |
| Sobel Gx/Gy + magnitude | 0 | 0 | ~400 | All coefficients are ±1, ±2 → shifts and adds |
| 3D LUT storage (8 banks) | 4 | 0 | ~200 | 8 × BRAM18, 729 entries each |
| Trilinear interpolation | 0 | 21 | ~600 | 7-lerp tree × 3 channels |
| Delay matching | 1 | 0 | ~150 | |
| Blend / mode mux | 0 | 3 | ~200 | |
| TMDS encoders ×3 | 0 | 0 | ~450 | ~150 each |
| OSERDES ×4 (×2 primitives) | 0 | 0 | 0 | Hard primitives |
| UART + control registers | 0 | 0 | ~500 | |
| 7-segment + LED status | 0 | 0 | ~250 | |
| **Total** | **~15** | **~27** | **~3,800** | |
| **Available** | 75 | 120 | ~32,600 | |
| **Utilization** | **20%** | **22%** | **12%** | |

You have enormous headroom. Do not optimize for area; optimize for timing closure and debuggability.

At 1080p30 the line buffers grow from 2 to 4 BRAM36 (1920×24 = 46 kbit per line). Everything else is unchanged.

### Why the 3D LUT is only 4 BRAM36

A 17³ LUT is 4,913 nodes. Stored as 24-bit RGB, that is 117,912 bits ≈ 3.2 BRAM36. The complication is that trilinear interpolation needs all 8 corners of the surrounding cube in the *same cycle*, and a BRAM has only 2 ports.

The trick: split the LUT into 8 banks indexed by the parity triple `{r_idx[0], g_idx[0], b_idx[0]}`. Because the 8 corners of a cube are `(r_idx or r_idx+1, g_idx or g_idx+1, b_idx or b_idx+1)`, and adding 1 flips parity, **the 8 corners always land in 8 different banks by construction.** One single-port read from each bank, all in parallel, one cycle. See section 9.6 for the address math.

---

## 6. Environment setup

### 6.1 Install Vivado

- Download **AMD Vivado ML Edition — Standard** from the AMD/Xilinx downloads page. The Standard edition is free and supports all Spartan-7 devices. You do not need a license.
- Version: 2023.2 or newer is fine. Pick one and stay on it; project files are not forward/backward compatible and version churn will waste your time.
- Disk: budget **~60 GB**. During install, deselect every device family except **Spartan-7** (and Artix-7 if you might switch boards). This cuts the install dramatically.
- Time: the download is large and the install is slow. Start it and go do something else.
- Linux users: install the cable drivers afterwards (`<install>/data/xicom/cable_drivers/lin64/install_script/install_drivers/install_drivers`) or programming will fail with a permissions error.
- Windows users: install to a path with **no spaces** (e.g. `C:\Xilinx`). Some backend tools still choke on spaces.

### 6.2 Board files and constraints

Real Digital publishes a master XDC (constraints file) for the Boolean Board on their website. **Get it from them — do not guess pin locations.** A wrong pin assignment on a differential TMDS pair at best does nothing and at worst drives a signal into the monitor's output.

The master XDC is fully commented out. Your job is to uncomment the lines for the pins you use and rename the ports to match your top-level module.

What you will need to uncomment:
- The 100 MHz system clock
- The four HDMI/TMDS differential pairs (`TMDS_D0_P/N`, `TMDS_D1_P/N`, `TMDS_D2_P/N`, `TMDS_CLK_P/N`)
- Slide switches, buttons, LEDs
- UART TX/RX
- 7-segment display (optional but very useful for status)

The TMDS constraints should end up looking like this (**pin names are placeholders — substitute the real ones from Real Digital's XDC**):

```tcl
## System clock
set_property -dict { PACKAGE_PIN <PIN>  IOSTANDARD LVCMOS33 } [get_ports clk_100mhz]
create_clock -period 10.000 -name sys_clk [get_ports clk_100mhz]

## HDMI / TMDS outputs — TMDS_33 standard, differential
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD TMDS_33 } [get_ports tmds_clk_p]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD TMDS_33 } [get_ports tmds_clk_n]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD TMDS_33 } [get_ports {tmds_d_p[0]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD TMDS_33 } [get_ports {tmds_d_n[0]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD TMDS_33 } [get_ports {tmds_d_p[1]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD TMDS_33 } [get_ports {tmds_d_n[1]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD TMDS_33 } [get_ports {tmds_d_p[2]}]
set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD TMDS_33 } [get_ports {tmds_d_n[2]}]

## Bitstream settings
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO     [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
```

Notes on `TMDS_33`: this is a true differential standard, so you declare **both** the `_p` and `_n` ports and instantiate an `OBUFDS`. Vivado will warn if you assign the negative pin of a differential pair manually in some flows — follow whatever the vendor XDC does.

You do not strictly need Vivado "board files" for this project. Board files add a GUI convenience for IP configuration; a plain XDC is enough and is more transparent.

### 6.3 Creating the project

```
File → Project → New
  Project name:  video_core
  Project type:  RTL Project   (uncheck "do not specify sources at this time")
  Add sources:   (skip for now, add later)
  Add constraints: (skip for now)
  Default part:  Parts tab → search "xc7s50csga324-1" → select
```

Confirm the part string reads exactly **`xc7s50csga324-1`**. The trailing `-1` is the speed grade — if you accidentally pick `-2`, Vivado will happily close timing on a design that will not work on your actual board.

### 6.4 Build flow

Every build cycle is:

1. **Write / edit RTL** in `rtl/`
2. **Simulate** — `Flow Navigator → Run Simulation → Run Behavioral Simulation`
3. **Synthesis** — turns RTL into a netlist of primitives. Catches syntax errors, unintended latches, missing signals.
4. **Implementation** — place and route. This is where timing closure happens.
5. **Check timing** — `Reports → Timing → Report Timing Summary`. **Worst Negative Slack (WNS) must be ≥ 0.** If it is negative, your design will not work reliably regardless of what the monitor shows.
6. **Generate Bitstream**
7. **Open Hardware Manager → Open Target → Auto Connect → Program Device**

A full build of this design will take roughly 3–8 minutes. Simulate first, always — an iteration in simulation is seconds, an iteration through the bitstream is minutes plus a walk to the monitor.

### 6.5 Optional but strongly recommended: a Tcl build script

Vivado's GUI project files are XML blobs that do not diff well in git. Once your design stabilizes, move to a scripted build so the repo contains only source:

```tcl
# scripts/build.tcl  —  run with: vivado -mode batch -source scripts/build.tcl
set proj_name  video_core
set part       xc7s50csga324-1
set outdir     ./build

create_project -in_memory -part $part

read_verilog [glob ./rtl/*.v]
read_xdc     ./constraints/boolean.xdc

synth_design -top top -part $part
opt_design
place_design
phys_opt_design
route_design

report_timing_summary -file $outdir/timing.rpt
report_utilization    -file $outdir/util.rpt
write_bitstream -force $outdir/$proj_name.bit
```

Add a line that fails the build loudly if timing is not met, so you can never accidentally ship a bitstream with negative slack:

```tcl
if {[get_property SLACK [get_timing_paths -delay_type min_max]] < 0} {
    puts "ERROR: timing not met"
    exit 1
}
```

### 6.6 Other tools worth installing

| Tool | Why |
|---|---|
| **Git** | Obviously. See section 7 for what to ignore. |
| **Python 3 + numpy + pillow** | Golden reference models and PNG↔hex conversion for testbenches. |
| **GTKWave** | Free waveform viewer. Vivado's built-in one is fine too, but GTKWave is faster for large dumps. |
| **Icarus Verilog** or **Verilator** | Optional. Much faster iteration than Vivado's `xsim` for pure-RTL modules with no vendor primitives. You cannot simulate `OSERDESE2` in them without the Xilinx libraries, so use `xsim` for anything touching primitives. |
| **A second monitor with HDMI input** | You will be power-cycling it a lot. Don't use your only display. |
| **A cheap HDMI cable you don't care about** | |

---

## 7. Repository layout

```
FPGA-Video-Processing-Core/
├── README.md
├── docs/
│   ├── design.md              ← this document
│   ├── timing_tables.md
│   └── images/
├── rtl/
│   ├── top.v                  ← top level, ports match XDC
│   ├── clocking.v             ← MMCM wrapper + reset sync
│   ├── video_timing.v         ← counters, de/hs/vs generation
│   ├── pattern_gen.v          ← procedural source
│   ├── image_rom.v            ← stored test image (optional)
│   ├── line_buffer.v          ← 2-line BRAM delay
│   ├── window_3x3.v           ← taps → 3×3 window
│   ├── rgb2luma.v
│   ├── sobel.v
│   ├── lut3d.v                ← 8-bank storage + trilinear
│   ├── lerp.v                 ← single linear interpolation stage
│   ├── blend.v
│   ├── delay_line.v           ← parameterized W×D shift register
│   ├── tmds_encoder.v
│   ├── serializer_10to1.v     ← OSERDESE2 master/slave pair
│   ├── dvi_tx.v               ← 3 encoders + 4 serializers
│   └── uart_rx.v / ctrl_regs.v
├── sim/
│   ├── tb_tmds_encoder.v
│   ├── tb_video_timing.v
│   ├── tb_sobel.v
│   ├── tb_lut3d.v
│   ├── tb_pipeline.v          ← full image in, full image out
│   └── vectors/
│       ├── input.hex
│       └── expected.hex
├── model/
│   ├── golden.py              ← numpy reference for sobel + LUT
│   ├── png2hex.py
│   ├── hex2png.py
│   └── make_lut.py            ← generate .coe / .mem from a .cube file
├── constraints/
│   └── boolean.xdc
├── scripts/
│   ├── build.tcl
│   └── program.tcl
└── .gitignore
```

`.gitignore` — Vivado generates enormous amounts of garbage:

```
*.jou
*.log
*.str
.Xil/
build/
vivado*/
*.cache/
*.hw/
*.ip_user_files/
*.runs/
*.sim/
*.gen/
```

Commit: RTL, constraints, testbenches, scripts, models, docs. Never commit the `.runs` directory or the project `.xpr`.

---

## 8. Milestone ladder

The ordering matters. Each step de-risks the next, and the goal of the first three is to get *something on a monitor* as fast as possible, because a black screen with no diagnostic is the worst possible place to start debugging from.

Time estimates assume you are genuinely starting from zero and working on this part-time.

---

### M0 — Toolchain smoke test: blink an LED
**Est. 1–2 days (mostly tooling friction)**

Write a counter off the 100 MHz clock, drive an LED from a high bit.

```verilog
module top (input wire clk_100mhz, output wire [15:0] led);
    reg [31:0] cnt = 0;
    always @(posedge clk_100mhz) cnt <= cnt + 1;
    assign led = cnt[31:16];
endmodule
```

**You are learning:** project creation, adding sources, editing the XDC, synthesis, implementation, bitstream generation, hardware manager, programming.

**Done when:** LEDs count visibly. If this takes you two days, that is completely normal and not a reflection on you. Almost all of it is install paths, cable drivers, and constraint syntax.

**Common failures:** missing cable driver; port name in XDC doesn't match the Verilog port name (must match *exactly*, case-sensitive); forgot `CFGBVS`/`CONFIG_VOLTAGE` and get a DRC error.

---

### M1 — Counter on the 7-segment display
**Est. 1 day**

Multiplexed 8-digit display driven by a slow refresh counter.

**You are learning:** clock division, multiplexing, hex-to-segment decoding, and — importantly — you now have an on-board debug output you can print numbers to. You will use this constantly later (e.g. displaying the pixel clock's measured frequency, or a frame counter to prove the pipeline is running).

**Done when:** a hex counter increments on the display.

---

### M2 — Simulate before you synthesize
**Est. 1 day**

Take the M1 design, write a testbench, run it in `xsim`, view waveforms.

```verilog
`timescale 1ns/1ps
module tb_counter;
    reg clk = 0;
    always #5 clk = ~clk;      // 100 MHz
    wire [15:0] led;
    top dut (.clk_100mhz(clk), .led(led));
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_counter);
        #1_000_000;
        $finish;
    end
endmodule
```

**You are learning:** the single most important habit in FPGA work. Every subsequent module gets simulated before it goes near the board.

**Done when:** you can look at a waveform and read your own signals.

---

### M3 — 640×480 color bars over HDMI ★ **the real first milestone**
**Est. 1–2 weeks**

This is the big one. Build:
- MMCM producing 25 MHz and 125 MHz
- `video_timing.v` producing `de`, `hsync`, `vsync`, `x`, `y`
- Trivial pattern: `rgb = f(x)` giving 8 vertical color bars
- `tmds_encoder.v` ×3
- `serializer_10to1.v` ×4 (3 data + 1 clock channel)
- `OBUFDS` ×4

**Start from Real Digital's HDMI demo for this board if one exists.** Get *their* design running unmodified first, so you know your cable, monitor, and constraints are good. Then replace their modules with yours one at a time. Debugging your own TMDS encoder while simultaneously not knowing if your XDC is right is a bad time.

**Why 640×480 first:** a 25 MHz pixel clock closes timing trivially. If the picture is wrong, it is a logic bug, not a timing bug. Eliminate one variable.

**You are learning:** video timing, TMDS encoding, DC balancing, SERDES primitives, differential I/O, two-clock-domain design.

**Done when:** a monitor displays stable color bars and reports the mode as 640×480 @ 60 Hz.

**Expect this to be the hardest milestone.** Budget accordingly. See the debugging playbook (section 12) for the black-screen decision tree.

---

### M4 — Scale to 720p60
**Est. 2–3 days**

Change the MMCM settings and the timing constants. That's it.

**You are learning:** where your timing margin actually is. Run `report_timing_summary` and look at the worst path — it will probably be in the TMDS encoder's disparity feedback loop.

**Done when:** monitor reports 1280×720 @ 60 Hz. Then also try 1080p30 with the same clocking, as a free win.

---

### M5 — Better source material
**Est. 3–5 days**

Color bars have no texture. Build a procedural pattern generator with content worth processing: gradients, a moving circle, a checkerboard, diagonal ramps, concentric rings. Add an animation counter driven by `vsync` so things move.

Optionally add a small stored image (256×144, 8-bit palette, ~8 BRAM36) pixel-replicated up to full resolution.

**You are learning:** frame-rate-synchronous logic, BRAM inference, and you get a source that will actually exercise Sobel and the LUT.

**Done when:** a moving, textured image displays cleanly with no tearing or artifacts.

---

### M6 — 3D LUT color grading ★ **do this before Sobel**
**Est. 1–2 weeks**

The LUT is stateless — one pixel in, one pixel out, no line buffers, no window, no border cases. That makes it a much gentler introduction to inserting processing into a live pixel stream.

Build order within the milestone:
1. `lut3d.v` with the 8-bank storage, initialized to an **identity LUT** (output = input). Insert it in the path. The display must be pixel-identical to M5. If it isn't, you have a bug in addressing or interpolation, and you can find it without any confounding visual change.
2. Verify in simulation against the Python model first.
3. Load a real grade (warm, cool, teal-and-orange, high contrast, a film emulation). Generate the `.mem` file from a `.cube` file with `model/make_lut.py`.
4. Add a switch to bypass the LUT so you can A/B it live.

**You are learning:** BRAM banking, fixed-point interpolation, DSP inference, pipeline latency management, and how to build a self-testing feature (the identity LUT).

**Done when:** flipping a switch visibly changes the color grade with no other artifacts.

---

### M7 — Line buffers and Sobel
**Est. 1–2 weeks**

1. `line_buffer.v` — two cascaded BRAM line delays
2. `window_3x3.v` — three 3-tap shift registers producing a 3×3 neighborhood
3. `rgb2luma.v`
4. `sobel.v` — Gx, Gy, `|Gx| + |Gy|`, clamp, threshold
5. Output edges only first (white on black). Much easier to eyeball than a blend.
6. Then add `blend.v` and delay-matched RGB.

**Border handling:** decide explicitly. The simplest correct option is to force the output to black on the 1-pixel frame around the image. Replicating edge pixels is nicer but more logic. Whatever you choose, make the Python model do the same thing or your simulation comparison will fail on the border and you'll chase a phantom bug.

**You are learning:** BRAM line buffers, spatial filtering, delay matching across parallel branches, and the discipline of keeping `de`/`hs`/`vs` aligned.

**Done when:** clean edge detection on the live display, and a blend mode that overlays edges on the graded image.

---

### M8 — Runtime control
**Est. 3–5 days**

- Switches: mode select (passthrough / LUT only / edges only / blend), LUT select, bypass
- Potentiometer via XADC: edge threshold (a nice tactile demo)
- 7-segment: current mode, frame counter, measured pixel clock
- UART: upload a new LUT at runtime, set threshold numerically

**Done when:** you can demonstrate the whole thing to someone without reprogramming the board.

---

### M9 — Polish
**Est. ongoing**

- README with photos/video of the output
- Block diagram
- Timing and utilization reports checked in
- A written note on why 1080p60 isn't achievable on this part — this is the kind of detail that signals you actually understand the hardware rather than copying a tutorial
- Scripted build

---

## 9. Module designs and reference RTL

The code below is reference-quality but **not tested on hardware**. Treat it as a starting point to understand and adapt, not as a drop-in library. Simulate everything.

### 9.1 Video timing generator

```verilog
module video_timing #(
    parameter H_ACT  = 1280, parameter H_FP = 110,
    parameter H_SYNC = 40,   parameter H_BP = 220,
    parameter V_ACT  = 720,  parameter V_FP = 5,
    parameter V_SYNC = 5,    parameter V_BP = 20,
    parameter H_POL  = 1'b1, parameter V_POL = 1'b1   // 1 = positive sync
)(
    input  wire        clk,
    input  wire        rst,
    output reg  [11:0] x,        // 0 .. H_ACT-1 during active
    output reg  [11:0] y,
    output reg         de,
    output reg         hs,
    output reg         vs
);
    localparam H_TOTAL = H_ACT + H_FP + H_SYNC + H_BP;
    localparam V_TOTAL = V_ACT + V_FP + V_SYNC + V_BP;

    reg [11:0] hcnt = 0, vcnt = 0;

    always @(posedge clk) begin
        if (rst) begin
            hcnt <= 0; vcnt <= 0;
        end else if (hcnt == H_TOTAL-1) begin
            hcnt <= 0;
            vcnt <= (vcnt == V_TOTAL-1) ? 0 : vcnt + 1;
        end else begin
            hcnt <= hcnt + 1;
        end
    end

    // registered outputs — one cycle of latency, consistent across all signals
    always @(posedge clk) begin
        de <= (hcnt < H_ACT) && (vcnt < V_ACT);
        x  <= hcnt;
        y  <= vcnt;
        hs <= ((hcnt >= H_ACT + H_FP) && (hcnt < H_ACT + H_FP + H_SYNC)) ? H_POL : ~H_POL;
        vs <= ((vcnt >= V_ACT + V_FP) && (vcnt < V_ACT + V_FP + V_SYNC)) ? V_POL : ~V_POL;
    end
endmodule
```

### 9.2 TMDS encoder

This implements the DVI 1.0 encoding algorithm: stage 1 minimizes transitions via XOR or XNOR chaining, stage 2 maintains DC balance using a running disparity counter. During blanking it emits one of four fixed control tokens.

```verilog
module tmds_encoder (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] din,      // pixel data for this channel
    input  wire [1:0] ctrl,     // {C1, C0} — only used when de == 0
    input  wire       de,
    output reg  [9:0] dout
);
    // ---- stage 1: transition minimization ----
    wire [3:0] n1d = din[0] + din[1] + din[2] + din[3]
                   + din[4] + din[5] + din[6] + din[7];

    wire use_xnor = (n1d > 4) || ((n1d == 4) && (din[0] == 1'b0));

    wire [8:0] qm;
    assign qm[0] = din[0];
    genvar i;
    generate
        for (i = 1; i < 8; i = i + 1) begin : g_qm
            assign qm[i] = use_xnor ? ~(qm[i-1] ^ din[i])
                                    :  (qm[i-1] ^ din[i]);
        end
    endgenerate
    assign qm[8] = ~use_xnor;      // 1 = XOR was used, 0 = XNOR

    // ---- stage 2: DC balancing ----
    wire [3:0] n1q = qm[0] + qm[1] + qm[2] + qm[3]
                   + qm[4] + qm[5] + qm[6] + qm[7];
    wire [3:0] n0q = 4'd8 - n1q;

    wire signed [5:0] diff_1m0 = $signed({2'b0, n1q}) - $signed({2'b0, n0q});
    wire signed [5:0] diff_0m1 = -diff_1m0;

    reg signed [5:0] cnt;   // running disparity

    always @(posedge clk) begin
        if (rst) begin
            cnt  <= 0;
            dout <= 10'b1101010100;
        end else if (!de) begin
            cnt <= 0;                       // disparity resets during blanking
            case (ctrl)
                2'b00:   dout <= 10'b1101010100;
                2'b01:   dout <= 10'b0010101011;
                2'b10:   dout <= 10'b0101010100;
                default: dout <= 10'b1010101011;
            endcase
        end else begin
            if ((cnt == 0) || (n1q == n0q)) begin
                dout[9]   <= ~qm[8];
                dout[8]   <=  qm[8];
                dout[7:0] <=  qm[8] ? qm[7:0] : ~qm[7:0];
                cnt <= qm[8] ? cnt + diff_1m0 : cnt + diff_0m1;
            end
            else if (((cnt > 0) && (n1q > n0q)) ||
                     ((cnt < 0) && (n0q > n1q))) begin
                dout[9]   <= 1'b1;
                dout[8]   <= qm[8];
                dout[7:0] <= ~qm[7:0];
                cnt <= cnt + {qm[8], 1'b0} + diff_0m1;
            end
            else begin
                dout[9]   <= 1'b0;
                dout[8]   <= qm[8];
                dout[7:0] <= qm[7:0];
                cnt <= cnt - {~qm[8], 1'b0} + diff_1m0;
            end
        end
    end
endmodule
```

**The critical timing path in your entire design lives in this module** — the `cnt` feedback loop is combinational logic from `cnt` through comparators and adders back to `cnt`. If you fail timing at 74.25 MHz, look here first. Section 11 has a fix.

**Channel assignment for DVI:**

| Channel | Data | `ctrl` |
|---|---|---|
| 0 | Blue | `{vsync, hsync}` |
| 1 | Green | `2'b00` |
| 2 | Red | `2'b00` |

Output DVI signaling, not full HDMI (no data islands, no audio, no InfoFrames). Virtually every HDMI display accepts DVI-mode signaling, and it is dramatically simpler.

### 9.3 10:1 serializer

`OSERDESE2` maxes out at 8:1 on its own, so you cascade a master and a slave to get 10:1.

```verilog
module serializer_10to1 (
    input  wire       clk_pix,    // 74.25 MHz
    input  wire       clk_5x,     // 371.25 MHz
    input  wire       rst,
    input  wire [9:0] data,
    output wire       out_p,
    output wire       out_n
);
    wire shift1, shift2, ser;

    OSERDESE2 #(
        .DATA_RATE_OQ   ("DDR"),
        .DATA_RATE_TQ   ("SDR"),
        .DATA_WIDTH     (10),
        .SERDES_MODE    ("MASTER"),
        .TRISTATE_WIDTH (1),
        .TBYTE_CTL      ("FALSE"),
        .TBYTE_SRC      ("FALSE")
    ) u_master (
        .OQ        (ser),
        .OFB       (), .TQ (), .TFB (), .TBYTEOUT (),
        .SHIFTOUT1 (), .SHIFTOUT2 (),
        .CLK       (clk_5x),
        .CLKDIV    (clk_pix),
        .D1 (data[0]), .D2 (data[1]), .D3 (data[2]), .D4 (data[3]),
        .D5 (data[4]), .D6 (data[5]), .D7 (data[6]), .D8 (data[7]),
        .OCE (1'b1), .TCE (1'b0), .RST (rst),
        .SHIFTIN1 (shift1), .SHIFTIN2 (shift2),
        .T1 (1'b0), .T2 (1'b0), .T3 (1'b0), .T4 (1'b0),
        .TBYTEIN (1'b0)
    );

    OSERDESE2 #(
        .DATA_RATE_OQ   ("DDR"),
        .DATA_RATE_TQ   ("SDR"),
        .DATA_WIDTH     (10),
        .SERDES_MODE    ("SLAVE"),
        .TRISTATE_WIDTH (1),
        .TBYTE_CTL      ("FALSE"),
        .TBYTE_SRC      ("FALSE")
    ) u_slave (
        .OQ        (), .OFB (), .TQ (), .TFB (), .TBYTEOUT (),
        .SHIFTOUT1 (shift1), .SHIFTOUT2 (shift2),
        .CLK       (clk_5x),
        .CLKDIV    (clk_pix),
        .D1 (1'b0),     .D2 (1'b0),
        .D3 (data[8]),  .D4 (data[9]),
        .D5 (1'b0), .D6 (1'b0), .D7 (1'b0), .D8 (1'b0),
        .OCE (1'b1), .TCE (1'b0), .RST (rst),
        .SHIFTIN1 (1'b0), .SHIFTIN2 (1'b0),
        .T1 (1'b0), .T2 (1'b0), .T3 (1'b0), .T4 (1'b0),
        .TBYTEIN (1'b0)
    );

    OBUFDS u_obuf (.I(ser), .O(out_p), .OB(out_n));
endmodule
```

The slave's `D3`/`D4` carrying bits 8 and 9 looks arbitrary but is the documented cascade arrangement — the slave contributes the *last* two bits of the 10-bit word.

The **clock channel** uses the same serializer fed with the constant `10'b0000011111`, which produces a square wave at the pixel clock rate. Do not try to route the pixel clock directly to an `OBUFDS` — the phase relationship to the data channels will be wrong.

```verilog
serializer_10to1 u_clk_ch (
    .clk_pix(clk_pix), .clk_5x(clk_5x), .rst(rst),
    .data(10'b0000011111),
    .out_p(tmds_clk_p), .out_n(tmds_clk_n)
);
```

**Bit ordering note:** TMDS transmits LSB first. The serializer above sends `data[0]` first. If your picture comes up as coherent-but-wrong noise, bit or channel order is the first thing to check.

### 9.4 Parameterized delay line

You will use this constantly for keeping `de`/`hs`/`vs` aligned with data that has been through a pipeline.

```verilog
module delay_line #(
    parameter WIDTH = 1,
    parameter DEPTH = 1
)(
    input  wire              clk,
    input  wire [WIDTH-1:0]  din,
    output wire [WIDTH-1:0]  dout
);
    generate
        if (DEPTH == 0) begin : g_zero
            assign dout = din;
        end else begin : g_sr
            reg [WIDTH-1:0] sr [0:DEPTH-1];
            integer k;
            always @(posedge clk) begin
                sr[0] <= din;
                for (k = 1; k < DEPTH; k = k + 1)
                    sr[k] <= sr[k-1];
            end
            assign dout = sr[DEPTH-1];
        end
    endgenerate
endmodule
```

Define the latency of each processing module as a `localparam` and derive the delay depths from those parameters rather than hardcoding numbers. When you add a pipeline stage to Sobel six months from now, the delay line updates itself.

### 9.5 Video source

You cannot store a full frame. At 1280×720×24 bit a frame is 27.6 Mbit against 2.7 Mbit of BRAM. And QSPI flash, while large enough (16 MB holds a 2.76 MB frame), cannot be read fast enough: 74.25 Mpixel/s × 3 bytes = 223 MB/s, versus roughly 50 MB/s for quad-SPI at 100 MHz.

So: **generate content procedurally.** This is not a compromise — it gives you precise control over what your filters see.

```verilog
module pattern_gen (
    input  wire        clk,
    input  wire [11:0] x,
    input  wire [11:0] y,
    input  wire        frame_tick,   // pulse on vsync
    input  wire [2:0]  pattern_sel,
    output reg  [23:0] rgb
);
    reg [11:0] phase = 0;
    always @(posedge clk) if (frame_tick) phase <= phase + 1;

    // moving circle
    wire signed [12:0] cx = 13'sd640 + $signed({1'b0, phase[8:0]}) - 13'sd256;
    wire signed [12:0] dx = $signed({1'b0, x}) - cx;
    wire signed [12:0] dy = $signed({1'b0, y}) - 13'sd360;
    wire [25:0] r2 = dx*dx + dy*dy;
    wire in_circle = (r2 < 26'd10000);

    wire checker = x[5] ^ y[5];
    wire [7:0] ramp_x = x[9:2];
    wire [7:0] ramp_y = y[9:2];

    always @(posedge clk) begin
        case (pattern_sel)
            3'd0: rgb <= {ramp_x, ramp_y, 8'h80};                 // gradient
            3'd1: rgb <= checker ? 24'hFFFFFF : 24'h101010;       // checkerboard
            3'd2: rgb <= in_circle ? 24'hFF6020 : {ramp_x, 8'h30, ramp_y};
            3'd3: rgb <= {x[7:0], y[7:0], x[7:0] ^ y[7:0]};       // xor texture
            default: rgb <= {{3{x[9:7]}}, 8'h00, 8'h00};          // color bars
        endcase
    end
endmodule
```

Patterns 1 and 2 are the useful ones for Sobel (hard edges, curved edges). Patterns 0 and 3 are the useful ones for the LUT (full color coverage).

**Optional: a small stored image.** A 256×144 image with an 8-bit palette is 294,912 bits ≈ 8 BRAM36, plus a 256-entry × 24-bit palette. Pixel-replicate ×5 horizontally and ×5 vertically to fill 1280×720. The replication produces blocky output, which is actually fine for demonstrating Sobel (blocky edges are still edges) and excellent for demonstrating a LUT.

Generate the `.mem` file with `model/png2hex.py` and load it with `$readmemh` in an `initial` block — Vivado will infer BRAM with an initialization and bake the contents into the bitstream.

### 9.6 3D LUT with trilinear interpolation

#### Indexing

With a 17³ LUT and 8-bit input, the mapping is exact and clean:

```
r_idx  = pixel_r[7:4]      // 0 .. 15
r_frac = pixel_r[3:0]      // 0 .. 15
```

Node *i* represents input value 16·*i*. Node 16 represents 256 (clamped to 255 in practice). A pixel value of 255 gives `idx=15, frac=15`, interpolating 15/16 of the way from node 15 to node 16. The tiny error from 256 vs 255 is invisible.

#### The 8-bank scheme

The eight cube corners are `(r_idx + a, g_idx + b, b_idx + c)` for `a,b,c ∈ {0,1}`. Adding 1 flips the LSB, so the eight corners have all eight distinct parity triples `{r[0], g[0], b[0]}`. Store node `(R,G,B)` in:

```
bank    = {R[0], G[0], B[0]}                    // 0 .. 7
address = (R>>1)*81 + (G>>1)*9 + (B>>1)         // 0 .. 728
```

`R>>1` ranges 0..8 (9 values), hence the ×81 and ×9. Each bank holds 729 entries × 24 bits = 17,496 bits, which fits a single BRAM18. Eight banks = 8 BRAM18 = 4 BRAM36.

All eight banks receive the *same* address for a given pixel — you compute one address from `(r_idx>>1, g_idx>>1, b_idx>>1)` and every bank returns its corner. The bank-to-corner mapping is then a fixed permutation determined by `{r_idx[0], g_idx[0], b_idx[0]}`.

```verilog
module lut3d (
    input  wire        clk,
    input  wire [23:0] px_in,
    input  wire        de_in,
    output wire [23:0] px_out,
    output wire        de_out
);
    localparam LATENCY = 6;   // 1 addr + 1 BRAM + 1 permute + 3 lerp stages

    wire [7:0] r = px_in[23:16];
    wire [7:0] g = px_in[15:8];
    wire [7:0] b = px_in[7:0];

    wire [3:0] ri = r[7:4], gi = g[7:4], bi = b[7:4];
    wire [3:0] rf = r[3:0], gf = g[3:0], bf = b[3:0];

    // --- stage 1: address ---
    // ri>>1 etc. are 3 bits (0..7); the +1 corner can reach 8, which is why
    // each axis is 4 bits wide in the address arithmetic.
    wire [3:0] ra = {1'b0, ri[3:1]};
    wire [3:0] ga = {1'b0, gi[3:1]};
    wire [3:0] ba = {1'b0, bi[3:1]};

    reg [9:0] addr;
    reg [2:0] parity;
    reg [3:0] rf_d, gf_d, bf_d;
    always @(posedge clk) begin
        addr   <= ra*10'd81 + ga*10'd9 + ba;   // constant mults → shift-add
        parity <= {ri[0], gi[0], bi[0]};
        rf_d <= rf; gf_d <= gf; bf_d <= bf;
    end

    // --- stage 2: eight parallel BRAM reads ---
    reg [23:0] bank [0:7][0:728];
    initial begin
        $readmemh("lut_bank0.mem", bank[0]);
        $readmemh("lut_bank1.mem", bank[1]);
        $readmemh("lut_bank2.mem", bank[2]);
        $readmemh("lut_bank3.mem", bank[3]);
        $readmemh("lut_bank4.mem", bank[4]);
        $readmemh("lut_bank5.mem", bank[5]);
        $readmemh("lut_bank6.mem", bank[6]);
        $readmemh("lut_bank7.mem", bank[7]);
    end

    reg [23:0] q [0:7];
    integer n;
    always @(posedge clk)
        for (n = 0; n < 8; n = n + 1)
            q[n] <= bank[n][addr];

    // --- stage 3: permute banks into cube corners c[r][g][b] ---
    // corner (a,b_,c) lives in bank {ri[0]^a, gi[0]^b_, bi[0]^c}
    wire [23:0] c000 = q[{parity[2]^1'b0, parity[1]^1'b0, parity[0]^1'b0}];
    wire [23:0] c001 = q[{parity[2]^1'b0, parity[1]^1'b0, parity[0]^1'b1}];
    wire [23:0] c010 = q[{parity[2]^1'b0, parity[1]^1'b1, parity[0]^1'b0}];
    wire [23:0] c011 = q[{parity[2]^1'b0, parity[1]^1'b1, parity[0]^1'b1}];
    wire [23:0] c100 = q[{parity[2]^1'b1, parity[1]^1'b0, parity[0]^1'b0}];
    wire [23:0] c101 = q[{parity[2]^1'b1, parity[1]^1'b0, parity[0]^1'b1}];
    wire [23:0] c110 = q[{parity[2]^1'b1, parity[1]^1'b1, parity[0]^1'b0}];
    wire [23:0] c111 = q[{parity[2]^1'b1, parity[1]^1'b1, parity[0]^1'b1}];

    // --- stages 4-6: 7-lerp tree, applied per channel ---
    // (instantiate lerp_rgb 7 times: 4 along B, 2 along G, 1 along R)
    //   l00 = lerp(c000, c001, bf)    l01 = lerp(c010, c011, bf)
    //   l10 = lerp(c100, c101, bf)    l11 = lerp(c110, c111, bf)
    //   m0  = lerp(l00,  l01,  gf)    m1  = lerp(l10,  l11,  gf)
    //   out = lerp(m0,   m1,   rf)
endmodule
```

A note on that `reg [23:0] bank [0:7][0:728]` declaration: Vivado will infer eight BRAMs from it, but 2-D unpacked arrays of memories are a place where inference sometimes goes sideways. If synthesis reports LUTRAM or distributed RAM instead of BRAM, declare eight separate 1-D arrays in a generate loop, or add `(* ram_style = "block" *)`.

The single lerp primitive:

```verilog
module lerp8 (
    input  wire       clk,
    input  wire [7:0] a,
    input  wire [7:0] b,
    input  wire [3:0] f,      // 0..15, interpreted as f/16
    output reg  [7:0] y
);
    wire signed [8:0]  d = $signed({1'b0, b}) - $signed({1'b0, a});
    wire signed [12:0] p = d * $signed({1'b0, f});
    always @(posedge clk)
        y <= a + p[12:4];     // a + (b-a)*f/16
endmodule
```

`lerp_rgb` is three of these in parallel. Seven `lerp_rgb` instances = 21 multipliers, well within your 120 DSPs. (Vivado may map the small 9×4 multiplies to LUTs rather than DSPs, which is also fine.)

#### Generating LUT data

`model/make_lut.py` should read a standard `.cube` file (Adobe/Resolve format, widely available for free) or generate a grade programmatically, resample to 17³, and emit eight `.mem` files:

```python
import numpy as np

def emit_banks(lut):            # lut: (17,17,17,3) uint8, indexed [r][g][b]
    banks = [np.zeros((729, 3), dtype=np.uint8) for _ in range(8)]
    for R in range(17):
        for G in range(17):
            for B in range(17):
                bank = ((R & 1) << 2) | ((G & 1) << 1) | (B & 1)
                addr = (R >> 1) * 81 + (G >> 1) * 9 + (B >> 1)
                banks[bank][addr] = lut[R, G, B]
    for i, bk in enumerate(banks):
        with open(f"lut_bank{i}.mem", "w") as f:
            for px in bk:
                f.write(f"{px[0]:02x}{px[1]:02x}{px[2]:02x}\n")
```

The identity LUT — your single most useful debugging tool — is just `lut[R,G,B] = (min(R*16,255), min(G*16,255), min(B*16,255))`.

### 9.7 Line buffer

Two BRAM line delays in cascade. The cascade arrangement avoids any role-rotation logic: the second buffer is fed from the first buffer's read output, so `row1` is always one line behind and `row0` is always two lines behind.

```verilog
module line_buffer #(
    parameter WIDTH = 24,
    parameter MAX_X = 1920
)(
    input  wire             clk,
    input  wire             de,
    input  wire [11:0]      x,
    input  wire [WIDTH-1:0] din,
    output wire [WIDTH-1:0] row0,   // two lines above
    output wire [WIDTH-1:0] row1,   // one line above
    output wire [WIDTH-1:0] row2    // current
);
    (* ram_style = "block" *) reg [WIDTH-1:0] buf0 [0:MAX_X-1];
    (* ram_style = "block" *) reg [WIDTH-1:0] buf1 [0:MAX_X-1];

    reg [WIDTH-1:0] q0, q1, d_reg;

    always @(posedge clk) begin
        if (de) begin
            q0        <= buf0[x];   // read-before-write: old value = line n-1
            buf0[x]   <= din;
            q1        <= buf1[x];   // line n-2
            buf1[x]   <= q0;        // one cycle behind — see note
            d_reg     <= din;
        end
    end

    assign row2 = d_reg;
    assign row1 = q0;
    assign row0 = q1;
endmodule
```

**Note the one-cycle skew:** `buf1[x] <= q0` writes the value read *last* cycle, so `buf1` is written one column late relative to `buf0`. Either offset the read address for `buf1` by one, or register `x` and use the delayed address. This is exactly the kind of off-by-one that a testbench comparing against the Python model catches instantly and that staring at a monitor never will.

Then the 3×3 window:

```verilog
module window_3x3 #(parameter W = 8)(
    input  wire        clk,
    input  wire [W-1:0] row0, row1, row2,
    output reg  [W-1:0] p00, p01, p02,
    output reg  [W-1:0] p10, p11, p12,
    output reg  [W-1:0] p20, p21, p22
);
    always @(posedge clk) begin
        p02 <= row0; p01 <= p02; p00 <= p01;
        p12 <= row1; p11 <= p12; p10 <= p11;
        p22 <= row2; p21 <= p22; p20 <= p21;
    end
endmodule
```

The window output is centered on `p11`, which corresponds to a pixel **2 lines and 1 column** behind the input stream. Every parallel branch must be delayed by the same amount.

### 9.8 Luma and Sobel

```verilog
module rgb2luma (
    input  wire        clk,
    input  wire [23:0] rgb,
    output reg  [7:0]  y
);
    // Y ≈ 0.299R + 0.587G + 0.114B, scaled by 256
    wire [15:0] acc = rgb[23:16] * 8'd77
                    + rgb[15:8]  * 8'd150
                    + rgb[7:0]   * 8'd29;
    always @(posedge clk) y <= acc[15:8];
endmodule
```

```verilog
module sobel (
    input  wire       clk,
    input  wire [7:0] p00, p01, p02,
    input  wire [7:0] p10, p11, p12,
    input  wire [7:0] p20, p21, p22,
    input  wire [7:0] threshold,
    output reg  [7:0] mag,
    output reg        edge_flag
);
    //  Gx = [-1 0 +1]      Gy = [-1 -2 -1]
    //       [-2 0 +2]           [ 0  0  0]
    //       [-1 0 +1]           [+1 +2 +1]
    // All coefficients are powers of two → shifts and adds, no multipliers.

    wire signed [11:0] gx = $signed({4'b0, p02}) + ($signed({4'b0, p12}) <<< 1) + $signed({4'b0, p22})
                          - $signed({4'b0, p00}) - ($signed({4'b0, p10}) <<< 1) - $signed({4'b0, p20});

    wire signed [11:0] gy = $signed({4'b0, p20}) + ($signed({4'b0, p21}) <<< 1) + $signed({4'b0, p22})
                          - $signed({4'b0, p00}) - ($signed({4'b0, p01}) <<< 1) - $signed({4'b0, p02});

    reg [11:0] agx, agy;
    always @(posedge clk) begin
        agx <= gx[11] ? -gx : gx;
        agy <= gy[11] ? -gy : gy;
    end

    wire [12:0] sum = agx + agy;                 // |Gx| + |Gy| approximation

    always @(posedge clk) begin
        mag       <= (sum > 13'd255) ? 8'd255 : sum[7:0];
        edge_flag <= (sum > {5'b0, threshold});
    end
endmodule
```

`|Gx| + |Gy|` overestimates the true magnitude `sqrt(Gx²+Gy²)` by up to ~41%, which is visually irrelevant and saves you a square root. If you want better, the alpha-max-beta-min approximation (`0.96·max + 0.40·min`) is two multiplies and gets within ~4%.

### 9.9 Blend and mode mux

```verilog
module blend (
    input  wire        clk,
    input  wire [23:0] rgb_graded,
    input  wire [7:0]  edge_mag,
    input  wire        edge_flag,
    input  wire [1:0]  mode,     // 0=pass 1=lut 2=edges 3=overlay
    input  wire [23:0] rgb_raw,
    output reg  [23:0] rgb_out
);
    always @(posedge clk) begin
        case (mode)
            2'd0: rgb_out <= rgb_raw;
            2'd1: rgb_out <= rgb_graded;
            2'd2: rgb_out <= {3{edge_mag}};
            2'd3: rgb_out <= edge_flag ? 24'hFFFFFF : rgb_graded;
        endcase
    end
endmodule
```

A nicer overlay blends proportionally rather than hard-switching:
`out = graded + (255 - graded) * edge_mag / 255`, which makes edges glow rather than punch holes.

---

## 10. Verification strategy

**Debugging video by looking at a monitor is close to useless.** A single off-by-one in a line buffer produces an image that looks subtly wrong in a way you cannot localize. The fix is a simulation flow that compares full images against a reference.

### 10.1 Golden model

```python
# model/golden.py
import numpy as np
from PIL import Image

def rgb2luma(img):
    w = np.array([77, 150, 29], dtype=np.int32)
    return ((img.astype(np.int32) @ w) >> 8).astype(np.uint8)

def sobel(luma, threshold):
    KX = np.array([[-1,0,1],[-2,0,2],[-1,0,1]], dtype=np.int32)
    KY = np.array([[-1,-2,-1],[0,0,0],[1,2,1]], dtype=np.int32)
    h, w = luma.shape
    out = np.zeros((h, w), dtype=np.uint8)
    L = luma.astype(np.int32)
    for y in range(1, h-1):
        for x in range(1, w-1):
            win = L[y-1:y+2, x-1:x+2]
            gx = int((win * KX).sum())
            gy = int((win * KY).sum())
            out[y, x] = min(abs(gx) + abs(gy), 255)
    return out                       # border stays 0 — RTL must match

def lut3d_apply(img, lut):           # lut: (17,17,17,3) uint8
    idx  = img >> 4
    frac = (img & 0xF).astype(np.int32)
    # ... trilinear with integer arithmetic that matches the RTL exactly,
    #     i.e. a + ((b-a)*f >> 4) at every stage, not float interpolation
```

The golden model must replicate the RTL's **integer truncation behavior exactly**, including the `>> 4` at each lerp stage. If you use floating-point interpolation in Python and integer in Verilog, you will get 1-LSB differences everywhere and won't be able to tell a real bug from rounding.

### 10.2 PNG ↔ hex

```python
# model/png2hex.py
import sys
from PIL import Image

img = Image.open(sys.argv[1]).convert("RGB")
with open(sys.argv[2], "w") as f:
    for px in img.getdata():
        f.write(f"{px[0]:02x}{px[1]:02x}{px[2]:02x}\n")
```

`hex2png.py` is the inverse.

### 10.3 Full-pipeline testbench

```verilog
`timescale 1ns/1ps
module tb_pipeline;
    localparam W = 64, H = 64;      // small image — simulation is slow

    reg clk = 0;
    always #6.734 clk = ~clk;       // ~74.25 MHz

    reg  [23:0] src [0:W*H-1];
    reg  [23:0] pixel;
    reg         de = 0;
    wire [23:0] result;
    wire        de_out;

    integer i, out_i;
    integer fout;

    video_pipeline dut (
        .clk(clk), .rst(1'b0),
        .px_in(pixel), .de_in(de),
        .px_out(result), .de_out(de_out)
    );

    initial begin
        $readmemh("vectors/input.hex", src);
        fout = $fopen("vectors/output.hex", "w");
        out_i = 0;

        // stream the image with realistic blanking so line buffers see
        // the same line boundaries they will see on hardware
        for (i = 0; i < H; i = i + 1) begin
            // active line
            for (integer j = 0; j < W; j = j + 1) begin
                @(posedge clk);
                de    <= 1'b1;
                pixel <= src[i*W + j];
            end
            // horizontal blanking
            repeat (20) begin
                @(posedge clk);
                de <= 1'b0;
            end
        end
        repeat (100) @(posedge clk);
        $fclose(fout);
        $finish;
    end

    always @(posedge clk)
        if (de_out) $fwrite(fout, "%06h\n", result);
endmodule
```

Then in Python: run the golden model on the same input, compare `output.hex` against the expected, and report the first differing pixel with its coordinates. A script that prints `first mismatch at (x=1, y=2): got 0x3f3f3f expected 0x000000` will save you days.

### 10.4 Unit testbenches worth writing

| Module | Test |
|---|---|
| `tmds_encoder` | Feed all 256 input values repeatedly. Assert: output always has ≤5 transitions, running disparity stays bounded within ±5, control tokens appear correctly when `de` is low. These are the DVI spec's own guarantees — if your encoder violates them, the monitor will not sync. |
| `video_timing` | Assert exact `H_TOTAL` × `V_TOTAL` cycles per frame, `de` high exactly `H_ACT × V_ACT` times, sync pulses the right width and polarity. |
| `lut3d` | Identity LUT → output must equal input for all 2²⁴ inputs (or a random sample of 100k). |
| `line_buffer` | Push a counting ramp, assert `row0`/`row1`/`row2` differ by exactly one and two line periods. |
| `sobel` | A single white pixel on black → known 3×3 response. A vertical edge → `Gx` maximal, `Gy` zero. |

The TMDS transition-count assertion is especially valuable, because a broken encoder produces a black screen and nothing else.

---

## 11. Timing closure notes

Target: **WNS ≥ 0** on both `clk_pix` (13.47 ns period) and `clk_5x` (2.69 ns).

### General rules

- Register every module output. No combinational path crosses a module boundary.
- Never write a multi-level combinational expression across more than ~4 LUT levels at 74 MHz. Break it with a pipeline register.
- Constant multiplications (×81, ×9, ×77, ×150) synthesize to shift-add trees; they are fine. Variable multiplications should be pipelined into DSP48 slices — instantiate with input, pipeline, and output registers so Vivado uses the DSP's internal pipelining.

### The TMDS encoder disparity loop

This is the most likely failure. The path is:

```
cnt (reg) → compare with 0 → select one of three branches
          → add/subtract → cnt (reg)
```

At 74.25 MHz this usually closes, but it can be tight. Two fixes if it doesn't:

1. **Precompute both candidate next-disparity values in a prior pipeline stage** and make the final stage a pure mux. The comparison `cnt > 0` and the additions then happen in parallel rather than in series.
2. **Pipeline stage 1 separately.** `qm` and the population counts depend only on `din`, not on `cnt`, so they can be computed a cycle earlier with no functional change.

### Placement

Add `set_property IOB TRUE` on nothing in the TMDS path — the `OSERDESE2` output must go directly to the `OBUFDS` with no intervening logic, and Vivado handles that placement automatically. If you find Vivado inserting logic there, you have a bug in your instantiation.

### Reading the timing report

`Reports → Timing → Report Timing Summary`. Look at:

- **WNS** (setup) and **WHS** (hold) — both must be ≥ 0
- **Number of failing endpoints** — if it's 1, it's usually one specific path you can fix. If it's 5,000, you have a missing clock constraint or a clock domain crossing you didn't know about.
- **Clock interaction report** — confirms `clk_pix` and `clk_5x` are recognized as related. If they show as asynchronous, your MMCM constraint is wrong and Vivado is not analyzing the OSERDES path at all, which means a "passing" report is meaningless.

---

## 12. Debugging playbook

### 12.1 Black screen / "no signal"

Work down this list in order. Do not skip steps.

1. **Does the `locked` output of the MMCM assert?** Wire it to an LED. If not locked, nothing downstream works.
2. **Is the pixel clock the frequency you think it is?** Divide it down to ~1 Hz and blink an LED, or better: count `clk_pix` edges over a known number of 100 MHz cycles and display the result on the 7-segment. A wrong MMCM setting is common and silent.
3. **Is `vsync` toggling at ~60 Hz?** Wire it to a counter → 7-segment frame counter. If frames aren't advancing, your timing generator is stuck.
4. **Is the clock channel serializer outputting?** Some monitors will at least report "unsupported mode" if they see a TMDS clock. Total silence often means the clock channel is dead.
5. **Check bit order.** TMDS is LSB-first. If you feed `data[9]` first, you get a stable but meaningless signal.
6. **Check channel order.** Blue must be channel 0 (the one carrying hsync/vsync in `ctrl`). Green and Red on 1 and 2. Swapped channels give a picture with wrong colors; a swapped *blue* channel gives no sync at all.
7. **Check sync polarity.** 640×480 wants negative hsync and vsync; 720p and 1080p want positive. Wrong polarity often gives "out of range".
8. **Check that `ctrl` is `{vsync, hsync}` and not `{hsync, vsync}`.** Easy to get backwards, and it produces exactly this symptom.
9. **Verify in simulation** that the TMDS encoder emits the four control tokens during blanking and that the encoded stream never exceeds 5 transitions per word.
10. **Try a different monitor.** Some displays are pickier about non-standard timing than others. A cheap old 1080p TV is often more forgiving than a modern high-end monitor.
11. **Try a different cable.**

### 12.2 Picture appears but is wrong

| Symptom | Likely cause |
|---|---|
| Image shifted horizontally by a few pixels | `de` not delay-matched to pixel data through the pipeline |
| Image shifted vertically by 1–2 lines | Line buffer latency not accounted for in the `de` delay |
| Diagonal tearing / image sheared | `H_TOTAL` wrong |
| Image rolls vertically | `V_TOTAL` wrong |
| Correct geometry, wrong colors | Channel assignment swapped (R↔B is the classic) |
| Sparkle / random pixel noise | Timing violation. Check WNS. Do not ignore this. |
| Left or top edge has a 1-pixel garbage line | Border handling in the convolution |
| Colors slightly off after LUT | Interpolation rounding mismatch, or bank permutation wrong |
| Vertical banding in the LUT output | LUT address computation wrong — off-by-one in the ×81/×9 stride |

### 12.3 Integrated Logic Analyzer (ILA)

Vivado's ILA lets you capture internal signals on the running hardware. Add it via **IP Catalog → Debug & Verification → ILA**, or by marking signals with `(* mark_debug = "true" *)` and running the Set Up Debug wizard.

Useful triggers:
- Trigger on `vsync` rising edge, capture the first 1024 pixels of a frame
- Trigger on `de` rising with `y == 100`, capture a specific scanline
- Trigger on a comparison between your RTL output and an expected value

ILA costs BRAM (you have plenty) and can affect timing. Remove it before final builds.

### 12.4 The general principle

Every time you are tempted to "just try it on the board," ask whether you could answer the same question in simulation in 30 seconds instead. Usually you can. The board is for confirming that something which already works in simulation also works in silicon — not for finding logic bugs.

---

## 13. Stretch goals

Ordered roughly by effort.

| Feature | Notes |
|---|---|
| **1D LUT per channel + 3D LUT** | A 1D curve stage before the 3D LUT is how real color pipelines work (shaper LUT). Cheap: 3 × 256-entry BRAM. |
| **Gaussian blur pre-filter** | Reuses your existing 3×3 window infrastructure. Reduces Sobel noise. |
| **5×5 kernels** | Requires 4 line buffers instead of 2. Straightforward extension. |
| **Non-maximum suppression** | Thins Sobel edges to single-pixel width. Needs gradient direction, which needs `atan2` — use a coarse 8-direction quantization from the signs and relative magnitudes of Gx/Gy instead. |
| **Full Canny** | NMS + hysteresis thresholding. Hysteresis needs a second pass or a clever streaming approximation. Genuinely hard; good stretch goal. |
| **Runtime LUT upload over UART** | Write into BRAM from the UART domain during vertical blanking to avoid tearing. Good CDC exercise. |
| **On-screen display** | Text overlay showing current mode and parameters. Character ROM + a small text buffer. |
| **Runtime resolution switching** | MMCM dynamic reconfiguration (DRP) + parameterized timing. |
| **Camera input** | An OV7670 or Pmod camera gives you real live video. This is the highest-value addition to the project and costs about $15. |
| **YCbCr 4:2:2 internal format** | Halves the bandwidth through the processing stages. Realistic for a production design. |
| **HDMI input** | Requires different hardware. See section 2.3. |

---

## 14. References

### Documentation to have open

| Document | What for |
|---|---|
| **UG471** — 7 Series SelectIO Resources | `OSERDESE2`/`ISERDESE2` port lists, cascade rules, the 10:1 example |
| **UG472** — 7 Series Clocking Resources | MMCM configuration, VCO ranges, clock buffer types and when to use each |
| **UG473** — 7 Series Memory Resources | BRAM inference templates, `ram_style` attribute |
| **UG901** — Vivado Synthesis | HDL coding templates Vivado reliably infers |
| **UG906** — Vivado Design Analysis and Closure | Reading timing reports properly |
| **DS189** — Spartan-7 Data Sheet | The speed-grade numbers in section 2.2. Confirm them for your exact part. |
| **XAPP585** / **XAPP1064** | Xilinx app notes on 7:1 and 10:1 LVDS serialization — the source of the standard serializer pattern |
| **DVI 1.0 specification** | The TMDS encoding algorithm, section 3.2.2 |
| **CEA-861** | Standard video timings |
| Real Digital Boolean Board reference manual + master XDC | Pin assignments. Get these from realdigital.org. |

### Open-source designs worth reading

- Digilent's `rgb2dvi` and `dvi2rgb` IP (in their `vivado-library` repo) — production-quality VHDL for exactly this problem. Read it; note where it acknowledges the speed-grade limits.
- Mike Field's (hamsterworks) HDMI projects — a well-known minimal Verilog DVI transmitter, widely referenced by hobbyists.
- `hdl-util/hdmi` — a modern, well-documented SystemVerilog HDMI transmitter including audio and data islands.

Read these for structure and for the parts you get stuck on. Write your own encoder and serializer, though — that's the part of this project that teaches you the most.

---

## Appendix A — Decision record

Recording *why* things are the way they are, because in three months you will not remember.

| Decision | Rationale |
|---|---|
| 720p60 instead of 1080p60 | 742.5 MHz serial clock exceeds every clock buffer on a -1 part (`BUFG` 464 MHz, `BUFIO` 600 MHz) and 1485 Mb/s exceeds the 950 Mb/s `OSERDESE2` limit. Not an overclock — physically unroutable. |
| 1080p30 offered as an alternative "1080p" mode | Same 74.25 MHz pixel clock as 720p60. Free. |
| Procedural source instead of stored frames | 2.7 Mbit of BRAM vs 27.6 Mbit for one 720p frame. QSPI flash is large enough but ~4× too slow. |
| No frame buffer, fully streaming | Sobel needs 3 lines, LUT needs 0. Avoids a DDR controller entirely — and the board has no DDR. |
| Sobel on ungraded luma, in parallel with the LUT | Grading can crush the local contrast the gradient operator depends on. |
| `\|Gx\| + \|Gy\|` instead of true magnitude | ≤41% overestimate, visually irrelevant, saves a square root. |
| 17³ LUT, 8-bank storage | 17 nodes maps exactly onto 8-bit input (`[7:4]` index, `[3:0]` fraction). Parity banking gives all 8 cube corners in one cycle from single-port BRAMs. |
| DVI signaling, not full HDMI | No data islands, no audio, no InfoFrames. Accepted by essentially every display. Dramatically simpler. |
| Registered module boundaries throughout | Buys timing closure almost for free at a latency cost that is irrelevant for video. |

---

## Appendix B — Quick reference card

```
Part:            xc7s50csga324-1
System clock:    100 MHz

720p60 / 1080p30 MMCM:  D=5, M=37.125, VCO=742.5 MHz
                        CLKOUT0 ÷2  → 371.25 MHz  (clk_5x)
                        CLKOUT1 ÷10 →  74.25 MHz  (clk_pix)

640x480p60 MMCM:        D=1, M=10.000, VCO=1000 MHz
                        CLKOUT0 ÷8  → 125 MHz
                        CLKOUT1 ÷40 →  25 MHz

TMDS channel map:  ch0 = Blue  + ctrl {vsync, hsync}
                   ch1 = Green + ctrl 2'b00
                   ch2 = Red   + ctrl 2'b00
                   clk = constant 10'b0000011111

Control tokens:    00 → 1101010100
                   01 → 0010101011
                   10 → 0101010100
                   11 → 1010101011

Serial order:      LSB first (data[0] out first)

LUT banking:       bank = {R[0], G[0], B[0]}
                   addr = (R>>1)*81 + (G>>1)*9 + (B>>1)

-1 speed grade:    BUFG 464 MHz   BUFIO 600 MHz
                   BUFR 315 MHz   OSERDES DDR 950 Mb/s
```
