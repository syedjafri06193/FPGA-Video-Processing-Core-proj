"""Compare two hex images and report the first mismatch with its coordinates.

    python3 model/compare.py got.hex expected.hex --width 64 --height 64

A script that prints ``first mismatch at (x=1, y=2): got 0x3f3f3f expected
0x000000`` will save you days (design.md section 10.3).  Exits non-zero on any
difference so it can gate a build.
"""

from __future__ import annotations

import argparse
from pathlib import Path


def read_hex(path: Path) -> list[int]:
    return [int(w, 16) for w in path.read_text().split() if w.strip()]


def rgb(value: int) -> tuple[int, int, int]:
    return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)


def compare(
    got_path: Path,
    exp_path: Path,
    width: int,
    height: int,
    *,
    tolerance: int = 0,
    max_report: int = 5,
    label: str = "",
) -> int:
    got = read_hex(got_path)
    exp = read_hex(exp_path)
    name = label or got_path.name

    if len(got) != len(exp):
        print(
            f"FAIL {name}: pixel count {len(got)} != expected {len(exp)}"
            f" ({width}x{height} = {width * height})"
        )
        if len(got) < len(exp):
            print("     short output usually means the pipeline dropped lines --"
                  " check de alignment at the end of the frame")
        return 1

    mismatches = []
    for i, (g, e) in enumerate(zip(got, exp)):
        if g == e:
            continue
        if tolerance and all(abs(a - b) <= tolerance for a, b in zip(rgb(g), rgb(e))):
            continue
        mismatches.append((i, g, e))
        if len(mismatches) >= max_report:
            break

    if not mismatches:
        note = f" (tolerance {tolerance} LSB)" if tolerance else ""
        print(f"PASS {name}: {len(got)} pixels identical{note}")
        return 0

    total = sum(
        1
        for g, e in zip(got, exp)
        if g != e and not (tolerance and all(abs(a - b) <= tolerance for a, b in zip(rgb(g), rgb(e))))
    )
    print(f"FAIL {name}: {total} of {len(got)} pixels differ")
    for i, g, e in mismatches:
        x, y = i % width, i // width
        print(
            f"     mismatch at (x={x}, y={y}): got 0x{g:06x} expected 0x{e:06x}"
            f"  delta={tuple(a - b for a, b in zip(rgb(g), rgb(e)))}"
        )
    first_x, first_y = mismatches[0][0] % width, mismatches[0][0] // width
    if first_y == 0 or first_x == 0:
        print("     first mismatch is on the top/left border -- check border handling")
    elif total == len(got):
        print("     every pixel differs -- check channel order or a whole-frame offset")
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("got", type=Path)
    parser.add_argument("expected", type=Path)
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    parser.add_argument("--tolerance", type=int, default=0)
    parser.add_argument("--label", default="")
    args = parser.parse_args()
    return compare(
        args.got,
        args.expected,
        args.width,
        args.height,
        tolerance=args.tolerance,
        label=args.label,
    )


if __name__ == "__main__":
    raise SystemExit(main())
