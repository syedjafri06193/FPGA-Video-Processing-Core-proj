# FPGA Video Processing Core

Real-time HDMI video pipeline on a Spartan-7 (Real Digital Boolean Board)
implementing 3×3 Sobel edge detection and 17³ 3D-LUT colour grading.

```
 pattern ──┬─────────────────── lut3d (17³, trilinear) ──┐
 generator │                                             ├── blend ── TMDS ── OSERDES ── HDMI
           └── luma ── line buffer ── 3×3 window ── sobel ┘
```

> **Scope note.** The original goal was HDMI-in → HDMI-out at 1080p60. The
> Boolean Board has no HDMI input, and 1080p60 needs a 742.5 MHz clock that a
> -1 speed-grade part cannot route. The design runs at **720p60** (and 1080p30
> from the same pixel clock) on a procedural source. Full reasoning in
> [`docs/design.md`](docs/design.md) §1–2.

## Repository layout

```
.
├── README.md          ← you are here
├── docs/
│   ├── design.md      ← full design & build guide (the spec code comments cite)
│   └── design.pdf     ← same guide, PDF
└── v1/                ← first implementation: RTL, testbenches, model, build
    ├── rtl/           synthesizable Verilog
    ├── sim/           one testbench per module + full-frame regression
    ├── model/         bit-exact Python golden model and vector tools
    ├── constraints/   boolean.xdc
    ├── scripts/       Vivado build / program Tcl
    └── docs/          timing, verification, bring-up, spec errata
```

Each `vN/` directory is a self-contained iteration of the design. Start with
[`v1/README.md`](v1/README.md).

## Quick start

Simulation only — no FPGA tools needed (Icarus Verilog, Python 3, numpy, pillow):

```bash
cd v1
make          # generate vectors, run every testbench, compare frames to the model
```

Bitstream (Vivado, after filling the pin placeholders in `v1/constraints/boolean.xdc`):

```bash
cd v1
vivado -mode batch -source scripts/build.tcl -tclargs 720p teal_orange
vivado -mode batch -source scripts/program.tcl
```

## Versions and feedback

| Version | Summary | Feedback |
|---|---|---|
| [v1](v1/) | 720p60 pipeline, Sobel + 3D LUT, 4 output modes, full simulation regression | — |

Add a row per version as new iterations land.
