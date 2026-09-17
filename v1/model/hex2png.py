"""hex -> PNG, the inverse of png2hex.py.

    python3 model/hex2png.py out.hex out.png --width 64 --height 64

Use it to *look* at what the RTL produced when a comparison fails and the
coordinates alone are not enough.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image


def hex_to_array(src: Path, width: int, height: int) -> np.ndarray:
    words = [line.strip() for line in src.read_text().split() if line.strip()]
    if len(words) < width * height:
        raise SystemExit(
            f"{src}: {len(words)} pixels, expected {width * height} "
            f"({width}x{height}) -- the pipeline may have dropped lines"
        )
    px = np.array([int(w, 16) for w in words[: width * height]], dtype=np.uint32)
    rgb = np.stack([(px >> 16) & 0xFF, (px >> 8) & 0xFF, px & 0xFF], axis=-1)
    return rgb.astype(np.uint8).reshape(height, width, 3)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("src", type=Path)
    parser.add_argument("dst", type=Path)
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    args = parser.parse_args()
    Image.fromarray(hex_to_array(args.src, args.width, args.height)).save(args.dst)
    print(f"{args.src} -> {args.dst} ({args.width}x{args.height})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
