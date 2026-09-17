"""Golden reference model (design.md section 10.1).

Every function here is **bit-exact with the RTL**, which is the only way the
comparison is worth anything.  Floating-point interpolation in Python against
integer interpolation in Verilog gives 1-LSB differences everywhere, and you
cannot tell a real bug from rounding.

The three places that have to match exactly:

* luma is ``(77R + 150G + 29B) >> 8`` -- truncating, not rounding;
* Sobel is ``|Gx| + |Gy|`` clamped to 255, with a **black one-pixel border**,
  because that is what the RTL does at the frame edge;
* every lerp is ``a + ((b - a) * f >> 4)`` with an *arithmetic* shift, applied
  in the order B, then G, then R.

That last one is subtle: ``>>`` on a negative number floors in both Python and
Verilog's ``>>>``, so the two agree -- but only if the RTL uses a signed shift.
The reference RTL in the design document does not (it slices ``p[12:4]`` out of
a signed product and adds it as an unsigned value), which is a real bug for any
pixel where the interpolation goes downhill.  See docs/notes-on-the-spec.md.
"""

from __future__ import annotations

import numpy as np

LUT_NODES = 17


# --------------------------------------------------------------------- luma


def rgb2luma(img: np.ndarray) -> np.ndarray:
    """Y = (77R + 150G + 29B) >> 8, truncating.

    Matches ``rtl/rgb2luma.v``.  The weights are 0.299/0.587/0.114 scaled by
    256 and rounded; their sum is 256 exactly, so the result cannot exceed 255.
    """
    w = np.array([77, 150, 29], dtype=np.int32)
    return ((img.astype(np.int32) @ w) >> 8).astype(np.uint8)


# -------------------------------------------------------------------- sobel

KX = np.array([[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]], dtype=np.int32)
KY = np.array([[-1, -2, -1], [0, 0, 0], [1, 2, 1]], dtype=np.int32)


def sobel(luma: np.ndarray, threshold: int = 64) -> tuple[np.ndarray, np.ndarray]:
    """Return ``(magnitude, edge_flag)``.

    ``|Gx| + |Gy|`` overestimates ``sqrt(Gx^2 + Gy^2)`` by up to 41%, which is
    visually irrelevant and saves a square root.

    The border stays black.  The RTL cannot see outside the frame, and the
    choice has to be identical here or every comparison fails on the edge and
    you chase a phantom bug.
    """
    h, w = luma.shape
    mag = np.zeros((h, w), dtype=np.uint8)
    flag = np.zeros((h, w), dtype=bool)
    src = luma.astype(np.int32)

    # Vectorised, but arithmetically identical to the per-pixel loop.
    win = np.lib.stride_tricks.sliding_window_view(src, (3, 3))
    gx = (win * KX).sum(axis=(-2, -1))
    gy = (win * KY).sum(axis=(-2, -1))
    total = np.abs(gx) + np.abs(gy)
    mag[1:h - 1, 1:w - 1] = np.minimum(total, 255).astype(np.uint8)
    flag[1:h - 1, 1:w - 1] = total > threshold
    return mag, flag


# ---------------------------------------------------------------------- LUT


def lerp8(a: np.ndarray, b: np.ndarray, f: np.ndarray | int) -> np.ndarray:
    """``a + ((b - a) * f >> 4)`` -- exactly what ``rtl/lerp8.v`` computes."""
    a = a.astype(np.int32)
    b = b.astype(np.int32)
    return (a + (((b - a) * f) >> 4)).astype(np.int32)


def identity_lut() -> np.ndarray:
    """The single most useful debugging tool in the project.

    Node *i* represents input value 16*i; node 16 represents 256, clamped to
    255.  Feeding this through the pipeline must reproduce the input exactly.
    """
    lut = np.zeros((LUT_NODES, LUT_NODES, LUT_NODES, 3), dtype=np.uint8)
    axis = np.minimum(np.arange(LUT_NODES) * 16, 255)
    lut[..., 0] = axis[:, None, None]
    lut[..., 1] = axis[None, :, None]
    lut[..., 2] = axis[None, None, :]
    return lut


