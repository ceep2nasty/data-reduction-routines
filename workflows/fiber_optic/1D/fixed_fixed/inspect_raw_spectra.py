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

DATA_DIR = Path(r"Z:\Cole\FTSI\Luna_Data\fixed_fixed")
SOURCE_FILE = (
    DATA_DIR / "raw" / "spec2" / "top" / "flat"
    / "flat_top_spec2_test2_notare_compressed_2026-10-16_15-16-41_ch1_gages.tsv"
)
save = False
save_filename = "top_flat_raw_spectra"
save_path = (DATA_DIR / "outputs" / "flat" / save_filename )


def main():
    recording = read_fos_tsv(SOURCE_FILE, segment="Pass")
    position_m = recording["position_m"]
    shift = recording["spectral_shift_ghz"]

    # Preserve NaN at gages where every sample is missing.
    count = np.sum(~np.isnan(shift), axis=0)
    mean_shift = np.divide(
        np.nansum(shift, axis=0), count,
        out=np.full(position_m.shape, np.nan), where=count > 0,
    )

    fig, ax = plt.subplots(figsize=(9, 4), constrained_layout=True)
    ax.plot(position_m, mean_shift, linewidth=1)
    ax.set_xlabel("Fiber position (m)")
    ax.set_ylabel("Time-averaged spectral shift (GHz)")
    ax.grid(alpha=0.25)

    ax.set_title("Fiber on top")
    if save:
        fig.savefig(save_path, dpi=300, bbox_inches="tight")

    plt.show()
    return recording


if __name__ == "__main__":
    main()


