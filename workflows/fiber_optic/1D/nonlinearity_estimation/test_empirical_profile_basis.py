"""Fit registered measurements with a same-side/pitch empirical 1 mm profile."""

import csv
import json
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "subroutines"))
from empirical_basis_inversion import fit_amplitudes
from plot_format import format_plot


REPORT_ROOT = Path("/mnt/lab_storage/Cole/FTSI/Reports/12OCT26")
INPUT_DIR = REPORT_ROOT / "experimental_nonlinearity"
OUTPUT_DIR = Path(__file__).resolve().parents[4] / "outputs/empirical_profile_basis"


def main():
    all_rows = []
    for side in ("top", "bottom"):
        for pitch in (0.65, 2.60):
            group = Path(side) / f"gage_pitch_{pitch:.2f}mm"
            cases = []
            for path in (INPUT_DIR / group / "mode1").rglob("*_fit_results.json"):
                data = json.loads(path.read_text())
                cases.append((float(data["imposed_amplitudes_mm"][0]), data, path))
            cases.sort(key=lambda item: item[0])
            calibration = next(data for amplitude, data, _ in cases if amplitude == 1.0)
            cal = calibration["linear"]
            x_basis = np.asarray(cal["position_mm"], dtype=float)
            # Preserve measured end features; separate the constant optical baseline.
            basis = np.asarray(cal["mean_shift_ghz"], dtype=float) - cal["offset_ghz"]
            folder = OUTPUT_DIR / group
            folder.mkdir(parents=True, exist_ok=True)
            np.savez_compressed(folder / "empirical_1mm_basis.npz", position_mm=x_basis,
                                optical_basis_ghz_per_mm=basis, imposed_amplitude_mm=1.0)
            rows = []
            for imposed, data, path in cases:
                target = data["linear"]
                x = np.asarray(target["position_mm"], dtype=float)
                measured = np.asarray(target["mean_shift_ghz"], dtype=float)
                evaluated = np.interp(x, x_basis, basis, left=np.nan, right=np.nan)
                fit = fit_amplitudes(evaluated[:, None], measured, allow_offset=True)
                amplitude = float(np.asarray(fit["amplitudes_mm"]).ravel()[0])
                row = dict(side=side, gage_pitch_mm=pitch, imposed_amplitude_mm=imposed,
                           empirical_amplitude_mm=amplitude, empirical_normalized_amplitude=amplitude / imposed,
                           empirical_offset_ghz=float(np.asarray(fit["offset_ghz"]).ravel()[0]),
                           empirical_rms_ghz=float(np.asarray(fit["rms_ghz"]).ravel()[0]),
                           valid_points=int(np.asarray(fit["valid_count"]).ravel()[0]),
                           cosine_linear_amplitude_mm=target["amplitudes_mm"][0],
                           cosine_corrected_amplitude_mm=data["corrected"]["amplitudes_mm"][0],
                           source_fit_results=str(path))
                rows.append(row)
                print(f"{side} {pitch:.2f} mm pitch, imposed {imposed:g}: empirical A={amplitude:.6f} mm")
            assert abs(rows[0]["empirical_amplitude_mm"] - 1.0) < 1e-8
            all_rows.extend(rows)
            with (folder / "summary.csv").open("w", newline="", encoding="utf-8") as file:
                writer = csv.DictWriter(file, fieldnames=list(rows[0]))
                writer.writeheader()
                writer.writerows(rows)
            fig, axes = plt.subplots(1, 2, figsize=(12, 5), constrained_layout=True)
            imposed = np.array([row["imposed_amplitude_mm"] for row in rows])
            axes[0].plot(imposed, imposed, "k--", label="Imposed")
            axes[1].axhline(1, color="black", linestyle="--", label="Perfect recovery")
            for key, label, style in (
                ("empirical_amplitude_mm", "Empirical 1 mm profile", "s-"),
                ("cosine_linear_amplitude_mm", "Linear cosine", "o-"),
                ("cosine_corrected_amplitude_mm", "Finite-slope cosine", "x-"),
            ):
                amplitude = np.array([row[key] for row in rows])
                axes[0].plot(imposed, amplitude, style, label=label)
                axes[1].plot(imposed, amplitude / imposed, style, label=label)
            axes[0].set_ylabel("Reconstructed amplitude (mm)")
            axes[1].set_ylabel(r"Normalized amplitude $A_{fit}/A_{imposed}$")
            for ax in axes:
                ax.set(xlabel="Imposed amplitude (mm)", xticks=imposed)
                ax.grid(alpha=0.3)
                ax.legend()
            fig.suptitle(f"{side.capitalize()}, mode 1, {pitch:.2f} mm pitch — empirical versus cosine basis")
            format_plot(fig)
            fig.savefig(folder / "reconstructed_amplitude_vs_imposed.png", dpi=250)
            plt.close(fig)
    with (OUTPUT_DIR / "summary.csv").open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=list(all_rows[0]))
        writer.writeheader()
        writer.writerows(all_rows)
    (OUTPUT_DIR / "README.txt").write_text(
        "Empirical basis = measured arc-registered 1 mm mean minus its fitted constant baseline, divided by 1 mm.\n"
        "Each side and pitch uses its own 1 mm profile. End features remain in this profile and scale with fitted amplitude.\n"
        "Targets use saved LINEAR-fit arc registration; this test changes only the basis, not registration.\n"
        "Fit amplitude and a free optical baseline. Missing basis/target points are excluded.\n"
        "Cosine comparators are saved original linear and finite-slope fits; the corrected comparator uses its own registration.\n"
        "Empirical basis has no finite-slope correction. No basis smoothing or recalibration using higher amplitudes.\n"
        "1 mm is a calibration self-check; 2-5 mm are held out from basis construction. Calibration uncertainty is not estimated.\n",
        encoding="utf-8",
    )
    assert len(all_rows) == 18
    return all_rows


if __name__ == "__main__":
    main()
