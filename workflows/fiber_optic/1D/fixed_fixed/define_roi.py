"""Load the spec2 k1a0.5 bending profile for subsequent ROI selection."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "subroutines"))

from bending_profile import load_bending_profile


PROFILE_PATH = (
    Path(r"C:\Users\coled_agkeohi\Notre Dame\FTSI F26\fixed-fixed")
    / "outputs/isolated_bending/k1a0-5_spec2.npz"
)


if __name__ == "__main__":
    profile = load_bending_profile(PROFILE_PATH)
    position_m = profile["position_m"]
    bending_shift_ghz = profile["bending_shift_ghz"]
