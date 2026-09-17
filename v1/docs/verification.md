# Verification

Debugging video by looking at a monitor is close to useless: a single
off-by-one in a line buffer produces an image that looks subtly wrong in a way
you cannot localise. So the whole flow is arranged around comparing full frames
against a Python model that is bit-exact with the RTL.

```
make            # everything below, in about twenty seconds
```

## The golden model

`model/golden.py` implements the same arithmetic as the RTL, deliberately
including its truncation:

| Operation | Both sides compute |
|---|---|
| Luma | `(77R + 150G + 29B) >> 8`, truncating |
| Sobel | `|Gx| + |Gy|`, clamped to 255, black one-pixel border |
| Lerp | `a + ((b - a) * f >> 4)`, arithmetic shift, floored |
| LUT order | 4 lerps along B, then 2 along G, then 1 along R |

Using floating-point interpolation in Python and integer in Verilog gives 1 LSB
differences everywhere, and then you cannot tell a real bug from rounding. That
is why the model is written this way and not the obvious way.

## What each testbench proves

| Testbench | What it asserts |
|---|---|
| `tb_delay_line` | Depths 0, 1, 3, 7, including the pass-through case, and states the latency convention explicitly |
| `tb_video_timing` | Exactly `H_TOTAL × V_TOTAL` cycles per frame; `de` high exactly `H_ACT × V_ACT` times; sync width, count and polarity per mode; the pixel-clock arithmetic for all three modes |
| `tb_tmds_encoder` | ≤5 transitions per encoded word, bounded running disparity, correct control tokens during blanking, and **decode(encode(x)) == x** over 6,400 words |
| `tb_dvi_tx` | Serialise then deserialise: word alignment recovered from the clock channel, all three data channels agree on it, pairs are complementary. Catches bit-order and channel-phase errors |
| `tb_line_buffer` | A ramp of `(y, x)` coordinates comes out with rows exactly one and two line periods apart |
| `tb_sobel` | Hand-checkable responses: flat field, vertical edge, horizontal edge, centre impulse, corner impulse, a step that does not clamp, threshold boundary, and the border override |
| `tb_lut3d` | 5,185 stimulus pixels against the model, for each of seven grades; identity exact below 240 and within 1 LSB above |
| `tb_uart_rx` | A byte, back-to-back bytes, a framing error, and a glitch on the idle line that must not decode |
| `tb_top_smoke` | MMCM locks, `de` asserts for the right fraction of the time, the pipeline emits non-black pixels, the serialisers toggle |
| `tb_pipeline` | A whole 64×64 frame through the real pipeline, compared pixel for pixel against the model, in all four modes and two grades |

## The full-frame regression

`make regress` streams the test image with realistic blanking — so the line
buffers see the same line boundaries they will see on hardware — and compares
the output against the model:

```
PASS mode=pass grade=identity: 4096 pixels identical
PASS mode=lut grade=identity: 4096 pixels identical
PASS mode=edges grade=identity: 4096 pixels identical
PASS mode=overlay grade=identity: 4096 pixels identical
PASS mode=pass grade=teal_orange: 4096 pixels identical
...
```

On a mismatch it prints the coordinates, which is the entire point:

```
FAIL mode=overlay grade=warm: 118 of 4096 pixels differ
     mismatch at (x=1, y=2): got 0x3f3f3f expected 0x000000  delta=(63, 63, 63)
     first mismatch is on the top/left border -- check border handling
```

## The test image

`model/gen_vectors.py` builds a 64×64 image that exercises both branches at
once:

* hard vertical, horizontal and diagonal edges — Sobel's easy cases, and where
  a line-buffer off-by-one is obvious;
* a circle — curved edges;
* smooth ramps across the full RGB cube — the LUT's interesting input, and what
  shows banding if the address arithmetic is wrong;
* saturated corners including 255 on each channel — the LUT's top node;
* a single white pixel on black — the impulse response.

64×64 is deliberate. Simulating a real 720p frame would take hours, and every
bug these tests catch is visible at 64×64.

## Looking at a failure

```
make wave TB=tb_pipeline
gtkwave build/tb_pipeline.vcd

python3 model/hex2png.py build/output_mode3_warm.hex build/got.png --width 64 --height 64
python3 model/hex2png.py sim/vectors/expected_overlay_warm.hex build/want.png --width 64 --height 64
```

Coordinates first, waveform second, picture third — in that order, because
each one is slower than the last.

## What is not verified here

* **Timing closure.** That needs Vivado; `scripts/build.tcl` fails the build on
  negative slack so it cannot be ignored.
* **The real Xilinx primitives.** `sim/models/xilinx_prims.v` models the
  documented behaviour of `OSERDESE2`, `OBUFDS` and `MMCME2_BASE` — enough to
  prove bit order and alignment, not enough to prove the design meets I/O
  timing. Re-run the serialiser tests in `xsim` against the real libraries
  before trusting the bitstream.
* **The monitor.** No simulation tells you whether a particular display likes
  your sync polarity. That is what `docs/bringup.md` is for.
