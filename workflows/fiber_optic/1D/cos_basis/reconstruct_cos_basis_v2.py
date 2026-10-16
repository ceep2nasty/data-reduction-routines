"""Reconstruct centered optical profiles using measured mode-1/mode-2 bases.

Coefficients multiply the known 1 mm displacement amplitudes of k1_a1/k2_a1.
Displacement is evaluated on the specimen coordinate, not the measured fiber arc.
"""

import sys
from pathlib import Path

# Shared readers remain in the parent subroutines directory.
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import argparse
import json
from pathlib import Path

import matplotlib.pyplot as plt
from cos_plot_labels import format_figure, save_figure
import numpy as np

from process_cos_basis_v2 import DATA_DIR, ROI_FILE, L_active, load_data, find_centers
from decompose_cos_basis_v2 import json_ready

OUTPUT_DIR = Path(__file__).with_name("cos_basis_v2_reconstruction")
FIG_DIR = Path(r"C:\Users\coled\Notre Dame\FTSI F26\progress reports\10OCT2026\figs")


def reconstruct(data, active_length=L_active, allow_offset=False):
    """Fit both empirical modes with an optional optical baseline offset."""
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
                    fit_design = design[keep]
                    if allow_offset:
                        fit_design = np.column_stack((fit_design, np.ones(keep.sum())))
                    fitted, _, rank, singular = np.linalg.lstsq(fit_design, y[keep], rcond=None)
                    if rank < fit_design.shape[1]:
                        raise ValueError("Empirical bases are linearly dependent")
                    coefficients = fitted[:2]
                    offset = float(fitted[2]) if allow_offset else 0.0
                    prediction = fit_design @ fitted
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
                        "offset_allowed": allow_offset, "offset_ghz": offset,
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
                    if allow_offset:
                        fig._reconstruction_kind += " with offset"
                        fig.suptitle(fig._suptitle.get_text() + " (With Offset)")
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
                    if allow_offset:
                        shape_fig._reconstruction_kind += " with offset"
                        shape_fig.suptitle(shape_fig._suptitle.get_text() + " (With Offset)")
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


def save_raw_spectra(data, fig_dir=FIG_DIR):
    """Save full JSON-selected ROI averages with no center finding or cropping."""
    folder = Path(fig_dir) / "raw spectra"
    folder.mkdir(parents=True, exist_ok=True)
    for case_id, conditions in data.items():
        pass_ids = sorted({pid for entry in conditions.values() for pid in entry["passes"]})
        fig, axes = plt.subplots(len(pass_ids), 2, squeeze=False,
                                 figsize=(12, 3.5 * len(pass_ids)), constrained_layout=True)
        fig.suptitle(f"Raw spectra: {case_id}")
        for row, pid in enumerate(pass_ids):
            for col, condition in enumerate(("unconstrained", "constrained")):
                ax = axes[row, col]
                passes = conditions.get(condition, {}).get("passes", {}).get(pid, {})
                for p in passes.values():
                    ax.plot(p["distance_mm"], p["mean_spectral_shift_ghz"], label=p["surface"])
                ax.set_title(f"{condition}: pass {pid}")
                ax.set_xlabel("Distance along selected ROI (mm)")
                ax.set_ylabel("Mean optical shift (GHz)")
                ax.grid(alpha=0.25)
                if passes:
                    ax.legend()
        format_figure(fig, raw=True)
        save_figure(fig, folder / f"{case_id}.png")
        plt.close(fig)


def reconstruct_with_offset(data, active_length=L_active):
    """Fit a constant GHz offset; only modal amplitudes determine displacement."""
    return reconstruct(data, active_length, allow_offset=True)