def lut3d_apply(img: np.ndarray, lut: np.ndarray) -> np.ndarray:
    """Trilinear 3D LUT, integer arithmetic, in the RTL's lerp order.

    Interpolation order is B, then G, then R -- the same tree the hardware
    builds (4 lerps along B, 2 along G, 1 along R).  Order matters at the LSB
    because each stage truncates.
    """
    if lut.shape != (LUT_NODES, LUT_NODES, LUT_NODES, 3):
        raise ValueError(f"expected a {LUT_NODES}^3 LUT, got {lut.shape}")

    idx = (img >> 4).astype(np.int32)      # 0..15
    frac = (img & 0xF).astype(np.int32)    # 0..15
    ri, gi, bi = idx[..., 0], idx[..., 1], idx[..., 2]
    rf, gf, bf = frac[..., 0], frac[..., 1], frac[..., 2]

    def corner(dr: int, dg: int, db: int) -> np.ndarray:
        return lut[ri + dr, gi + dg, bi + db].astype(np.int32)

    # 4 lerps along B
    l00 = lerp8(corner(0, 0, 0), corner(0, 0, 1), bf[..., None])
    l01 = lerp8(corner(0, 1, 0), corner(0, 1, 1), bf[..., None])
    l10 = lerp8(corner(1, 0, 0), corner(1, 0, 1), bf[..., None])
    l11 = lerp8(corner(1, 1, 0), corner(1, 1, 1), bf[..., None])
    # 2 along G
    m0 = lerp8(l00, l01, gf[..., None])
    m1 = lerp8(l10, l11, gf[..., None])
    # 1 along R
    out = lerp8(m0, m1, rf[..., None])
    return out.astype(np.uint8)


# ----------------------------------------------------------------- pipeline

MODE_PASS = 0
MODE_LUT = 1
MODE_EDGES = 2
MODE_OVERLAY = 3


def pipeline(
    img: np.ndarray,
    lut: np.ndarray,
    *,
    mode: int = MODE_OVERLAY,
    threshold: int = 64,
    lut_bypass: bool = False,
) -> np.ndarray:
    """The whole video path, as the hardware computes it.

    Note the branch structure (section 3.2): Sobel runs on luma derived from
    the **ungraded** image, because grading can crush the local contrast the
    gradient operator depends on.  The two branches rejoin at the blend.
    """
    graded = img if lut_bypass else lut3d_apply(img, lut)
    mag, flag = sobel(rgb2luma(img), threshold)

    if mode == MODE_PASS:
        return img.copy()
    if mode == MODE_LUT:
        return graded
    if mode == MODE_EDGES:
        return np.repeat(mag[:, :, None], 3, axis=2)
    if mode == MODE_OVERLAY:
        out = graded.copy()
        out[flag] = 255
        return out
    raise ValueError(f"unknown mode {mode}")


# -------------------------------------------------------------------- banks


def emit_banks(lut: np.ndarray) -> list[np.ndarray]:
    """Split a 17^3 LUT into the 8 parity banks the RTL reads in parallel.

    The eight corners of any interpolation cube are
    ``(r+a, g+b, b+c)`` for a,b,c in {0,1}.  Adding one flips the LSB, so the
    eight corners always land in eight *different* banks by construction --
    which is what makes a single-cycle 8-corner read possible from single-port
    BRAMs (section 5).
    """
    banks = [np.zeros((729, 3), dtype=np.uint8) for _ in range(8)]
    for r in range(LUT_NODES):
        for g in range(LUT_NODES):
            for b in range(LUT_NODES):
                bank = ((r & 1) << 2) | ((g & 1) << 1) | (b & 1)
                addr = (r >> 1) * 81 + (g >> 1) * 9 + (b >> 1)
                banks[bank][addr] = lut[r, g, b]
    return banks


def bank_of(r: int, g: int, b: int) -> int:
    return ((r & 1) << 2) | ((g & 1) << 1) | (b & 1)


def addr_of(r: int, g: int, b: int) -> int:
    return (r >> 1) * 81 + (g >> 1) * 9 + (b >> 1)
