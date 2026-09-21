from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

from load_fos_case import read_fos_tsv

def main():
    source_file = Path(
        "C:/Users/coled/Notre Dame/FTSI F26/lunaData/1D_1Mode_test1/1mm_NoLoad_2026-09-17_19-47-16_ch1_gages.tsv")

    recording = read_fos_tsv(source_file)

    positions = recording["position_m"]
    raw = recording["spectral_shift_ghz"]
    tare = recording["tare_shift_ghz"]

    corrected = raw - tare[np.newaxis, :]

    def mean_over_time(values):
        counts = np.sum(np.isfinite(values), axis=0)
        totals = np.sum(
            np.where(np.isfinite(values), values, 0.0),
            axis=0,
        )

        means = np.full(values.shape[1], np.nan)

        np.divide(
            totals,
            counts,
            out=means,
            where=counts > 0,
        )

        return means

    raw_mean = mean_over_time(raw)
    corrected_mean = mean_over_time(corrected)

    fig, axes = plt.subplots(
        1, 1,
        figsize=(11, 10),
        constrained_layout=True,
    )

    for pass_number, ax in enumerate(axes, start=1):
        start = recording["markers"][
            "Beginning ROI"
        ]["position_m"]

        end = recording["markers"][
            f"End ROI"
        ]["position_m"]

        mask = (
            (positions >= min(start, end))
            & (positions <= max(start, end))
        )

        ax.plot(
            positions[mask],
            raw_mean[mask],
            label="Exported measurement mean",
        )

        ax.plot(
            positions[mask],
            tare[mask],
            linestyle=":",
            label="Exported tare",
        )

        ax.plot(
            positions[mask],
            corrected_mean[mask],
            label="Mean after subtracting tare",
        )

        ax.axhline(0, color="black", linewidth=0.6)
        ax.set_title(f"Pass {pass_number}")
        ax.set_xlabel("Distance along fiber (m)")
        ax.set_ylabel("Spectral shift (GHz)")
        ax.grid(True, alpha=0.3)

    axes[0].legend()
    fig.suptitle("Diagnostic: explicit subtraction of exported tare")
    plt.show()
    return recording

if __name__ == "__main__":
    recording = main()