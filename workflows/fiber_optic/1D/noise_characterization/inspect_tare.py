"""Plot the saved optical tare from a Luna TSV export."""

import sys
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "subroutines"))
from restore_tare import read_tare_profile

TARE_SOURCE_FILE = Path("/mnt/lab_storage/Cole/FTSI/Luna_Data/NOISE_CHARACTERIZATION/collected data/1mm/0-65/1MM_BOTTOM_0-65_2026-10-07_01-38-25_ch1_full.tsv")
POSITION_RANGE_M = (1.69, 1.80)  # Example: (1.69, 1.80) to inspect the coupon region.

SAVE_PLOT = False
OUTPUT_DIR = Path("/mnt/lab_storage/Cole/FTSI/Luna_Data/NOISE_CHARACTERIZATION/outputs/1mm/0-65/bottom")
PLOT_NAME = "1mm_bottom_tare.png"
PLOT_TITLE = "Bottom case: exported 1MM TARE"


def main():
    position_m, tare_ghz = read_tare_profile(TARE_SOURCE_FILE)
    selected = np.ones(position_m.shape, dtype=bool)
    if POSITION_RANGE_M is not None:
        lower, upper = POSITION_RANGE_M
        selected = (position_m >= lower) & (position_m <= upper)
    if not selected.any():
        raise ValueError("No positions in the selected range")
    position_m, tare_ghz = position_m[selected], tare_ghz[selected]
    print(f"Source: {TARE_SOURCE_FILE}")
    print(f"Finite tare readings: {np.isfinite(tare_ghz).sum()} / {tare_ghz.size}")

    fig, ax = plt.subplots(figsize=(10, 5), constrained_layout=True)
    ax.plot(position_m, tare_ghz)
    ax.set_xlabel("Absolute fiber position (m)")
    ax.set_ylabel("Saved tare spectral shift (GHz)")
    ax.set_title(PLOT_TITLE)
    ax.grid(True)
    if SAVE_PLOT:
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        fig.savefig(OUTPUT_DIR / PLOT_NAME, dpi=300)
    plt.show()
    return position_m, tare_ghz


if __name__ == "__main__":
    position_m, tare_ghz = main()
