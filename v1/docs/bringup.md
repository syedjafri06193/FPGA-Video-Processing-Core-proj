# Bring-up and debugging

The general principle first, because it saves more time than everything else
here put together: **every time you are tempted to "just try it on the board",
ask whether simulation could answer the same question in thirty seconds.**
Usually it can. The board confirms that something which already works in
simulation also works in silicon; it is a terrible place to find logic bugs.

```
make            # every testbench, plus the full-frame comparison, in seconds
make wave TB=tb_pipeline && gtkwave build/tb_pipeline.vcd
```

## Before the first bitstream

1. Fill in the `<PIN>` placeholders in `constraints/boolean.xdc` from Real
   Digital's master XDC. `scripts/build.tcl` refuses to build until you do.
2. Confirm the part string is `xc7s50csga324-1`. The trailing `-1` is the speed
   grade; building against `-2` will close timing on a design that does not
   work on your board.
3. Get the vendor's own HDMI demo running unmodified first, if there is one.
   Debugging your own TMDS encoder while not knowing whether your cable,
   monitor and constraints are good is a bad time.
4. Build at 640x480 first: `vivado -mode batch -source scripts/build.tcl
   -tclargs 480p`. A 25 MHz pixel clock closes timing trivially, so a wrong
   picture is a logic bug rather than a timing bug. One variable at a time.

## Black screen, or "no signal"

In order. Do not skip.

| # | Check | How |
|---|---|---|
| 1 | Does the MMCM lock? | `led[0]`. Nothing downstream works until it does. |
| 2 | Is the pixel clock the frequency you think? | Hold `btn[1]`: the seven-segment shows the measured pixel clock in hex. 74.25 MHz is `0x46CDF80`, 25 MHz is `0x17D7840`. A wrong MMCM setting is common and silent. |
| 3 | Is the frame counter advancing? | Release `btn[1]`: the display shows frames. Stuck means the timing generator is stuck. |
| 4 | Is the clock channel serialising? | Some monitors report "unsupported mode" if they see a TMDS clock at all. Total silence often means a dead clock channel. |
| 5 | Bit order | TMDS is LSB first. `tb_dvi_tx` proves the RTL does this; a mismatch here would mean an edited serializer. |
| 6 | Channel order | Blue must be channel 0 — it carries hsync and vsync in its control word. Swapped colours mean R/B crossed; *no sync at all* usually means blue is on the wrong pin. |
| 7 | Sync polarity | 640x480 wants negative, 720p and 1080p positive. Wrong polarity often gives "out of range". |
| 8 | Is `ctrl` `{vsync, hsync}` and not the other way round? | Easy to reverse, and it produces exactly this symptom. |
| 9 | Try another monitor | A cheap old 1080p TV is usually more forgiving than a modern high-end monitor. |
| 10 | Try another cable | Yes, really. |

## Picture appears but is wrong

| Symptom | Likely cause | Where to look |
|---|---|---|
| Shifted horizontally by a few pixels | `de` not delay-matched to the data | `video_pipeline` latency constants; `make regress` would have caught it |
| Shifted vertically by a line or two | Line-buffer latency unaccounted for | same, and `tb_line_buffer` |
| Diagonal tearing / sheared | `H_TOTAL` wrong | `rtl/video_modes.vh` |
| Rolls vertically | `V_TOTAL` wrong | same |
| Right geometry, wrong colours | Channel assignment swapped | XDC, and `dvi_tx` channel map |
| Sparkle, random pixel noise | **Timing violation** | `build/timing.rpt` — do not ignore this |
| One-pixel garbage line at the top or left | Border handling in the convolution | `sobel`'s `border` input, `video_pipeline`'s border logic |
| Colours slightly off after the LUT | Interpolation rounding, or a bank permutation error | `tb_lut3d`, and `docs/notes-on-the-spec.md` items 1–3 |
| Vertical banding in LUT output | LUT address arithmetic — the ×81/×9 stride | `docs/notes-on-the-spec.md` item 2 |
| Edges look doubled or smeared | Sobel running on graded rather than raw luma | `video_pipeline` branch wiring |

## Reading the timing report

`build/timing.rpt`, or `Reports → Timing → Report Timing Summary`:

* **WNS** (setup) and **WHS** (hold) must both be ≥ 0. `scripts/build.tcl`
  fails the build otherwise, on purpose.
* **Failing endpoints: 1** is usually one path you can fix. **5,000** means a
  missing clock constraint or an unnoticed clock domain crossing.
* **Clock interaction report**: `clk_pix` and `clk_5x` must appear as related.
  If they show as asynchronous, Vivado is not analysing the OSERDES paths at
  all, and a passing report means nothing.

## The ILA

`IP Catalog → Debug & Verification → ILA`, or mark signals with
`(* mark_debug = "true" *)`. Triggers worth setting up:

* `vsync` rising edge, capture the first 1024 pixels of a frame;
* `de` rising with `y == 100`, to capture one specific scanline;
* a comparison between the pipeline output and an expected constant.

It costs BRAM (there is plenty) and can perturb timing. Remove it before the
final build.

## Runtime controls

Switches, once a picture is up:

```
sw[1:0]   mode: 00 passthrough, 01 LUT, 10 edges, 11 overlay
sw[2]     LUT bypass (A/B the grade live)
sw[3]     glow overlay instead of hard white edges
sw[6:4]   pattern select
sw[7]     freeze animation
sw[15:8]  edge threshold
btn[0]    force threshold to 0x40 -- the way back from nonsense switches
btn[1]    seven-segment shows the measured pixel clock instead of frames
```

Over UART (115200 8N1), two bytes per command, register then value:

```
00 03     mode = overlay
01 40     threshold = 0x40
02 01     flags: bit0 LUT bypass, bit1 glow, bit2 freeze
03 02     pattern = 2
04 00     hand control back to the switches
```

The switches stay in charge until the first UART command arrives, so the board
is usable with nothing plugged into it.