def reconstruct_average(outputs):
    """Average top/bottom fitted amplitudes equally, then evaluate displacement."""
    for case_id, conditions in outputs.items():
        for condition, passes in conditions.items():
            surfaces = {}
            for directions in passes.values():
                for result in directions.values():
                    if result["surface"] in surfaces:
                        raise ValueError("Expected one fitted pass per surface")
                    surfaces[result["surface"]] = result
            if set(surfaces) != {"top", "bottom"}:
                raise ValueError("Averaged shape requires top and bottom fits")
            top, bottom = surfaces["top"], surfaces["bottom"]
            amplitudes = (top["modal_amplitudes_mm"] + bottom["modal_amplitudes_mm"]) / 2
            x = top["specimen_coordinate_mm"]
            length = top["L_active_mm"]
            basis = np.cos(2 * np.pi * (x[:, None] / length + 0.5) * np.array([1, 2]))
            shape = basis @ amplitudes
            imposed = top["imposed_displacement_mm"]
            passes["average_shape"] = {
                "modal_amplitudes_mm": amplitudes,
                "top_modal_amplitudes_mm": top["modal_amplitudes_mm"],
                "bottom_modal_amplitudes_mm": bottom["modal_amplitudes_mm"],
                "specimen_coordinate_mm": x,
                "reconstructed_displacement_mm": shape,
                "imposed_displacement_mm": imposed,
                "displacement_residual_mm": shape - imposed,
            }
            fig, axes = plt.subplots(2, 1, figsize=(10, 7), sharex=True, constrained_layout=True)
            fig.suptitle(f"Average Shape Reconstruction: {case_id}, {condition}")
            fig._reconstruction_kind = "averaged shape reconstruction"
            fig._output_name = f"{case_id}_{condition}_average_shape"
            axes[0].plot(x, imposed, label="Known Imposed Shape")
            axes[0].plot(x, shape, "--", label="Average-Amplitude Reconstruction")
            axes[0].set_title(f"Mean Amplitudes: A1={amplitudes[0]:.3f}, A2={amplitudes[1]:.3f} mm")
            axes[0].set_ylabel("Displacement (mm)")
            axes[0].legend()
            axes[1].plot(x, shape - imposed)
            axes[1].axhline(0, color="0.5", linewidth=0.7)
            axes[1].set_ylabel("Shape Residual (mm)")
            axes[1].set_xlabel("Centered Specimen Coordinate (mm)")
            for ax in axes:
                ax.grid(alpha=0.25)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_dir", nargs="?", type=Path, default=DATA_DIR)
    parser.add_argument("--roi-file", type=Path, default=ROI_FILE)
    parser.add_argument("--output-dir", type=Path, default=OUTPUT_DIR)
    parser.add_argument("--fig-dir", type=Path, default=FIG_DIR, help="Parent folder for reconstruction figures")
    parser.add_argument("--L-active", type=float, default=L_active, help="Centered ROI length in mm")
    args = parser.parse_args()
    data = load_data(args.data_dir, args.roi_file)
    save_raw_spectra(data, args.fig_dir)
    find_centers(data, args.L_active)
    outputs = reconstruct(data, args.L_active)
    reconstruct_average(outputs)
    offset_outputs = reconstruct_with_offset(data, args.L_active)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for case_id, conditions in outputs.items():
        (args.output_dir / f"{case_id}.json").write_text(
            json.dumps(json_ready(conditions), indent=2, allow_nan=False), encoding="utf-8")
    offset_dir = args.output_dir / "with offset"
    offset_dir.mkdir(parents=True, exist_ok=True)
    for case_id, conditions in offset_outputs.items():
        (offset_dir / f"{case_id}.json").write_text(
            json.dumps(json_ready(conditions), indent=2, allow_nan=False), encoding="utf-8")
    for number in plt.get_fignums():
        fig = plt.figure(number)
        kind = getattr(fig, "_reconstruction_kind", None)
        if kind is None:
            continue
        folder = args.fig_dir / kind
        folder.mkdir(parents=True, exist_ok=True)
        format_figure(fig)
        save_figure(fig, folder / f"{fig._output_name}.png")
    plt.show()
    return outputs


if __name__ == "__main__":
    outputs = main()
