"""PNG -> hex, one 24-bit RRGGBB word per line, raster order.

    python3 model/png2hex.py in.png out.hex [--width W] [--height H]

``$readmemh`` reads this straight into a ``reg [23:0]`` array.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def png_to_hex(src: Path, dst: Path, width: int | None = None, height: int | None = None) -> tuple[int, int]:
    img = Image.open(src).convert("RGB")
    if width and height:
        img = img.resize((width, height), Image.LANCZOS)
    with dst.open("w") as handle:
        for px in img.getdata():
            handle.write(f"{px[0]:02x}{px[1]:02x}{px[2]:02x}\n")
    return img.size


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("src", type=Path)
    parser.add_argument("dst", type=Path)
    parser.add_argument("--width", type=int)
    parser.add_argument("--height", type=int)
    args = parser.parse_args()
    w, h = png_to_hex(args.src, args.dst, args.width, args.height)
    print(f"{args.src} -> {args.dst} ({w}x{h}, {w * h} pixels)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
