"""Generate the simulation vectors: a test image, LUT banks, expected outputs.

    python3 model/gen_vectors.py [--width 64] [--height 64]

The test image is built to exercise both branches at once (section 9.5):

* hard vertical, horizontal and diagonal edges -- Sobel's easy cases, and the
  ones where an off-by-one in the line buffer is obvious;
* a circle -- curved edges, which catch gradient-direction mistakes;
* smooth ramps covering the full RGB cube -- the LUT's interesting input, and
  the thing that shows banding if the address arithmetic is wrong;
* saturated corners (0 and 255 on each channel) -- the LUT's top node, where
  the 256-vs-255 clamp lives;
* a single white pixel on black -- the known-response Sobel impulse test.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from golden import (  # noqa: E402
    lut3d_apply,
    MODE_EDGES,
    MODE_LUT,
    MODE_OVERLAY,
    MODE_PASS,
    pipeline,
)
from make_lut import GRADES, write_banks  # noqa: E402

MODE_NAMES = {
    MODE_PASS: "pass",
    MODE_LUT: "lut",
    MODE_EDGES: "edges",
    MODE_OVERLAY: "overlay",
}


def test_image(width: int = 64, height: int = 64) -> np.ndarray:
    img = np.zeros((height, width, 3), dtype=np.uint8)
    yy, xx = np.mgrid[0:height, 0:width]

    # Quadrant 1: smooth two-axis ramp (full cube coverage for the LUT).
    img[..., 0] = (xx * 255 // max(width - 1, 1)).astype(np.uint8)
    img[..., 1] = (yy * 255 // max(height - 1, 1)).astype(np.uint8)
    img[..., 2] = ((xx + yy) * 255 // max(width + height - 2, 1)).astype(np.uint8)

    # Hard vertical and horizontal edges.
    img[:, width // 3] = 255
    img[height // 3, :] = 0
    img[height // 2 :, width // 2 :] = np.array([20, 20, 20], dtype=np.uint8)

    # Diagonal edge.
    img[np.abs(xx - yy) < 2] = np.array([255, 255, 0], dtype=np.uint8)

    # Circle: curved edges.
    cx, cy, r = width * 0.7, height * 0.35, min(width, height) * 0.18
    inside = (xx - cx) ** 2 + (yy - cy) ** 2 < r**2
    img[inside] = np.array([255, 96, 32], dtype=np.uint8)

    # Saturated corners, including the LUT's top node.
    img[0, 0] = [0, 0, 0]
    img[0, width - 1] = [255, 255, 255]
    img[height - 1, 0] = [255, 0, 0]
    img[height - 1, width - 1] = [0, 0, 255]

    # Impulse: one white pixel on black, away from everything else.
    img[height - 6 : height - 3, 3:6] = 0
    img[height - 5, 4] = 255
    return img


def write_hex(path: Path, img: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    flat = img.reshape(-1, 3)
    with path.open("w") as handle:
        for px in flat:
            handle.write(f"{px[0]:02x}{px[1]:02x}{px[2]:02x}\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--width", type=int, default=64)
    parser.add_argument("--height", type=int, default=64)
    parser.add_argument("--threshold", type=int, default=64)
    parser.add_argument("--outdir", type=Path, default=Path("sim/vectors"))
    args = parser.parse_args()

    img = test_image(args.width, args.height)
    write_hex(args.outdir / "input.hex", img)
    print(f"input.hex           {args.width}x{args.height}")

    lut_dir = args.outdir / "lut"
    for name, builder in GRADES.items():
        write_banks(builder(), lut_dir, name)
    print(f"lut/                {len(GRADES)} grades x 8 banks")

    for lut_name in ("identity", "teal_orange"):
        lut = GRADES[lut_name]()
        for mode, mode_name in MODE_NAMES.items():
            out = pipeline(img, lut, mode=mode, threshold=args.threshold)
            write_hex(args.outdir / f"expected_{mode_name}_{lut_name}.hex", out)
        print(f"expected_*_{lut_name:<12} 4 modes at threshold {args.threshold}")

    # ---- LUT stimulus: a list of pixels chosen to stress the addressing ----
    # Full sweeps along each axis catch a wrong stride; the grey diagonal
    # catches a bank permutation error; the values around each node boundary
    # catch off-by-one in the index/fraction split; random coverage catches
    # everything else.
    rng = np.random.default_rng(5)
    pixels = []
    for v in range(256):
        pixels += [(v, 0, 0), (0, v, 0), (0, 0, v), (v, v, v)]
    for node in range(17):
        base = min(node * 16, 255)
        for d in (-1, 0, 1):
            v = min(max(base + d, 0), 255)
            pixels += [(v, v, v), (v, 255 - v, 128), (255, v, 0)]
    pixels += [(0, 0, 0), (255, 255, 255), (255, 0, 0), (0, 255, 0), (0, 0, 255),
               (240, 240, 240), (241, 17, 96), (15, 16, 17)]
    pixels += [tuple(int(c) for c in px) for px in rng.integers(0, 256, size=(4000, 3))]
    stim = np.array(pixels, dtype=np.uint8).reshape(-1, 1, 3)
    write_hex(args.outdir / "lut_stim.hex", stim)
    for lut_name in GRADES:
        out = lut3d_apply(stim, GRADES[lut_name]())
        write_hex(args.outdir / f"lut_stim_expected_{lut_name}.hex", out)
    print(f"lut_stim.hex        {len(pixels)} pixels x {len(GRADES)} grades")

    # The impulse response, on its own, as a hand-checkable case.
    impulse = np.zeros((8, 8, 3), dtype=np.uint8)
    impulse[4, 4] = 255
    write_hex(args.outdir / "impulse.hex", impulse)
    write_hex(
        args.outdir / "expected_impulse_edges.hex",
        pipeline(impulse, GRADES["identity"](), mode=MODE_EDGES, threshold=args.threshold),
    )
    print("impulse.hex         8x8 single white pixel")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
