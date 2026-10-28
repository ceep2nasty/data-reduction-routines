"""Subtract flat references and isolate bending from top/bottom Pass spectra."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "subroutines"))

import numpy as np
import matplotlib.pyplot as plt

from load_fos_case import read_fos_tsv
from bending_profile import save_bending_profile

plt.rcParams.update({'font.size': 20,
                     'font.family': 'serif',
                     'font.serif': ['Times New Roman'],
                     }) # Sets global font size


DATA_DIR = Path(r"C:\Users\coled_agkeohi\Notre Dame\FTSI F26\fixed-fixed\roi extended")
FLAT_TOP_FILE = (
    DATA_DIR / "spec2/top/flat"
    / "flat_spec2_top_roi_extended.tsv"
)
FLAT_BOTTOM_FILE = (
    DATA_DIR / "spec2/bottom/flat"
    / "flat_spec2_bottom_roi_extended.tsv"
)
# Replace these paths to compare other recordings.
TOP_FILE = (
    DATA_DIR / "spec2/top/k1"
    / "k1a0-5_spec2_top_roi_extended.tsv"
)
BOTTOM_FILE = (
    DATA_DIR / "spec2/bottom/k1"
    / "k1a0-5_spec2_bottom_roi_extended.tsv"
)

SAVE_PROFILE = True
save = True  # Save figures as well.
SAVE_DIR = DATA_DIR.parent
save_filename = TOP_FILE.stem.removesuffix("_top_roi_extended")
PROFILE_PATH = SAVE_DIR / "outputs" / "isolated_bending" / f"{save_filename}.npz"
save_path = (SAVE_DIR / "outputs" / "isolated_bending_figs" / save_filename )


def mean_profile(recording):
    """Time-average each gage, retaining NaN for all-missing gages."""
    shift = recording["spectral_shift_ghz"]
    count = np.sum(~np.isnan(shift), axis=0)
    return np.divide(
        np.nansum(shift, axis=0), count,
        out=np.full(shift.shape[1], np.nan), where=count > 0,
    )

def isolate_bending(FLAT_TOP_FILE, FLAT_BOTTOM_FILE, TOP_FILE, BOTTOM_FILE):
    flat_top = read_fos_tsv(FLAT_TOP_FILE, segment="Pass")
    flat_bottom = read_fos_tsv(FLAT_BOTTOM_FILE, segment="Pass")
    top = read_fos_tsv(TOP_FILE, segment="Pass")
    bottom = read_fos_tsv(BOTTOM_FILE, segment="Pass")

    top_tared = mean_profile(top) - mean_profile(flat_top)
    bottom_tared = mean_profile(bottom) - mean_profile(flat_bottom)
    bending_shift = (bottom_tared - top_tared) / 2

    return bending_shift






if __name__ == "__main__":
    flat_top = read_fos_tsv(FLAT_TOP_FILE, segment="Pass")
    flat_bottom = read_fos_tsv(FLAT_BOTTOM_FILE, segment="Pass")
    top = read_fos_tsv(TOP_FILE, segment="Pass")
    bottom = read_fos_tsv(BOTTOM_FILE, segment="Pass")

    fig, axes = plt.subplots(1, 2, figsize=(18, 4), constrained_layout=True)
    for ax, recording, flat, title in zip(
        axes, [top, bottom], [flat_top, flat_bottom],
        ["Fiber on top", "Fiber on bottom"],
    ):
        position_m = recording["position_m"]
        if not np.array_equal(position_m, flat["position_m"]):
            raise ValueError(f"{title}: test and flat gage positions must match")
        raw = mean_profile(recording)
        tared = raw - mean_profile(flat)
        ax.plot(position_m, raw, label="Raw", linewidth=1)
        ax.plot(position_m, tared, label="Tared", linewidth=1)
        ax.set_xlabel("Fiber position (m)")
        ax.set_title(title)
        ax.grid(alpha=0.25)
        ax.legend()

    fig.supylabel("Time-averaged spectral shift (GHz)")
    fig.suptitle(r"Tare results, $A_1$ = 0.5mm")

    if not np.array_equal(top["position_m"], bottom["position_m"]):
        raise ValueError("Top and bottom gage positions must match")
    top_tared = mean_profile(top) - mean_profile(flat_top)
    bottom_tared = mean_profile(bottom) - mean_profile(flat_bottom)
    bending_shift = (bottom_tared - top_tared) / 2

    if SAVE_PROFILE:
        saved_path = save_bending_profile(
            PROFILE_PATH,
            position_m=top["position_m"],
            bending_shift_ghz=bending_shift,
            top_tared_shift_ghz=top_tared,
            bottom_tared_shift_ghz=bottom_tared,
            metadata={
                "recording_name": save_filename,
                "source_files": {
                    "flat_top": str(FLAT_TOP_FILE),
                    "flat_bottom": str(FLAT_BOTTOM_FILE),
                    "top": str(TOP_FILE),
                    "bottom": str(BOTTOM_FILE),
                },
            },
        )
        print(f"Saved bending profile: {saved_path}")

    bending_fig, bending_ax = plt.subplots(figsize=(9, 4), constrained_layout=True)
    bending_ax.plot(top["position_m"], bending_shift, linewidth=1)
    bending_ax.set_xlabel("Fiber position (m)")
    bending_ax.set_ylabel("Spectral shift (GHz)")
    bending_ax.set_title("Isolated Bending Shift")
    bending_ax.grid(alpha=0.25)
    if save:
        save_path.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(save_path.with_name(f"{save_filename}_tare.png"), dpi=300, bbox_inches="tight")
        bending_fig.savefig(save_path.with_name(f"{save_filename}_isolated_bending.png"), dpi=300, bbox_inches="tight")
    plt.show()
