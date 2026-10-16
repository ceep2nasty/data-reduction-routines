"""Separate membrane/bending optical shifts over the original selected ROIs.

Assumes equal sensor sensitivity and symmetric offsets from the neutral surface.
Outputs remain GHz; no optical-shift-to-strain calibration is applied.
Shape reconstruction fits empirical bending-shift bases from the two 1 mm
single-mode cases, so no strain calibration is required.
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

OUTPUT_DIR = Path(__file__).with_name("cos_basis_v2_decomposition")
FIG_DIR = Path(r"C:\Users\coled\Notre Dame\FTSI F26\progress reports\10OCT2026\figs\decomposed composition")


def decompose(data):
    """Use top-pass positions within the full centered top/bottom ROI overlap."""
    outputs = {}
    for case_id, conditions in data.items():
        outputs[case_id] = {}
        for condition, entry in conditions.items():
            surfaces = {}
            for pid, directions in entry["passes"].items():
                for direction, p in directions.items():
                    surface = p["surface"]
                    if surface in surfaces:
                        raise ValueError(f"Multiple {surface} passes: {case_id}, {condition}")
                    surfaces[surface] = (pid, direction, p)
            if set(surfaces) != {"top", "bottom"}:
                raise ValueError(f"Need one top and one bottom pass: {case_id}, {condition}")
            top, bottom = surfaces["top"][2], surfaces["bottom"][2]
            xt = top["distance_mm"] - top["center_mm"]
            xb = bottom["distance_mm"] - bottom["center_mm"]
            overlap = (xt >= xb[0]) & (xt <= xb[-1])
            x = xt[overlap]
            if len(x) < 2:
                raise ValueError(f"No usable ROI overlap: {case_id}, {condition}")
            yt = top["mean_spectral_shift_ghz"][overlap]
            yb = np.interp(x, xb, bottom["mean_spectral_shift_ghz"], left=np.nan, right=np.nan)
            if not np.any(np.isfinite(yt) & np.isfinite(yb)):
                raise ValueError(f"No paired finite measurements: {case_id}, {condition}")
            result = {
                "units": {"distance": "mm", "optical_shift": "GHz"},
                "definition": "membrane=(top+bottom)/2; bending=(top-bottom)/2",
                "centered_distance_mm": x,
                "top_shift_ghz": yt, "bottom_shift_ghz": yb,
                "membrane_shift_ghz": (yt + yb) / 2,
                "bending_shift_ghz": (yt - yb) / 2,
                "sources": {},
            }
            for surface, (pid, direction, p) in surfaces.items():
                result["sources"][surface] = {
                    "source_file": str(entry["full_data"]["source_file"]),
                    "pass_id": pid, "direction": direction,
                    "center_mm": p["center_mm"], "bounds_mm": p["roi"]["bounds_mm"],
                    "centered_distance_mm": p["distance_mm"] - p["center_mm"],
                    "mean_spectral_shift_ghz": p["mean_spectral_shift_ghz"],
                }
            entry["strain_components"] = result
            outputs[case_id][condition] = result
    return outputs


def reconstruct_bending_shape(outputs, active_length=L_active):
    """Attach cosine shapes fitted to decomposed bending optical shifts.

    Like reconstruct_cos_basis_v2, k1_a1 and k2_a1 calibrate the modal
    amplitudes in mm. Fit their bending components, rather than individual
    surface profiles, over the centered active overlap. A constant optical
    offset is not fitted. Displacement uses the specimen coordinate and
    the cosine basis fixes its rigid displacement and tilt.
    """
    if not np.isfinite(active_length) or active_length <= 0:
        raise ValueError("Active length must be finite and positive")
    known_amplitudes = {"k1_a1": [1.0, 0.0], "k2_a1": [0.0, 1.0],
                        "k1_a2": [2.0, 0.0], "k1_a2_k2_a1": [2.0, 1.0]}
    for case_id, conditions in outputs.items():
        for condition, result in conditions.items():
            bases = [outputs[case][condition] for case in ("k1_a1", "k2_a1")]
            x = np.asarray(result["centered_distance_mm"], dtype=float)
            y = np.asarray(result["bending_shift_ghz"], dtype=float)
            design = np.column_stack([
                np.interp(x, basis["centered_distance_mm"], basis["bending_shift_ghz"],
                          left=np.nan, right=np.nan) for basis in bases
            ])
            keep = ((np.abs(x) <= active_length / 2) & np.isfinite(y)
                    & np.all(np.isfinite(design), axis=1))
            if keep.sum() < 3:
                raise ValueError(f"Not enough finite bending overlap: {case_id}, {condition}")
            amplitudes, _, rank, singular = np.linalg.lstsq(design[keep], y[keep], rcond=None)
            if rank < 2:
                raise ValueError(f"Bending bases are linearly dependent: {case_id}, {condition}")
            prediction = design[keep] @ amplitudes
            residual = y[keep] - prediction
            shape_x = np.linspace(-active_length / 2, active_length / 2, 501)
            shape_basis = np.cos(2 * np.pi * (shape_x[:, None] / active_length + 0.5)
                                 * np.array([1, 2]))
            shape = shape_basis @ amplitudes
            reconstruction = {
                "units": {"distance": "mm", "displacement": "mm", "optical_shift": "GHz"},
                "basis_cases": ["k1_a1", "k2_a1"],
                "coefficients": amplitudes, "modal_amplitudes_mm": amplitudes,
                "L_active_mm": active_length,
                "centered_distance_mm": x[keep], "measured_bending_shift_ghz": y[keep],
                "basis_bending_shift_ghz": design[keep],
                "reconstructed_bending_shift_ghz": prediction, "residual_ghz": residual,
                "rms_ghz": float(np.sqrt(np.mean(residual**2))),
                "basis_condition_number": float(singular[0] / singular[-1]),
                "specimen_coordinate_mm": shape_x, "reconstructed_displacement_mm": shape,
            }
            if case_id in known_amplitudes:
                imposed = np.asarray(known_amplitudes[case_id])
                reconstruction.update({
                    "imposed_modal_amplitudes_mm": imposed,
                    "imposed_displacement_mm": shape_basis @ imposed,
                    "displacement_residual_mm": shape - shape_basis @ imposed,
                })
            result["shape_reconstruction"] = reconstruction
    return outputs


def plot_bending_shapes(outputs):
    """Plot Fixed-Fixed shapes above reconstructed-minus-imposed residuals."""
    for case_id, conditions in outputs.items():
        fig, axes = plt.subplots(2, 1, squeeze=False,
                                 figsize=(10, 7), sharex="col",
                                 constrained_layout=True)
        fig.suptitle(f"Bending shape reconstruction: {case_id}, constrained")
        fig._output_name = f"{case_id}_bending_shape_reconstruction"
        for col, (condition, result) in enumerate((("constrained", conditions["constrained"]),)):
            r = result["shape_reconstruction"]
            shape_x = r["specimen_coordinate_mm"]
            if "imposed_displacement_mm" in r:
                axes[0, col].plot(shape_x, r["imposed_displacement_mm"], label="Known imposed shape")
                axes[1, col].plot(shape_x, r["displacement_residual_mm"])
            axes[0, col].plot(shape_x, r["reconstructed_displacement_mm"], "--", label="Reconstructed shape")
            axes[0, col].set_ylabel("Displacement (mm)")
            axes[0, col].legend()
            a = r["modal_amplitudes_mm"]
            axes[0, col].set_title(f"{condition}: A1={a[0]:.3f}, A2={a[1]:.3f} mm")
            axes[1, col].axhline(0, color="0.5", linewidth=0.7)
            axes[1, col].set_ylabel("Shape residual (mm)")
            axes[1, col].set_xlabel("Centered specimen coordinate (mm)")
            for ax in axes[:, col]:
                ax.grid(alpha=0.25)


def json_ready(value):
    """Preserve missing values as JSON null rather than nonstandard NaN."""
    if isinstance(value, np.ndarray):
        return json_ready(value.tolist())
    if isinstance(value, dict):
        return {k: json_ready(v) for k, v in value.items()}
    if isinstance(value, list):
        return [json_ready(v) for v in value]
    if isinstance(value, float) and not np.isfinite(value):
        return None
    return value


def save_outputs(outputs, output_dir=OUTPUT_DIR):
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    for case_id, conditions in outputs.items():
        path = output_dir / f"{case_id}.json"
        path.write_text(json.dumps(json_ready(conditions), indent=2, allow_nan=False), encoding="utf-8")
        print(f"Saved {path}")


def plot_outputs(outputs):
    for case_id, conditions in outputs.items():
        fig, axes = plt.subplots(3, 2, figsize=(13, 10), constrained_layout=True)
        fig.suptitle(case_id)
        fig._output_name = f"{case_id}_decomposition"
        for col, condition in enumerate(("unconstrained", "constrained")):
            r = conditions[condition]
            for surface, source in r["sources"].items():
                axes[0, col].plot(source["centered_distance_mm"],
                                  source["mean_spectral_shift_ghz"], label=surface)
            axes[0, col].set_title(f"{condition}: original ROI profiles")
            axes[0, col].legend()
            for row, component in ((1, "membrane"), (2, "bending")):
                axes[row, col].plot(r["centered_distance_mm"], r[f"{component}_shift_ghz"])
                axes[row, col].set_title(f"{component.capitalize()} optical shift")
            for ax in axes[:, col]:
                ax.set_xlabel("Distance from detected center (mm)")
                ax.set_ylabel("Optical shift (GHz)")
                ax.axhline(0, color="0.5", linewidth=0.7)
                ax.grid(alpha=0.25)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_dir", nargs="?", type=Path, default=DATA_DIR)
    parser.add_argument("--roi-file", type=Path, default=ROI_FILE)
    parser.add_argument("--output-dir", type=Path, default=OUTPUT_DIR)
    parser.add_argument("--fig-dir", type=Path, default=FIG_DIR, help="Folder for shape reconstruction figures")
    parser.add_argument("--L-active", type=float, default=L_active, help="Center-finding and reconstruction length in mm")
    args = parser.parse_args()
    data = load_data(args.data_dir, args.roi_file)
    find_centers(data, args.L_active)
    data = {case_id: {"constrained": conditions["constrained"]}
            for case_id, conditions in data.items()}
    outputs = decompose(data)
    reconstruct_bending_shape(outputs, args.L_active)
    save_outputs(outputs, args.output_dir)
    plot_bending_shapes(outputs)
    args.fig_dir.mkdir(parents=True, exist_ok=True)
    for number in plt.get_fignums():
        fig = plt.figure(number)
        format_figure(fig)
        if hasattr(fig, "_output_name"):
            save_figure(fig, args.fig_dir / f"{fig._output_name}.png")
    plt.show()
    return outputs


if __name__ == "__main__":
    outputs = main()
