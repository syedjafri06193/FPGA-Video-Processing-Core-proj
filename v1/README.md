# FPGA Video Processing Core

Real-time video pipeline for the Real Digital Boolean Board (Spartan-7
XC7S50-CSGA324-**1**), driving a DVI/HDMI display at 720p60 with 3×3 Sobel edge
detection and 17³ 3D-LUT colour grading on a procedurally generated source,
with runtime-selectable processing modes.

The full design is in [`../Documentation/README.md`](../Documentation/README.md);
code comments refer to it by section number throughout.

---

## Quick start

```bash
cd v1
make                    # generate vectors, run every testbench, compare frames
```

About twenty seconds, no FPGA tools required — Icarus Verilog, Python, numpy
and pillow. The last thing it prints:

```
PASS mode=pass grade=identity: 4096 pixels identical
PASS mode=lut grade=identity: 4096 pixels identical
PASS mode=edges grade=identity: 4096 pixels identical
PASS mode=overlay grade=identity: 4096 pixels identical
... (same for the teal_orange grade)

================================================================
 all testbenches passed, and the pipeline matches the golden
 model pixel for pixel in every mode
================================================================
```

To build a bitstream, fill in the pin placeholders in
`constraints/boolean.xdc` from Real Digital's master XDC, then:

```bash
vivado -mode batch -source scripts/build.tcl -tclargs 720p teal_orange
vivado -mode batch -source scripts/program.tcl
```

The build fails loudly if the XDC still has `<PIN>` placeholders, and again if
timing is not met.

## What it does

```
 pattern ──┬─────────────────── lut3d (17³, trilinear) ──┐
 generator │                                             ├── blend ── TMDS ── OSERDES ── HDMI
           └── luma ── line buffer ── 3×3 window ── sobel ┘
```

Two branches in parallel, not in series. Edge detection runs on luma from the
**ungraded** image, because grading crushes the local contrast a gradient
operator depends on; the RGB pixel takes a delay-matched path through the LUT
and the two meet at the blend.

| Mode | Output |
|---|---|
| 0 passthrough | the source, for A/B |
| 1 LUT | graded only |
| 2 edges | Sobel magnitude, white on black |
| 3 overlay | graded with edges punched in (or glowing) |

Seven grades ship as ready-made LUTs (`identity`, `warm`, `cool`,
`teal_orange`, `high_contrast`, `mono`, `bleach_bypass`), and
`model/make_lut.py` reads any standard `.cube` file.

## Scope, and the two things the original pitch asked for that are not possible

The original statement was *"Real-time HDMI video pipeline on Spartan-7
implementing edge detection and LUT-based colour grading at 1080p60."* Two
parts of that cannot be built on this board, and pretending otherwise would be
the least interesting kind of failure:

**There is no HDMI input.** The Boolean Board's video interface is an HDMI
*source*. There is no TMDS receiver and no way to add one through the Pmod
headers at 742 Mb/s. The source here is procedural instead — which costs
nothing algorithmically, since the filters do not care where pixels come from.
A $15 camera module is the natural upgrade.

**1080p60 needs a 742.5 MHz clock, and no clock buffer on this part can carry
it.** `BUFG` tops out at 464 MHz and `BUFIO` at 600 MHz on a -1 speed grade,
and the 1485 Mb/s serial rate exceeds the OSERDES limit of 950 Mb/s by 56%.
Not a marginal overclock — unroutable. The arithmetic is in
[`docs/timing.md`](docs/timing.md).

720p60 and 1080p30 share the same 74.25 MHz pixel clock, so both come from one
bitstream with different constants. That is a legitimate 1080p claim and it is
in spec with real margin.

## Layout

```
v1/
  rtl/          video_timing, pattern_gen, rgb2luma, line_buffer, window_3x3,
                sobel, lut3d + lut_bank + lerp8, blend, delay_line,
                video_pipeline, tmds_encoder, serializer_10to1, dvi_tx,
                clk_gen, reset_sync, uart_rx, ctrl_regs, seven_seg,
                freq_counter, top
  sim/          one testbench per module, a full-frame regression, and
                behavioural models of the Xilinx primitives
  model/        golden.py (bit-exact reference), make_lut.py, gen_vectors.py,
                png2hex.py, hex2png.py, compare.py
  constraints/  boolean.xdc  (pin placeholders -- fill from the vendor XDC)
  scripts/      build.tcl, program.tcl
  docs/         timing.md, verification.md, bringup.md, notes-on-the-spec.md
```

## Verification

Every module has a testbench, and the whole pipeline is compared against a
Python golden model that is bit-exact with the RTL — including its truncation,
because floating-point interpolation in Python against integer in Verilog gives
1 LSB differences everywhere and then you cannot tell a bug from rounding.

| Testbench | Proves |
|---|---|
| `tb_tmds_encoder` | ≤5 transitions, bounded disparity, control tokens, and `decode(encode(x)) == x` over 6,400 words |
| `tb_dvi_tx` | Serialise → deserialise round trip; catches bit-order and channel-alignment errors |
| `tb_video_timing` | Exact frame arithmetic for all three modes |
| `tb_line_buffer` | Rows exactly one and two line periods apart |
| `tb_sobel` | Hand-checkable kernel responses |
| `tb_lut3d` | 5,185 pixels × 7 grades against the model |
| `tb_pipeline` | A whole frame, four modes, two grades, pixel for pixel |

[`docs/verification.md`](docs/verification.md) has the details;
[`docs/bringup.md`](docs/bringup.md) is the black-screen decision tree.

## Where this deviates from the design document

The reference RTL in the design document is described there as "not tested on
hardware", and it isn't. Six substantive corrections came out of making it
simulate, each caught by a named test — the signed-shift bug in the lerp, the
per-bank LUT address carry, the permutation pipeline stage, the line-buffer
skew, two SystemVerilog keyword collisions, and the identity LUT's 1 LSB
deviation at the top node. They are written up in
[`docs/notes-on-the-spec.md`](docs/notes-on-the-spec.md) with the arithmetic.

One deliberate architectural difference: the pipeline is free-running with
`H_TOTAL`-long line delays rather than de-gated with `H_ACT`-long ones. It
costs about 4 BRAM36 of the 75 available and makes every delay in the design a
plain cycle count, so alignment is verifiable by arithmetic instead of by
inspection.

## Status against the milestone ladder

| Milestone | State |
|---|---|
| M0–M2 toolchain, display, simulation | flow is scripted; `make` runs the lot |
| M3 640×480 over HDMI | RTL complete, `MODE=0`; needs real pins to build |
| M4 720p60 | `MODE=1`, default; 1080p30 is `MODE=2` |
| M5 source material | 8 procedural patterns with vsync-driven animation |
| M6 3D LUT | 8-bank parity storage, trilinear, 7 grades, verified bit-exact |
| M7 line buffers and Sobel | verified against the model, borders included |
| M8 runtime control | switches, buttons, UART register writes |
| M9 polish | docs, scripted build with timing gate |

Not done: a stored test image in BRAM (`image_rom`), the XADC potentiometer
threshold, and runtime LUT upload over UART — the register interface is there,
the BRAM write path is not. The clock-domain-crossing work that last one needs
is written up in the design document's stretch goals.
