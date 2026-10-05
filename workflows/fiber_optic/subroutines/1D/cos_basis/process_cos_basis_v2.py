"""Load full COS recordings and labeled passes for subsequent processing.

data[case_id][condition]["full_data"] is the complete read_fos_tsv recording.
data[case_id][condition]["passes"][pass_id]["forward" or "reverse"] contains
the selected raw samples and time average, oriented along the specimen.
Processing spatial fields use mm; original TSV/JSON headers retain source units.
Case components retain the filename's k/a values; physical units are not assumed.
"""

import sys
from pathlib import Path

# Shared readers remain in the parent subroutines directory.
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import argparse
import json
from pathlib import Path
import re

import numpy as np
import matplotlib.pyplot as plt
from cos_plot_labels import format_figure, save_figure

plt.rcParams.update({
    "font.family": "Times New Roman",
    "font.size": 14,
    "axes.labelsize": 16,
    "axes.titlesize": 16,
    "xtick.labelsize": 14,
    "ytick.labelsize": 14,
    "legend.fontsize": 13,
    "figure.titlesize": 18,
})

from plot_cos_basis_v2 import DATA_DIR, ROI_FILE, load_spectra, mean_profile

L_active = 50.0  # mm: active length for subsequent processing
L_ext = 0.0      # mm: extension per side
FIG_DIR = Path(r"C:\Users\coled\Notre Dame\FTSI F26\progress reports\10OCT2026\figs\combined linearity checks")
EXTREMA_RADIUS = 25.0  # mm: search around the ROI midpoint
SLOPE_GAGES = 5        # gages on each side supporting a slope reversal


def fit_extrema(p, components, active_length=L_active, radius=EXTREMA_RADIUS,
                slope_gages=SLOPE_GAGES):
    """Rank sustained local extrema by raw-data RMS over a full active window."""
    x, y = p["distance_mm"], p["mean_spectral_shift_ghz"]
    valid = np.isfinite(y)
    if active_length <= 0 or radius <= 0 or slope_gages < 2 or valid.sum() < 10:
        raise ValueError("Invalid lengths or insufficient finite data")
    filled = np.interp(x, x[valid], y[valid])
    smooth = np.convolve(np.pad(filled, (2, 2), mode="edge"), np.ones(5) / 5, mode="valid")
    slope = np.diff(smooth)
    noise = 1.4826 * np.median(np.abs((filled - smooth) - np.median(filled - smooth)))
    midpoint = (x[0] + x[-1]) / 2
    candidates = []
    n = slope_gages
    for i in range(n, len(x) - n):
        if abs(x[i] - midpoint) > radius:
            continue
        if x[i] - active_length / 2 < x[0] or x[i] + active_length / 2 > x[-1]:
            continue
        maximum = slope[i - 1] > 0 and slope[i] <= 0
        minimum = slope[i - 1] < 0 and slope[i] >= 0
        if not (maximum or minimum):
            continue
        sign = 1 if maximum else -1
        if np.mean(sign * slope[i-n:i] > 0) < 0.8 or np.mean(sign * slope[i:i+n] < 0) < 0.8:
            continue
        prominence = min(sign * (smooth[i] - smooth[i-n]), sign * (smooth[i] - smooth[i+n]))
        if prominence <= 3 * noise:
            continue
        mask = valid & (np.abs(x - x[i]) <= active_length / 2)
        if mask.sum() < 10:
            continue
        centered = x[mask] - x[i]
        template = sum(c["amplitude"] * c["wavenumber"]**2 *
                       np.cos(2 * np.pi * c["wavenumber"] *
                              (centered / active_length + 0.5)) for c in components)
        design = np.column_stack((np.ones(mask.sum()), template))
        coeff, _, rank, _ = np.linalg.lstsq(design, y[mask], rcond=None)
        if rank < 2:
            continue
        predicted = design @ coeff
        candidates.append({"center_mm": float(x[i]), "kind": "maximum" if maximum else "minimum",
                           "rms_ghz": float(np.sqrt(np.mean((y[mask] - predicted)**2))),
                           "offset_ghz": float(coeff[0]), "scale_ghz": float(coeff[1]),
                           "mask": mask, "fitted_shift_ghz": predicted})
    if not candidates:
        raise ValueError("No sustained extrema above the noise threshold near ROI center")
    best = min(candidates, key=lambda r: (r["rms_ghz"], abs(r["center_mm"] - midpoint)))
    p["center_mm"] = best["center_mm"]
    return best
