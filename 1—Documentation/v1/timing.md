# Clocking, video timing, and why 1080p60 is not on the table

## Why 1080p60 cannot work on this part

DVI sends 10 bits per pixel per channel, so the serial rate is ten times the
pixel clock and the SERDES needs a clock at five times it (DDR).

| Mode | Pixel clock | Serial rate/channel | Required 5x clock |
|---|---|---|---|
| 640x480p60 | 25.175 MHz | 251.75 Mb/s | 125.9 MHz |
| 1280x720p60 | 74.25 MHz | 742.5 Mb/s | 371.25 MHz |
| 1920x1080p30 | 74.25 MHz | 742.5 Mb/s | 371.25 MHz |
| **1920x1080p60** | **148.5 MHz** | **1485 Mb/s** | **742.5 MHz** |

Against the -1 speed grade limits:

| Resource | -1 limit | 1080p60 needs |
|---|---|---|
| `BUFG` | 464 MHz | 742.5 MHz — 60% over |
| `BUFIO` | 600 MHz | 742.5 MHz — 24% over |
| `BUFR` | 315 MHz | 742.5 MHz |
| `OSERDESE2` DDR | 950 Mb/s | 1485 Mb/s — 56% over |

There is no clock buffer on the device that can carry 742.5 MHz. This is not a
marginal overclock; the clock is unroutable. Vendor IP and forum posts claiming
1080p60 on -1 parts are out of spec on two independent axes, and "works on my
bench at room temperature" is not a property you want in the headline claim of
a portfolio project.

**720p60 and 1080p30 share the 74.25 MHz pixel clock**, so both come from one
bitstream with different timing constants. That is the honest way to put
"1080p" on this project.

## MMCM settings

720p60 / 1080p30:

| Parameter | Value | Check |
|---|---|---|
| `CLKIN1_PERIOD` | 10.000 | 100 MHz board oscillator |
| `DIVCLK_DIVIDE` (D) | 5 | PFD = 100/5 = 20 MHz, inside 10–450 |
| `CLKFBOUT_MULT_F` (M) | 37.125 | VCO = 742.5 MHz, inside 600–1200 |
| `CLKOUT0_DIVIDE_F` | 2 | 371.25 MHz — `clk_5x` |
| `CLKOUT1_DIVIDE` | 10 | 74.25 MHz — `clk_pix` |

640x480p60:

| Parameter | Value | Check |
|---|---|---|
| `DIVCLK_DIVIDE` | 1 | PFD = 100 MHz |
| `CLKFBOUT_MULT_F` | 10.000 | VCO = 1000 MHz |
| `CLKOUT0_DIVIDE_F` | 8 | 125 MHz |
| `CLKOUT1_DIVIDE` | 40 | 25 MHz (25.175 nominal; every monitor accepts 25.0) |

The 742.5 MHz VCO is internal to the MMCM and entirely legal — VCOs run far
faster than clock buffers. What must never happen is that frequency reaching a
`BUFG`.

Both clocks come from the **same MMCM**. Two MMCMs drift relative to each other
and the OSERDES output becomes garbage.

## Video timing constants

| | 640x480p60 | 1280x720p60 | 1920x1080p30 |
|---|---|---|---|
| Pixel clock | 25.175 MHz | 74.25 MHz | 74.25 MHz |
| H active | 640 | 1280 | 1920 |
| H front porch | 16 | 110 | 88 |
| H sync | 96 | 40 | 44 |
| H back porch | 48 | 220 | 148 |
| **H total** | **800** | **1650** | **2200** |
| V active | 480 | 720 | 1080 |
| V front porch | 10 | 5 | 4 |
| V sync | 2 | 5 | 5 |
| V back porch | 33 | 20 | 36 |
| **V total** | **525** | **750** | **1125** |
| Sync polarity | negative | positive | positive |

`tb_video_timing` asserts the arithmetic rather than trusting the table:
1650 × 750 × 60 = 74,250,000 and 2200 × 1125 × 30 = 74,250,000.

## Pipeline latency

Every module exports its latency as a register count, and `video_pipeline`
derives the delays from those rather than hardcoding numbers.

| Stage | Registers |
|---|---|
| `pattern_gen` | 1 |
| `rgb2luma` | 1 |
| `line_buffer` alignment | 2 |
| `window_3x3` | 1 |
| `sobel` | 2 |
| `lut3d` | 6 |
| `blend` | 1 |
| `tmds_encoder` | 2 |

The 3x3 window centres on a pixel one line and one column behind the pixel
entering the line buffer, so the whole Sobel branch trails by `H_TOTAL + 1`
cycles on top of its register count. The graded branch is delayed to match
through one line delay, and the sync signals through a shift register of the
same total depth:

```
sync   : H_TOTAL + 7
graded : lut3d (6) + line delay (H_TOTAL + 1)
sobel  : luma (1) + line buffer (2) + window (1) + sobel (2) + spatial (H_TOTAL + 1)
```

A mismatch here is the "image shifted by a few pixels" or "shifted by a line or
two" symptom, and it is exactly what the full-frame regression catches.

## Where the timing path will be

At 74.25 MHz the clock period is 13.47 ns, and the worst path will almost
certainly be the TMDS encoder's running-disparity feedback loop: register →
comparators → adders → same register.

This implementation already applies the section 11 fix — stage 1 (transition
minimisation and the population counts) is registered separately, because it
depends only on the input byte and not on the disparity. That halves the depth
of the feedback path at the cost of one cycle of latency, which is irrelevant
for video.

If it still fails, precompute both candidate next-disparity values in the
earlier stage and make the final stage a pure mux.

## Expected resource use

| Block | BRAM36 | DSP | LUTs (approx) |
|---|---|---|---|
| Line buffers (2 × 8-bit luma, H_TOTAL deep) | 1 | 0 | ~100 |
| RGB delay match (48-bit, H_TOTAL deep) | 3 | 0 | ~50 |
| 3D LUT (8 banks × 729 × 24) | 4 | 0 | ~200 |
| Trilinear interpolation (7 × 3 lerps) | 0 | 0–21 | ~600 |
| Sobel + window + luma | 0 | 0–3 | ~700 |
| TMDS encoders ×3 | 0 | 0 | ~450 |
| Timing, pattern, control, display | 0 | 0 | ~1,200 |
| **Total** | **~8** | **~24** | **~3,300** |
| **Available (XC7S50)** | 75 | 120 | ~32,600 |

The BRAM figure is higher than the design document's estimate because the line
delays here are `H_TOTAL` long rather than `H_ACT` long — the cost of the
free-running pipeline, and worth it (see `docs/notes-on-the-spec.md`). Roughly
11% of BRAM either way.
