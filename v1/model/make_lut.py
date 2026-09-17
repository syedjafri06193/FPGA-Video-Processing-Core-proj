"""Generate 17^3 LUTs and emit the eight `.mem` banks the RTL loads.

Reads a standard Adobe/Resolve ``.cube`` file, or builds a grade
programmatically.  Run with no arguments to write every built-in grade into
``sim/vectors/lut/``:

    python3 model/make_lut.py                    # all built-in grades
    python3 model/make_lut.py --cube film.cube --name film
    python3 model/make_lut.py --list
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from golden import LUT_NODES, emit_banks, identity_lut  # noqa: E402

AXIS = np.minimum(np.arange(LUT_NODES) * 16, 255).astype(np.float64) / 255.0


def _grid() -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Normalised (r, g, b) coordinates of every node, shaped (17,17,17)."""
    return np.meshgrid(AXIS, AXIS, AXIS, indexing="ij")


def _pack(r: np.ndarray, g: np.ndarray, b: np.ndarray) -> np.ndarray:
    out = np.stack([r, g, b], axis=-1)
    return np.clip(np.rint(out * 255.0), 0, 255).astype(np.uint8)


# ------------------------------------------------------------------- grades


def grade_identity() -> np.ndarray:
    return identity_lut()


def grade_warm() -> np.ndarray:
    """Lift the reds, pull the blues down slightly.  Golden-hour look."""
    r, g, b = _grid()
    return _pack(np.clip(r * 1.08 + 0.03, 0, 1), np.clip(g * 1.01, 0, 1), b * 0.92)


def grade_cool() -> np.ndarray:
    r, g, b = _grid()
    return _pack(r * 0.90, np.clip(g * 1.01, 0, 1), np.clip(b * 1.10 + 0.02, 0, 1))


def grade_teal_orange() -> np.ndarray:
    """The blockbuster grade: shadows to teal, highlights to orange."""
    r, g, b = _grid()
    luma = 0.299 * r + 0.587 * g + 0.114 * b
    shadow = np.clip(1.0 - luma * 1.6, 0, 1)
    high = np.clip((luma - 0.4) * 1.6, 0, 1)
    return _pack(
        np.clip(r + high * 0.16 - shadow * 0.06, 0, 1),
        np.clip(g + high * 0.05 + shadow * 0.02, 0, 1),
        np.clip(b - high * 0.10 + shadow * 0.14, 0, 1),
    )


def grade_high_contrast() -> np.ndarray:
    """S-curve on each channel: crushed shadows, rolled-off highlights."""
    r, g, b = _grid()

    def s_curve(x: np.ndarray) -> np.ndarray:
        return np.clip(x * x * (3.0 - 2.0 * x), 0, 1)

    return _pack(s_curve(r), s_curve(g), s_curve(b))


def grade_mono() -> np.ndarray:
    """Luma only -- useful for checking the LUT really is in the path."""
    r, g, b = _grid()
    y = 0.299 * r + 0.587 * g + 0.114 * b
    return _pack(y, y, y)


def grade_bleach_bypass() -> np.ndarray:
    """Desaturated, high contrast -- the classic film-lab look."""
    r, g, b = _grid()
    y = 0.299 * r + 0.587 * g + 0.114 * b
    mix = 0.55
    out = [np.clip(c * (1 - mix) + y * mix, 0, 1) for c in (r, g, b)]
    out = [np.clip((c - 0.5) * 1.35 + 0.5, 0, 1) for c in out]
    return _pack(*out)


GRADES = {
    "identity": grade_identity,
    "warm": grade_warm,
    "cool": grade_cool,
    "teal_orange": grade_teal_orange,
    "high_contrast": grade_high_contrast,
    "mono": grade_mono,
    "bleach_bypass": grade_bleach_bypass,
}


# --------------------------------------------------------------- .cube files


