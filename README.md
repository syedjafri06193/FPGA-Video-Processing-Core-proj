# FPGA Video Processing Core

[![CI](https://github.com/syedjafri06193/FPGA-Video-Processing-Core-proj/actions/workflows/ci.yml/badge.svg)](https://github.com/syedjafri06193/FPGA-Video-Processing-Core-proj/actions/workflows/ci.yml)

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
> [`1—Documentation/design.md`](1—Documentation/design.md) §1–2.

## Repository layout

```
.
├── README.md          ← you are here
├── 1—Documentation/   ← all documentation (index in its README)
│   ├── design.md      ← full design & build guide (the spec code comments cite)
│   ├── design.pdf     ← same guide, PDF
│   └── v1/            timing, verification, bring-up, spec errata
└── v1/                ← first implementation: RTL, testbenches, model, build
    ├── rtl/           synthesizable Verilog
    ├── sim/           one testbench per module + full-frame regression
    ├── model/         bit-exact Python golden model and vector tools
    ├── constraints/   boolean.xdc
    └── scripts/       Vivado build / program Tcl
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

## Feedback

Feedback, bug reports and ideas are welcome.

- **Bugs or problems:** [open an issue](https://github.com/syedjafri06193/FPGA-Video-Processing-Core-proj/issues/new) and include your FPGA board, toolchain version, and steps to reproduce.
- **Ideas or questions:** start a thread in [Discussions](https://github.com/syedjafri06193/FPGA-Video-Processing-Core-proj/discussions).
- **Code changes:** pull requests are appreciated; please describe what you changed and how you tested it.

<!-- project-metrics:start -->
## Project Metrics

[![Stars](https://img.shields.io/github/stars/syedjafri06193/FPGA-Video-Processing-Core-proj?style=flat-square)](https://github.com/syedjafri06193/FPGA-Video-Processing-Core-proj/stargazers) [![Forks](https://img.shields.io/github/forks/syedjafri06193/FPGA-Video-Processing-Core-proj?style=flat-square)](https://github.com/syedjafri06193/FPGA-Video-Processing-Core-proj/forks) [![Open issues](https://img.shields.io/github/issues/syedjafri06193/FPGA-Video-Processing-Core-proj?style=flat-square)](https://github.com/syedjafri06193/FPGA-Video-Processing-Core-proj/issues) [![Last commit](https://img.shields.io/github/last-commit/syedjafri06193/FPGA-Video-Processing-Core-proj/improvements?style=flat-square)](https://github.com/syedjafri06193/FPGA-Video-Processing-Core-proj/commits/improvements) [![Commits](https://img.shields.io/github/commit-activity/t/syedjafri06193/FPGA-Video-Processing-Core-proj?style=flat-square)](https://github.com/syedjafri06193/FPGA-Video-Processing-Core-proj/commits/improvements) [![Top language](https://img.shields.io/github/languages/top/syedjafri06193/FPGA-Video-Processing-Core-proj?style=flat-square)](https://github.com/syedjafri06193/FPGA-Video-Processing-Core-proj) [![Repo size](https://img.shields.io/github/repo-size/syedjafri06193/FPGA-Video-Processing-Core-proj?style=flat-square)](https://github.com/syedjafri06193/FPGA-Video-Processing-Core-proj)

### Code

| Metric | Value |
|---|---|
| Lines of code | 3,050 |
| Source files | 42 |
| Tracked files | 56 |
| Documentation | 8 Markdown files (16,367 words), 1 PDF |
| Commits | 13 |
| Contributors | 1 |
| Active | 2026-09-11 → 2026-10-28 |

| Language | Lines | Share |
|---|---:|---:|
| verilog | 2,407 | 78.9% |
| Python | 450 | 14.8% |
| Makefile | 112 | 3.7% |
| Tcl | 81 | 2.7% |

### Performance

| Metric | Result |
|---|---|
| `tb_pipeline` regression | Full 64×64 frame bit-exact vs reference model, 4 modes × 2 grades |
| 720p60 / 1080p30 serial clock | 371.25 MHz (under 464 MHz BUFG limit) |

<sub>Measured figures recorded in [`1—Documentation/v1/verification.md`](1%E2%80%94Documentation/v1/verification.md).</sub>

<sub>Code stats as of 2026-10-28, counted with pygount (comments and blank lines excluded). Badges update live.</sub>
<!-- project-metrics:end -->
