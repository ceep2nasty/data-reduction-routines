"""Plot the independently calibrated optical gain of each imposed-amplitude case."""

import csv
import re
import shutil
from pathlib import Path

import matplotlib.pyplot as plt

from batch_estimate_noise import DATA_ROOT
from empirical_basis_inversion import load_calibrated_basis
from plot_format import format_plot


OUTPUT_DIR = Path("/mnt/lab_storage/Cole/FTSI/Reports/12OCT26/calibration_gain")


def main(output_dir=OUTPUT_DIR):
    output_dir = Path(output_dir)
    rows = []
    for path in sorted((DATA_ROOT / "optical_basis_cal").glob("*mm/*_full.npz")):
        match = re.fullmatch(r"(\d+)mm_(top|bottom)_mode1_(\d+-\d+)_full", path.stem)
        if match is None:
            continue
        amplitude, side, pitch = match.groups()
        calibration = load_calibrated_basis(path)
        amplitude = float(amplitude)
        assert amplitude == calibration["imposed_amplitude_mm"]
        gain = calibration["optical_amplitude_ghz"] / amplitude
        rows.append(dict(side=side, gage_pitch_mm=float(pitch.replace("-", ".")),
                         imposed_amplitude_mm=amplitude, gain_ghz_per_mm=gain,
                         gain_magnitude_ghz_per_mm=abs(gain),
                         calibration_rms_ghz=calibration["rms_ghz"], source_calibration=str(path)))
        folder = output_dir / "bases" / side / f"gage_pitch_{float(pitch.replace('-', '.')):.2f}mm"
        folder.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, folder / path.name)
    rows.sort(key=lambda row: (row["side"], row["gage_pitch_mm"], row["imposed_amplitude_mm"]))
    with (output_dir / "summary.csv").open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

    fig, axes = plt.subplots(1, 2, figsize=(12, 5), constrained_layout=True)
    for ax, side in zip(axes, ("top", "bottom")):
        for pitch in (0.65, 2.6):
            cases = [row for row in rows if row["side"] == side and row["gage_pitch_mm"] == pitch]
            ax.plot([row["imposed_amplitude_mm"] for row in cases],
                    [row["gain_ghz_per_mm"] for row in cases], "o-", label=f"{pitch:.2f} mm pitch")
        ax.set(title=side.capitalize(), xlabel="Calibration cosine amplitude (mm)",
               ylabel="Signed calibrated gain (GHz/mm)", xticks=range(1, 6))
        ax.grid(alpha=0.3)
        ax.legend()
    fig.suptitle("Empirical linear cosine calibration: gain versus imposed amplitude")
    format_plot(fig)
    fig.savefig(output_dir / "calibrated_gain_vs_amplitude.png", dpi=250)
    plt.close(fig)
    # Separate side plots show gain magnitude on a common scale for comparison.
    for side in ("top", "bottom"):
        fig, ax = plt.subplots(figsize=(8, 5), constrained_layout=True)
        for pitch in (0.65, 2.6):
            cases = [row for row in rows if row["side"] == side and row["gage_pitch_mm"] == pitch]
            ax.plot([row["imposed_amplitude_mm"] for row in cases],
                    [row["gain_magnitude_ghz_per_mm"] for row in cases], "o-",
                    label=f"{pitch:.2f} mm pitch")
        gains = [row["gain_magnitude_ghz_per_mm"] for row in rows]
        ax.set(title=f"{side.capitalize()}: independently calibrated gain per mm",
               xlabel="Calibration cosine amplitude (mm)", ylabel="Gain magnitude (GHz/mm)",
               xticks=range(1, 6), ylim=(min(gains) - 0.5, max(gains) + 0.5))
        ax.grid(alpha=0.3)
        ax.legend()
        format_plot(fig)
        fig.savefig(output_dir / f"{side}_gain_per_mm_vs_amplitude.png", dpi=250)
        plt.close(fig)
    (output_dir / "README.txt").write_text(
        "Gain = fitted optical cosine coefficient (GHz) / imposed cosine amplitude (mm).\n"
        "Each point uses that recording's own saved linear calibration, not the fixed 1 mm reconstruction basis.\n"
        "Signed gains are plotted: top and bottom have opposite optical response signs.\n"
        "Separate top/bottom plots show gain magnitude on matching axes.\n"
        "Both signed gains and magnitudes are in summary.csv; no uncertainty bars are estimated.\n"
        "Existing centered, tared calibrations are used without arc registration or finite-slope correction.\n"
        "Top covers 1-4 mm; bottom covers 1-5 mm, at both 0.65 and 2.60 mm pitch.\n",
        encoding="utf-8",
    )
    print(f"Saved {len(rows)} calibrated gains to {output_dir}")
    return rows


if __name__ == "__main__":
    main()
