"""Overlay measured arc-registered profiles normalized by imposed amplitude."""

import csv
import json
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "subroutines"))
from plot_format import format_plot


REPORT_ROOT = Path("/mnt/lab_storage/Cole/FTSI/Reports/12OCT26")
INPUT_DIR = REPORT_ROOT / "experimental_nonlinearity"
OUTPUT_DIR = Path(__file__).resolve().parents[4] / "outputs/profile_collapse"
SIDES = ("top", "bottom")
GAGE_PITCHES_MM = (0.65, 2.60)
REGISTRATION_FIT = "linear"  # Use the linear estimator's converged arc mapping.


def main():
    for side in SIDES:
        for pitch in GAGE_PITCHES_MM:
            group = Path(side) / f"gage_pitch_{pitch:.2f}mm"
            profiles = []
            for source in (INPUT_DIR / group / "mode1").rglob("*_fit_results.json"):
                data = json.loads(source.read_text())
                fit = data[REGISTRATION_FIT]
                if not fit["converged"]:
                    raise ValueError(f"Unconverged registration: {source}")
                profiles.append((float(data["imposed_amplitudes_mm"][0]), fit, source))
            profiles.sort(key=lambda item: item[0])
            assert len(profiles) == (4 if side == "top" else 5)
            folder = OUTPUT_DIR / group
            folder.mkdir(parents=True, exist_ok=True)
            fig, axes = plt.subplots(1, 2, figsize=(12, 5), sharex=True,
                                     constrained_layout=True)
            rows = []
            for amplitude, fit, source in profiles:
                x = np.asarray(fit["position_mm"])
                measured = np.asarray(fit["mean_shift_ghz"], dtype=float)
                offset = float(fit["offset_ghz"])
                raw = measured / amplitude
                centered = (measured - offset) / amplitude
                # Plot measured registered points; no cosine substitution or smoothing.
                for ax, values in zip(axes, (raw, centered)):
                    ax.plot(x, values, ".-", markersize=3, label=f"{amplitude:g} mm imposed")
                for position, original, normalized, baseline_removed in zip(x, measured, raw, centered):
                    rows.append(dict(imposed_amplitude_mm=amplitude, position_mm=position,
                                     mean_shift_ghz=original, fitted_offset_ghz=offset,
                                     normalized_shift_ghz_per_mm=normalized,
                                     baseline_removed_shift_ghz_per_mm=baseline_removed,
                                     source_fit_results=str(source)))
            axes[0].set_title(r"Measured shift / $A_{imposed}$")
            axes[1].set_title(r"(Measured shift − fitted baseline) / $A_{imposed}$")
            for ax in axes:
                ax.set(xlabel="Arc-registered horizontal position (mm)",
                       ylabel="Optical shift per imposed amplitude (GHz/mm)")
                ax.grid(alpha=0.3)
                ax.legend()
            fig.suptitle(f"{side.capitalize()}, mode 1, {pitch:.2f} mm pitch: measured profile collapse")
            format_plot(fig)
            fig.savefig(folder / "normalized_optical_profiles.png", dpi=250)
            plt.close(fig)
            with (folder / "normalized_profiles.csv").open("w", newline="", encoding="utf-8") as file:
                writer = csv.DictWriter(file, fieldnames=list(rows[0]))
                writer.writeheader()
                writer.writerows(rows)
            print(f"Saved {len(profiles)} overlaid profiles: {folder}")
    (OUTPUT_DIR / "README.txt").write_text(
        "Measured time-averaged optical profiles, normalized by KNOWN imposed amplitude.\n"
        "Use mean_shift_ghz from each saved linear fit: the measurement after its converged arc registration, not its cosine prediction.\n"
        "Left: shift/A. Right: (shift - fitted optical baseline)/A. Baselines are from the original linear fits.\n"
        "Only the registered active 0-50 mm window is plotted; padded ROIs remain in the source outputs.\n"
        "No signal smoothing, further fitting, or scaling by recovered amplitude. Signed top/bottom shifts are retained.\n"
        "Registration depends on fitted amplitude, so this is a conditional profile comparison.\n"
        "Baseline subtraction can hide a common constant component; compare both panels when assessing shared end effects.\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
