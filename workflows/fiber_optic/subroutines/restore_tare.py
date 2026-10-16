"""Restore a subtracted optical tare in arrays or uncentered ROI recordings."""

import csv
import json
from pathlib import Path

import numpy as np


def restore_tare(spectral_shift_ghz, tare_shift_ghz):
    """Add a verified reference profile to already tare-subtracted measurements.

    Shift is (positions,) or (time, positions); tare is (positions,), in GHz
    on the same grid. Returns a new array and preserves missing measurements.
    Raises ValueError for incompatible shapes or missing/infinite tare values.
    This restores reference-relative shift, not absolute physical strain.
    """
    shift = np.asarray(spectral_shift_ghz, dtype=float)
    tare = np.asarray(tare_shift_ghz, dtype=float)
    if shift.ndim not in (1, 2) or tare.ndim != 1 or shift.shape[-1] != tare.size:
        raise ValueError("Shift must be (positions,) or (time, positions), with a matching tare vector")
    if not np.all(np.isfinite(tare)):
        raise ValueError("Tare must contain finite values at every selected position")
    return shift + tare


def read_tare_profile(tare_source_file):
    """Return (absolute fiber position_m, tare_shift_ghz) from a Luna TSV.

    Supports full and All Gages exports. Missing tare readings remain NaN;
    missing or ambiguous header rows raise ValueError. No reference is inferred
    from a tare name alone.
    """
    with Path(tare_source_file).open(encoding="utf-8-sig", newline="") as file:
        rows = list(csv.reader(file, delimiter="\t"))

    def unique_row(label):
        matches = [row for row in rows if row and row[0].strip() == label]
        if len(matches) != 1:
            raise ValueError(f"{tare_source_file}: expected one {label!r} row; found {len(matches)}")
        return matches[0]

    tare_row = unique_row("Tare")
    positions = unique_row("x-axis")
    names = next((row for row in rows if row and row[0].strip() == "Gage/Segment Name"), None)
    if len(tare_row) != len(positions) or (names is not None and len(names) != len(positions)):
        raise ValueError("Tare, position, and gage headers must have matching widths")
    columns = [j for j in range(3, len(positions))
               if names is None or names[j].strip().startswith("All Gages[")]
    x = np.asarray([positions[j] for j in columns], dtype=float)
    tare = np.asarray([tare_row[j].strip() or "nan" for j in columns], dtype=float)
    if x.size == 0 or not np.all(np.isfinite(x)) or np.any(np.diff(x) <= 0):
        raise ValueError("Tare positions must be finite, nonempty, and increasing")
    return x, tare


def restore_roi_tare(roi_data, tare_source_file):
    """Restore tare for uncentered ROI JSON data or a JSON path, without saving.

    Uses absolute position_m per pass to match the TSV tare grid. Restores
    every time sample and returns a new dictionary with new shift arrays.
    Original data is unchanged. No interpolation or zero-filling is performed.
    Call before centering; position_mm alone cannot identify the original
    fiber locations. Choose another reference export explicitly only when
    you have verified it represents the recording's subtracted tare.
    """
    if isinstance(roi_data, (str, Path)):
        roi_data = json.loads(Path(roi_data).read_text(encoding="utf-8"))
    if "position_m" not in roi_data:
        raise ValueError("Supply uncentered ROI data with absolute position_m")
    x, tare = read_tare_profile(tare_source_file)
    restored = dict(roi_data)
    restored["spectral_shift_ghz"] = {}
    for name, values in roi_data["position_m"].items():
        position = np.asarray(values, dtype=float)
        if position.ndim != 1 or not np.all(np.isfinite(position)):
            raise ValueError(f"{name}: ROI positions must be a finite vector")
        # Choose the nearest gage, allowing only numerical roundoff in positions.
        right = np.clip(np.searchsorted(x, position), 0, len(x) - 1)
        left = np.maximum(right - 1, 0)
        indices = np.where(abs(x[left] - position) < abs(x[right] - position), left, right)
        if not np.allclose(x[indices], position, rtol=0, atol=1e-10):
            raise ValueError(f"{name}: ROI positions do not match the tare grid")
        restored["spectral_shift_ghz"][name] = restore_tare(
            roi_data["spectral_shift_ghz"][name], tare[indices],
        )
    return restored
