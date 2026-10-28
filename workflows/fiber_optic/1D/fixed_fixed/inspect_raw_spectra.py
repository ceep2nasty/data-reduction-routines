"""Plot time-averaged Luna spectral shifts for static fixed-fixed tests."""

import sys
from pathlib import Path

# Shared readers remain in the parent subroutines directory.
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "subroutines"))

import matplotlib.pyplot as plt
import numpy as np

from load_fos_case import read_fos_tsv

plt.rcParams.update({'font.size': 20,
                     'font.family': 'serif',
                     'font.serif': ['Times New Roman'],
                     }) # Sets global font size

DATA_DIR = Path(r"Z:\Cole\FTSI\Luna_Data\fixed_fixed\raw\constant_curvature")
SOURCE_FILES = [
    DATA_DIR / "sag2_bottom_test1_2026-10-16_19-00-07_ch1_gages.tsv",
    DATA_DIR / "sag2_top_test1_2026-10-16_18-45-29_ch1_gages.tsv",
]
TITLES = [None, None]
save = False
save_filename = "top_bottom_flat_raw_spectra.png"
save_path = DATA_DIR / "outputs" / "raw_spectra_examples" / save_filename


def main():
    fig, axes = plt.subplots(2, 1, figsize=(18, 5), constrained_layout=True)
    recordings = []
    for ax, source, title in zip(axes, SOURCE_FILES, TITLES):
        recording = read_fos_tsv(source, segment="Pass")
        recordings.append(recording)
        position_m = recording["position_m"]
        shift = recording["spectral_shift_ghz"]
        # Preserve NaN at gages where every sample is missing.
        count = np.sum(~np.isnan(shift), axis=0)
        mean_shift = np.divide(
            np.nansum(shift, axis=0), count,
            out=np.full(position_m.shape, np.nan), where=count > 0,
        )
        ax.plot(position_m, mean_shift, linewidth=1)
        ax.grid(alpha=0.25)
    fig.supylabel("Time-averaged spectral shift (GHz)")
    fig.supxlabel("Fiber position (m)")
    if save:
        save_path.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(save_path, dpi=300, bbox_inches="tight")

    plt.show()
    return recordings


if __name__ == "__main__":
    main()


