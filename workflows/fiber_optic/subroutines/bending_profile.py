"""Portable full-profile storage, before ROI selection or strain conversion.

Usage: profile = load_bending_profile(path)
       x, y = profile["position_m"], profile["bending_shift_ghz"]
"""

import json
from pathlib import Path

import numpy as np


def save_bending_profile(path, *, position_m, bending_shift_ghz,
                         top_tared_shift_ghz, bottom_tared_shift_ghz,
                         metadata=None):
    """Save matching 1D arrays and JSON metadata; return the .npz path."""
    path = Path(path).with_suffix(".npz")
    arrays = {name: np.asarray(value, dtype=float) for name, value in {
        "position_m": position_m,
        "bending_shift_ghz": bending_shift_ghz,
        "top_tared_shift_ghz": top_tared_shift_ghz,
        "bottom_tared_shift_ghz": bottom_tared_shift_ghz,
    }.items()}
    shape = arrays["position_m"].shape
    if len(shape) != 1 or any(value.shape != shape for value in arrays.values()):
        raise ValueError("Profile arrays must be matching 1D arrays")
    info = dict(metadata or {})
    info.update(format_version=1, segment="Pass",
                bending_convention="(bottom_tared - top_tared) / 2")
    metadata_json = json.dumps(info)
    path.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(path, **arrays, metadata_json=metadata_json)
    return path


def load_bending_profile(path):
    """Return arrays and decoded metadata, with the archive closed after loading."""
    with np.load(path, allow_pickle=False) as archive:
        metadata = json.loads(str(archive["metadata_json"].item()))
        if metadata.get("format_version") != 1:
            raise ValueError("Unsupported bending profile format version")
        profile = {name: archive[name] for name in (
            "position_m", "bending_shift_ghz", "top_tared_shift_ghz",
            "bottom_tared_shift_ghz",
        )}
    profile["metadata"] = metadata
    return profile
