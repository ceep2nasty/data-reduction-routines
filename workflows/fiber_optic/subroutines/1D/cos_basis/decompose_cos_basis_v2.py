"""Separate membrane/bending optical shifts over the original selected ROIs.

Assumes equal sensor sensitivity and symmetric offsets from the neutral surface.
Outputs remain GHz; no optical-shift-to-strain calibration is applied.
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
from cos_plot_labels import format_figure
import numpy as np

from process_cos_basis_v2 import DATA_DIR, ROI_FILE, L_active, load_data, find_centers

OUTPUT_DIR = Path(__file__).with_name("cos_basis_v2_decomposition")


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
    parser.add_argument("--L-active", type=float, default=L_active, help="Center-finding length in mm only")
    args = parser.parse_args()
    data = load_data(args.data_dir, args.roi_file)
    find_centers(data, args.L_active)
    outputs = decompose(data)
    save_outputs(outputs, args.output_dir)
    plot_outputs(outputs)
    for number in plt.get_fignums():
        format_figure(plt.figure(number))
    plt.show()
    return outputs


if __name__ == "__main__":
    outputs = main()