def load_data(data_dir=DATA_DIR, roi_file=ROI_FILE):
    """Read TSV measurements and JSON bounds without opening figures."""
    selections = json.loads(Path(roi_file).read_text(encoding="utf-8"))
    spectra = load_spectra(data_dir)
    data = {}
    for condition, cases in spectra.items():
        for case_id, recording in cases.items():
            saved = selections.get(condition, {}).get(case_id)
            if saved is None:
                raise ValueError(f"Missing ROI definitions: {case_id}, {condition}")
            if Path(saved["source_file"]).name != recording["source_file"].name:
                raise ValueError(f"ROI source mismatch: {case_id}, {condition}")
            components = re.findall(r"k(\d+)_a(\d+)", case_id)
            positions, average = mean_profile(recording)
            positions = positions * 1000
            recording_mm = dict(recording)
            recording_mm["position_mm"] = recording_mm.pop("position_m") * 1000
            recording_mm["markers"] = {
                name: {**{k: v for k, v in marker.items() if k != "position_m"},
                       "position_mm": marker["position_m"] * 1000}
                for name, marker in recording["markers"].items()
            }
            entry = {
                "components": [{"wavenumber": int(k), "amplitude": int(a)}
                               for k, a in components],
                "full_data": recording_mm,
                "passes": {},
            }
            for roi in saved["rois"]:
                if roi["direction"] not in (1, -1) or roi["surface"] not in ("top", "bottom"):
                    raise ValueError(f"Unlabeled ROI: {case_id}, {condition}, {roi}")
                start, end = np.asarray(roi["bounds_m"]) * 1000
                roi_mm = {k: v for k, v in roi.items() if k != "bounds_m"}
                roi_mm["bounds_mm"] = [float(start), float(end)]
                if not positions[0] <= start < end <= positions[-1]:
                    raise ValueError(f"Invalid ROI bounds: {case_id}, {condition}, {roi}")
                indices = np.flatnonzero((positions >= start) & (positions <= end))
                if len(indices) < 2:
                    raise ValueError(f"ROI needs at least two gages: {roi}")
                direction = "forward" if roi["direction"] == 1 else "reverse"
                if direction == "reverse":
                    indices = indices[::-1]
                fiber_positions = positions[indices]
                distance = np.abs(fiber_positions - fiber_positions[0])
                pass_data = {
                    "roi": roi_mm,
                    "surface": roi["surface"],
                    "gage_indices": indices,
                    "fiber_position_mm": fiber_positions,
                    "distance_mm": distance,
                    "time_s": recording["time_s"],
                    "timestamps": recording["timestamps"],
                    "spectral_shift_ghz": recording["spectral_shift_ghz"][:, indices],
                    "mean_spectral_shift_ghz": average[indices],
                    "tare_shift_ghz": recording["tare_shift_ghz"][indices],
                }
                passes = entry["passes"].setdefault(roi["pass_id"], {})
                if direction in passes:
                    raise ValueError(f"Duplicate pass/direction: {case_id}, {condition}, {roi}")
                passes[direction] = pass_data
            data.setdefault(case_id, {})[condition] = entry
    return data



def find_centers(data, active_length=L_active):
    for conditions in data.values():
        for entry in conditions.values():
            for directions in entry["passes"].values():
                for p in directions.values():
                    fit_extrema(p, entry["components"], active_length)


def check_linearity(data, active_length=L_active):
    """Compare raw time averages: residual = 2*k1_a1 - k1_a2."""
    results = {}
    for condition, entry in data["k1_a1"].items():
        for pid, directions in entry["passes"].items():
            for direction, small in directions.items():
                large = data["k1_a2"][condition]["passes"][pid][direction]
                if small["surface"] != large["surface"]:
                    raise ValueError("Pass surfaces do not match")
                x1 = small["distance_mm"] - small["center_mm"]
                x2 = large["distance_mm"] - large["center_mm"]
                y1 = small["mean_spectral_shift_ghz"]
                y2 = large["mean_spectral_shift_ghz"]
                # No extrapolation or bridging missing samples.
                scaled = np.interp(x2, x1, 2*y1, left=np.nan, right=np.nan)
                keep = (np.abs(x2) <= active_length/2) & np.isfinite(y2) & np.isfinite(scaled)
                if not keep.any():
                    raise ValueError("No overlapping finite active-window samples")
                residual = scaled[keep] - y2[keep]
                rms = float(np.sqrt(np.mean(residual**2)))
                results.setdefault(condition, {}).setdefault(pid, {})[direction] = {
                    "centered_distance_mm": x2[keep], "residual_ghz": residual, "rms_ghz": rms}
                fig, axes = plt.subplots(3, 1, figsize=(9, 8), sharex=True, constrained_layout=True)
                fig.suptitle(f"Amplitude linearity: {condition}, pass {pid}")
                fig._output_direction = direction
                axes[0].plot(x1, y1, label="k1_a1")
                axes[1].plot(x2, y2, label="k1_a2")
                axes[1].plot(x1, 2*y1, "--", label="2 * k1_a1")
                axes[2].plot(x2[keep], residual, label="2 * k1_a1 - k1_a2")
                axes[2].axhline(0, color="0.5", linewidth=0.7)
                axes[2].set_title(f"Active-window residual RMS: {rms:.3f} GHz")
                for ax in axes:
                    for bound in (-active_length/2, active_length/2):
                        ax.axvline(bound, color="k", linestyle="--", linewidth=0.8)
                    ax.set_ylabel("Optical shift (GHz)")
                    ax.grid(alpha=0.25)
                    ax.legend()
                axes[2].set_ylabel("Residual (GHz)")
                axes[2].set_xlabel("Distance from detected center (mm)")
                print(f"{condition}, pass {pid}, {direction}: linearity RMS={rms:.3f} GHz")
    return results


