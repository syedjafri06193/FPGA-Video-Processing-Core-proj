# Notes on the design document

The reference RTL in `Documentation/README.md` is described there as
"reference-quality but **not tested on hardware** ... a starting point to
understand and adapt, not a drop-in library."  Taking that at its word, here is
everything that changed on the way to something that simulates correctly, and
why.  Each one is caught by a named testbench, so none of it is an opinion.

---

## 1. `lerp8` adds a signed product as an unsigned value

**Section 9.6.** The reference lerp is:

```verilog
wire signed [8:0]  d = $signed({1'b0, b}) - $signed({1'b0, a});
wire signed [12:0] p = d * $signed({1'b0, f});
always @(posedge clk)
    y <= a + p[12:4];          // a + (b-a)*f/16
```

`p[12:4]` is a *bit slice*, so it is unsigned. When `b < a` the product is
negative and the slice is a large positive number, so the interpolation runs
the wrong way — on roughly half of all pixels, for any grade that is not the
identity. The comment says `a + (b-a)*f/16`; the code does not.

The fix is to keep it signed all the way through:

```verilog
wire signed [9:0]  d = $signed({2'b00, b}) - $signed({2'b00, a});
wire signed [13:0] p = d * $signed({1'b0, f});
wire signed [9:0]  delta = p[13:4];        // arithmetic >>> 4
always @(posedge clk) y <= $signed({2'b00, a}) + delta;
```

Truncation toward negative infinity is kept deliberately, because Python's `>>`
floors too and the golden model has to match bit for bit.

*Caught by:* `tb_lut3d` on any non-identity grade.

---

## 2. "All eight banks receive the same address" — only when every index is even

**Section 5, "Why the 3D LUT is only 4 BRAM36".** The parity-banking trick is
right and it is the good idea in the design: the eight corners of the
interpolation cube always land in eight different banks, so one read from each
gets all eight in a single cycle.

The address claim does not follow, though. The address of a node is

```
addr = (R >> 1)*81 + (G >> 1)*9 + (B >> 1)
```

and when `R` is odd, `(R+1) >> 1` is `(R >> 1) + 1` — a different row. Feeding
every bank the same address returns the correct corner only when all three
indices are even, which is one pixel in eight.

Each bank needs the base address plus a per-axis carry that depends only on its
own parity bit and the index's LSB:

```verilog
wire carry_r = odd_r & (bank_parity_r == 0);   // odd index, even-side bank
assign addr = base + 81*carry_r + 9*carry_g + carry_b;
```

Eight small adders on a shared base; the BRAM cost is unchanged.

*Caught by:* `tb_lut3d`, which fails on about 7 of every 8 pixels with the
original version.

---

## 3. The bank permutation needs the parity from a cycle earlier

Not an error in the document — it does not show this stage in full — but the
trap is real and it is the kind that produces a *nearly* right picture.

The permute reads `q[...]` indexed by `{ri[0], gi[0], bi[0]}`. Those bits must
belong to the pixel whose bank outputs are arriving *now*, which is one cycle
older than the register feeding the address, because the BRAM read sits between
them. Using the address-stage parity permutes each pixel's corners with its
successor's parity: correct whenever consecutive pixels share parity, so it
looks fine on flat colour and fails on every gradient.

*Caught by:* `tb_lut3d`; it was the last bug standing when this was built.

---

## 4. The line buffer's one-cycle skew

**Section 9.7.** The document writes the second buffer with the value read from
the first on the previous cycle, notes the resulting column skew, and leaves
fixing it as an exercise.

Rather than carrying a fix-up offset, each line delay here is a self-contained
FIFO addressed by its own counter, which wraps after exactly one line period.
The value read back *is* the pixel from the line above, with nothing to
correct; row alignment becomes plain latency matching.

*Caught by:* `tb_line_buffer`, which pushes a ramp of `(y, x)` coordinates and
asserts the three rows are exactly one and two line periods apart.

---

## 5. `checker` and `clocking` are SystemVerilog keywords

The document's `pattern_gen` uses a wire named `checker`, and the natural name
for the MMCM wrapper is `clocking`. Both are reserved words in SystemVerilog
(SVA checkers, and clocking blocks), so any tool in `-sv` mode — including
Vivado when the file extension says SystemVerilog — rejects them. Renamed here
to `checkerboard` and `clk_gen`.

---

## 6. The identity LUT is not quite the identity

**Section 9.6** says the identity LUT is "your single most useful debugging
tool", and section 10.4 asks for "identity LUT → output must equal input for
all 2^24 inputs". It is very nearly true, and the exception is worth knowing
before it looks like a bug.

Node 16 represents input value 256, stored as 255. For inputs at or below 240
the interpolation is exact. Above 240 it interpolates toward 255 instead of
256, so the output can be 1 LSB low: `0xFF` comes back as `0xFE`.

The test asserts exactness below 240 and a 1 LSB tolerance above it, rather
than pretending the discrepancy is not there.

*Caught by:* `tb_lut3d +grade=identity`.

---

## 7. Two conventions for "latency", one pixel apart

A pipeline with N registers presents a value sampled on edge A at edge
A + (N−1), because the first register captures *at* A. So "number of pipeline
stages" and "edges to wait before checking" differ by one.

Mixing them up shifts the image by one pixel — which is item one in the
document's own "picture appears but is wrong" table. Every module here exports
its latency as a register count, `delay_line #(.DEPTH(N))` matches a
register count, and the testbenches say which convention they are using.

---

## 8. Things the document got right that were tempting to change

* **Sobel on ungraded luma, in parallel with the LUT.** It is more tempting
  than it looks to chain them and save the delay-matching line. The document is
  right: grading crushes the local contrast the gradient operator needs.
* **`|Gx| + |Gy|`.** Overestimates by up to 41%, invisible, saves a square root.
* **DVI signalling rather than full HDMI.** No data islands, no audio, no
  InfoFrames; every display accepts it.
* **Registered module boundaries throughout.** The reason timing closure is not
  a fight at 74.25 MHz.
* **720p60 rather than 1080p60.** 742.5 MHz exceeds every clock buffer on a -1
  part. The arithmetic is in `docs/timing.md` and it is not close.