def read_cube(path: Path) -> np.ndarray:
    """Read a .cube file and resample it to 17^3.

    ``.cube`` stores values with **blue varying fastest**, which is the single
    most common thing to get wrong when reading one.
    """
    size = None
    values: list[tuple[float, float, float]] = []
    domain_min = np.zeros(3)
    domain_max = np.ones(3)

    for raw in path.read_text().splitlines():
        line = raw.split("#")[0].strip()
        if not line:
            continue
        head, *rest = line.split()
        key = head.upper()
        if key == "LUT_3D_SIZE":
            size = int(rest[0])
        elif key == "DOMAIN_MIN":
            domain_min = np.array([float(v) for v in rest])
        elif key == "DOMAIN_MAX":
            domain_max = np.array([float(v) for v in rest])
        elif key in {"TITLE", "LUT_1D_SIZE"}:
            continue
        else:
            try:
                values.append(tuple(float(v) for v in (head, *rest)[:3]))
            except ValueError:
                continue

    if size is None:
        raise ValueError(f"{path}: no LUT_3D_SIZE")
    if len(values) != size**3:
        raise ValueError(f"{path}: expected {size**3} entries, found {len(values)}")

    data = np.array(values, dtype=np.float64).reshape(size, size, size, 3)
    # .cube order is [b][g][r] with blue fastest -> transpose to [r][g][b].
    data = np.transpose(data, (2, 1, 0, 3))
    data = (data - domain_min) / (domain_max - domain_min)

    if size == LUT_NODES:
        return np.clip(np.rint(data * 255), 0, 255).astype(np.uint8)
    return resample(data, LUT_NODES)


def resample(data: np.ndarray, nodes: int) -> np.ndarray:
    """Trilinear resample of a float LUT onto an n^3 grid."""
    size = data.shape[0]
    coords = np.linspace(0, size - 1, nodes)
    lo = np.floor(coords).astype(int)
    hi = np.minimum(lo + 1, size - 1)
    frac = coords - lo

    def axis_lerp(arr: np.ndarray, axis: int) -> np.ndarray:
        a = np.take(arr, lo, axis=axis)
        b = np.take(arr, hi, axis=axis)
        shape = [1] * arr.ndim
        shape[axis] = nodes
        f = frac.reshape(shape)
        return a + (b - a) * f

    out = axis_lerp(data, 0)
    out = axis_lerp(out, 1)
    out = axis_lerp(out, 2)
    return np.clip(np.rint(out * 255), 0, 255).astype(np.uint8)


# ------------------------------------------------------------------- output


def write_banks(lut: np.ndarray, outdir: Path, name: str) -> list[Path]:
    """Write ``<name>_bank0.mem`` .. ``<name>_bank7.mem``.

    One 24-bit hex word per line, which is what ``$readmemh`` expects and what
    Vivado bakes into the bitstream as BRAM initialisation.
    """
    outdir.mkdir(parents=True, exist_ok=True)
    written = []
    for i, bank in enumerate(emit_banks(lut)):
        path = outdir / f"{name}_bank{i}.mem"
        with path.open("w") as handle:
            for px in bank:
                handle.write(f"{px[0]:02x}{px[1]:02x}{px[2]:02x}\n")
        written.append(path)
    return written


def write_cube(lut: np.ndarray, path: Path, title: str) -> None:
    """Emit a .cube so a grade made here can be checked in Resolve."""
    with path.open("w") as handle:
        handle.write(f"TITLE \"{title}\"\nLUT_3D_SIZE {LUT_NODES}\n\n")
        for b in range(LUT_NODES):
            for g in range(LUT_NODES):
                for r in range(LUT_NODES):
                    px = lut[r, g, b] / 255.0
                    handle.write(f"{px[0]:.6f} {px[1]:.6f} {px[2]:.6f}\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cube", type=Path, help="read a .cube file instead")
    parser.add_argument("--name", help="output base name")
    parser.add_argument(
        "--outdir", type=Path, default=Path("sim/vectors/lut"), help="output directory"
    )
    parser.add_argument("--list", action="store_true", help="list built-in grades")
    args = parser.parse_args(argv)

    if args.list:
        for name in GRADES:
            print(name)
        return 0

    if args.cube:
        name = args.name or args.cube.stem
        lut = read_cube(args.cube)
        paths = write_banks(lut, args.outdir, name)
        print(f"{name}: {len(paths)} banks -> {args.outdir}")
        return 0

    for name, builder in GRADES.items():
        write_banks(builder(), args.outdir, name)
        print(f"{name}: 8 banks -> {args.outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
