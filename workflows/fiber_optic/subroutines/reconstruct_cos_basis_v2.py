"""Reconstruct centered optical profiles using measured mode-1/mode-2 bases.

Coefficients multiply the known 1 mm displacement amplitudes of k1_a1/k2_a1.
Displacement is evaluated on the specimen coordinate, not the measured fiber arc.
"""

import argparse
import json
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

from process_cos_basis_v2 import DATA_DIR, ROI_FILE, L_active, load_data, find_centers
from decompose_cos_basis_v2 import json_ready

OUTPUT_DIR = Path(__file__).with_name("cos_basis_v2_reconstruction")
FIG_DIR = Path(r"C:\Users\coled\Notre Dame\FTSI F26\progress reports\10OCT2026\figs")


def reconstruct(data, active_length=L_active):
    """Fit both empirical modes without a baseline offset or phase adjustment."""
    outputs = {}
    for case_id in ("k1_a2", "k1_a2_k2_a1"):
        outputs[case_id] = {}
        for condition, entry in data[case_id].items():
            outputs[case_id][condition] = {}
            for pid, directions in entry["passes"].items():
                outputs[case_id][condition][pid] = {}
                for direction, target in directions.items():
                    bases = [data[case][condition]["passes"][pid][direction]
                             for case in ("k1_a1", "k2_a1")]
                    if any(p["surface"] != target["surface"] for p in bases):
                        raise ValueError("Basis and target surfaces differ")
                    x = target["distance_mm"] - target["center_mm"]
                    y = target["mean_spectral_shift_ghz"]
                    columns = [np.interp(x, p["distance_mm"] - p["center_mm"],
                                         p["mean_spectral_shift_ghz"], left=np.nan, right=np.nan)
                               for p in bases]
                    design = np.column_stack(columns)
                    keep = ((np.abs(x) <= active_length / 2)
                            & np.isfinite(y) & np.all(np.isfinite(design), axis=1))
                    if keep.sum() < 3:
                        raise ValueError("Not enough overlapping finite ROI samples")
                    coefficients, _, rank, singular = np.linalg.lstsq(design[keep], y[keep], rcond=None)
                    if rank < 2:
                        raise ValueError("Empirical bases are linearly dependent")
                    prediction = design[keep] @ coefficients
                    residual = y[keep] - prediction
                    # Empirical calibration: both measured basis states have 1 mm amplitude.
                    amplitudes_mm = coefficients * np.array([1.0, 1.0])
                    shape_x = np.linspace(-active_length / 2, active_length / 2, 501)
                    shape_basis = np.cos(2 * np.pi *
                                         (shape_x[:, None] / active_length + 0.5)
                                         * np.array([1, 2]))
                    imposed_amplitudes = np.array([2.0, 0.0] if case_id == "k1_a2" else [2.0, 1.0])
                    displacement = shape_basis @ amplitudes_mm
                    imposed_displacement = shape_basis @ imposed_amplitudes
                    result = {
                        "surface": target["surface"], "units": {"distance": "mm", "shift": "GHz"},
                        "basis_cases": ["k1_a1", "k2_a1"],
                        "coefficients": coefficients,
                        "modal_amplitudes_mm": amplitudes_mm,
                        "specimen_coordinate_mm": shape_x,
                        "reconstructed_displacement_mm": displacement,
                        "imposed_modal_amplitudes_mm": imposed_amplitudes,
                        "imposed_displacement_mm": imposed_displacement,
                        "displacement_residual_mm": displacement - imposed_displacement,
                        "expected_coefficients": [2, 0] if case_id == "k1_a2" else [2, 1],
                        "centered_distance_mm": x[keep], "measured_shift_ghz": y[keep],
                        "basis_shift_ghz": design[keep],
                        "reconstructed_shift_ghz": prediction, "residual_ghz": residual,
                        "rms_ghz": float(np.sqrt(np.mean(residual**2))),
                        "basis_condition_number": float(singular[0] / singular[-1]),
                        "target_center_mm": target["center_mm"],
                        "L_active_mm": active_length,
                        "basis_centers_mm": [p["center_mm"] for p in bases],
                        "source_file": str(entry["full_data"]["source_file"]),
                    }
                    outputs[case_id][condition][pid][direction] = result
                    fig, axes = plt.subplots(3, 1, figsize=(10, 9), sharex=True, constrained_layout=True)
                    fig.suptitle(f"Empirical reconstruction: {case_id}, {condition}, pass {pid}, {target['surface']}")
                    fig._reconstruction_kind = "optical shift reconstruction"
                    fig._output_name = f"{case_id}_{condition}_pass_{pid}_{target['surface']}_{direction}"
                    for j, basis_case in enumerate(result["basis_cases"]):
                        axes[0].plot(x[keep], design[keep, j] * coefficients[j],
                                     label=f"{coefficients[j]:.3f} * {basis_case}")
                    axes[0].set_title("Fitted modal contributions")
                    axes[1].plot(x[keep], y[keep], color="0.6", label="Centered target ROI")
                    axes[1].plot(x[keep], prediction, "--", label="Reconstruction")
                    axes[2].plot(x[keep], residual, label="Measured - reconstructed")
                    axes[2].axhline(0, color="0.5", linewidth=0.7)
                    axes[2].set_title(f"ROI overlap RMS: {result['rms_ghz']:.3f} GHz")
                    for ax in axes:
                        ax.set_ylabel("Optical shift (GHz)")
                        ax.grid(alpha=0.25)
                        ax.legend()
                    axes[2].set_xlabel("Distance from detected center (mm)")
                    print(f"{case_id}, {condition}, pass {pid}: coefficients={coefficients.round(3)}, "
                          f"RMS={result['rms_ghz']:.3f} GHz")
                    shape_fig, shape_axes = plt.subplots(2, 1, figsize=(10, 7), sharex=True,
                                                         constrained_layout=True)
                    shape_fig.suptitle(f"Displacement: {case_id}, {condition}, pass {pid}, {target['surface']}")
                    shape_fig._reconstruction_kind = "shape reconstruction"
                    shape_fig._output_name = fig._output_name
                    shape_axes[0].plot(shape_x, imposed_displacement, label="Known imposed shape")
                    shape_axes[0].plot(shape_x, displacement, "--", label="Reconstructed shape")
                    shape_axes[0].set_ylabel("Displacement (mm)")
                    shape_axes[0].set_title(f"Fitted amplitudes: A1={amplitudes_mm[0]:.3f}, A2={amplitudes_mm[1]:.3f} mm")
                    shape_axes[0].legend()
                    shape_axes[1].plot(shape_x, displacement - imposed_displacement)
                    shape_axes[1].axhline(0, color="0.5", linewidth=0.7)
                    shape_axes[1].set_ylabel("Shape residual (mm)")
                    shape_axes[1].set_xlabel("Centered specimen coordinate (mm)")
                    for ax in shape_axes:
                        ax.grid(alpha=0.25)
    return outputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_dir", nargs="?", type=Path, default=DATA_DIR)
    parser.add_argument("--roi-file", type=Path, default=ROI_FILE)
    parser.add_argument("--output-dir", type=Path, default=OUTPUT_DIR)
    parser.add_argument("--fig-dir", type=Path, default=FIG_DIR, help="Parent folder for reconstruction figures")
    parser.add_argument("--L-active", type=float, default=L_active, help="Centered ROI length in mm")
    args = parser.parse_args()
    data = load_data(args.data_dir, args.roi_file)
    find_centers(data, args.L_active)
    outputs = reconstruct(data, args.L_active)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for case_id, conditions in outputs.items():
        (args.output_dir / f"{case_id}.json").write_text(
            json.dumps(json_ready(conditions), indent=2, allow_nan=False), encoding="utf-8")
    for number in plt.get_fignums():
        fig = plt.figure(number)
        kind = getattr(fig, "_reconstruction_kind", None)
        if kind is None:
            continue
        folder = args.fig_dir / kind
        folder.mkdir(parents=True, exist_ok=True)
        fig.savefig(folder / f"{fig._output_name}.png", dpi=300)
    plt.show()
    return outputs


if __name__ == "__main__":
    outputs = main()