def check_superposition(data, active_length=L_active, first_case="k1_a2", first_scale=1):
    """Compare scaled first case + k2_a1 against the combined recording."""
    results = {}
    first_label = first_case if first_scale == 1 else f"{first_scale} * {first_case}"
    title = "Superposition" if first_scale == 1 else "Combined linearity"
    for condition, entry in data[first_case].items():
        for pid, directions in entry["passes"].items():
            for direction, first in directions.items():
                second = data["k2_a1"][condition]["passes"][pid][direction]
                combined = data["k1_a2_k2_a1"][condition]["passes"][pid][direction]
                if len({p["surface"] for p in (first, second, combined)}) != 1:
                    raise ValueError("Pass surfaces do not match")
                x1, x2, xc = [p["distance_mm"] - p["center_mm"]
                              for p in (first, second, combined)]
                y1, y2, yc = [p["mean_spectral_shift_ghz"]
                              for p in (first, second, combined)]
                y1 = first_scale * y1
                # Use combined-recording positions; preserve gaps and avoid extrapolation.
                summed = (np.interp(xc, x1, y1, left=np.nan, right=np.nan)
                          + np.interp(xc, x2, y2, left=np.nan, right=np.nan))
                keep = (np.abs(xc) <= active_length / 2) & np.isfinite(yc) & np.isfinite(summed)
                if not keep.any():
                    raise ValueError("No overlapping finite active-window samples")
                residual = summed[keep] - yc[keep]
                rms = float(np.sqrt(np.mean(residual**2)))
                results.setdefault(condition, {}).setdefault(pid, {})[direction] = {
                    "centered_distance_mm": xc[keep], "residual_ghz": residual,
                    "summed_shift_ghz": summed[keep], "rms_ghz": rms,
                }
                fig, axes = plt.subplots(3, 1, figsize=(9, 8), sharex=True, constrained_layout=True)
                fig.suptitle(f"{title}: {condition}, pass {pid}")
                fig._output_direction = direction
                axes[0].plot(x1, y1, label=first_label)
                axes[0].plot(x2, y2, label="k2_a1")
                axes[1].plot(xc, yc, label="k1_a2_k2_a1")
                axes[1].plot(xc, summed, "--", label=f"{first_label} + k2_a1")
                axes[2].plot(xc[keep], residual, label="Sum − combined recording")
                axes[2].axhline(0, color="0.5", linewidth=0.7)
                axes[2].set_title(f"Active-window residual RMS: {rms:.3f} GHz")
                for ax in axes:
                    for bound in (-active_length / 2, active_length / 2):
                        ax.axvline(bound, color="k", linestyle="--", linewidth=0.8)
                    ax.set_ylabel("Optical shift (GHz)")
                    ax.grid(alpha=0.25)
                    ax.legend()
                axes[2].set_ylabel("Residual (GHz)")
                axes[2].set_xlabel("Distance from detected center (mm)")
                print(f"{condition}, pass {pid}, {direction}: {title} RMS={rms:.3f} GHz")
    return results


def check_combined_linearity(data, active_length=L_active):
    """Compare 2*k1_a1 + k2_a1 against k1_a2_k2_a1."""
    return check_superposition(data, active_length, first_case="k1_a1", first_scale=2)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_dir", nargs="?", type=Path, default=DATA_DIR)
    parser.add_argument("--roi-file", type=Path, default=ROI_FILE)
    parser.add_argument("--L-active", type=float, default=L_active, help="Active length in mm")
    parser.add_argument("--L-ext", type=float, default=L_ext, help="Extension per side in mm")
    parser.add_argument("--output-dir", type=Path, default=FIG_DIR, help="Figure output folder")
    args = parser.parse_args()
    data = load_data(args.data_dir, args.roi_file)
    find_centers(data, args.L_active)
    data["linearity"] = check_linearity(data, args.L_active)
    data["superposition"] = check_superposition(data, args.L_active)
    data["combined_linearity"] = check_combined_linearity(data, args.L_active)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for number in plt.get_fignums():
        fig = plt.figure(number)
        name = re.sub(r"[^a-z0-9]+", "_", fig._suptitle.get_text().lower()).strip("_")
        name += f"_{fig._output_direction}"
        format_figure(fig)
        save_figure(fig, args.output_dir / f"{name}.png")
    plt.show()
    return data


if __name__ == "__main__":
    data = main()
