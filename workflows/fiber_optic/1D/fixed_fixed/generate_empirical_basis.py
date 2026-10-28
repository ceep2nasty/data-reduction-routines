"""Build an empirical optical-shift basis from the 0.5 mm k1 and k2 cases.

Plot and save the linearly detrended empirical basis and its matrix.
"""

import json
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

from scipy.signal import detrend


OUTPUT_ROOT = Path(r"C:\Users\coled_agkeohi\Notre Dame\FTSI F26\fixed-fixed\outputs")
CASES = {1: "k1a0-5_spec2", 2: "k2a0-5_spec2"}
SPAN_M = 0.050
REFERENCE_AMPLITUDE_MM = 0.5
GENERATE_BASIS = False
SAVE_BASIS = True
SAVE_FIGURES = True
BASIS_DIR = OUTPUT_ROOT / "basis_cal" / "k1_k2"

plt.rcParams.update({'font.size': 20,
                     'font.family': 'serif',
                     'font.serif': ['Times New Roman'],
                     }) # Sets global font size

def load_case(path):
    """Load the archive, including ROI masks and selected center."""
    with np.load(path, allow_pickle=False) as archive:
        data = {name: archive[name] for name in archive.files}
    data["metadata"] = json.loads(data.pop("metadata_json").item())
    return data


def select_region(data):
    """Return finite, unfiltered samples in the saved centered 50 mm window.

    Positions are meters relative to the selected center; shifts are GHz.
    Region selection is kept here so a future ROI switch stays separate
    from the scientific calculation. Saved cosine predictions are not used.
    """
    position = data["fit50_position_m"] - float(data["center_m"])
    shift = data["fit50_measured_shift_ghz"]
    valid = np.isfinite(position) & np.isfinite(shift)
    return position[valid], shift[valid]


def build_empirical_basis_column(bending_shift_ghz, reference_amplitude_mm):
    """Outputs sprectral shift basis column in shift/mm for a given mode"""
    basis_ghz_per_mm = bending_shift_ghz / reference_amplitude_mm

    return basis_ghz_per_mm




def save_basis(path, arrays):
    """Save numerical results and provenance without serializing Python objects."""
    metadata = {
        "format_version": 1, "span_m": SPAN_M,
        "reference_amplitude_mm": REFERENCE_AMPLITUDE_MM,
        "source_profiles": [str(OUTPUT_ROOT / "roi_zoomed" / f"k{mode}" / f"{case}.npz")
                            for mode, case in CASES.items()],
        "basis_units": "GHz/mm", "position_reference": "selected center",
        "region": "centered_50mm",
        "linear_detrend": True,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(path, **arrays, metadata_json=json.dumps(metadata))
    print(f"Saved {path}")

def detrend_basis(cal):

    return

def main():
    profiles = []
    fig, axes = plt.subplots(len(CASES), 1, figsize=(10, 9), constrained_layout=True)
    for ax, (mode, case) in zip(np.atleast_1d(axes), CASES.items()):
        source = OUTPUT_ROOT / "roi_zoomed" / f"k{mode}" / f"{case}.npz"
        data = load_case(source)
        position, shift = select_region(data)
        column = build_empirical_basis_column(shift, reference_amplitude_mm=REFERENCE_AMPLITUDE_MM)
        profiles.append((position, column))


        ax.set_title(rf"$A_{mode} = {REFERENCE_AMPLITUDE_MM:g}\,\mathrm{{mm}}$")
        ax.grid(alpha=0.25)
        print(f"{case}: {len(position)} valid gages in centered 50 mm window")


    left = max(position[0] for position, column in profiles)
    right = min(position[-1] for position, column in profiles)

    spacing = max(
        np.median(np.diff(position))
        for position, column in profiles
    )
    count = int(np.floor((right - left) / spacing)) + 1
    common_position = np.linspace(left, right, count)

    B = np.column_stack([
        np.interp(common_position, position, column)
        for position, column in profiles
    ])
    B_original = B.copy()
    B = detrend(B_original, axis = 0 , type = "linear")
    removed_trend = B_original - B


    matrix_fig, matrix_ax = plt.subplots(figsize=(6, 7), constrained_layout=True)
    limit = np.max(np.abs(B))
    image = matrix_ax.imshow(
        B, origin="lower", aspect="auto", interpolation="nearest",
        extent=(0.5, len(CASES) + 0.5, left * 1000, right * 1000),
        cmap="RdBu_r", vmin=-limit, vmax=limit,
    )
    matrix_ax.set_xticks(np.arange(1, len(CASES) + 1),
                         [f"k{mode}" for mode in CASES])
    matrix_ax.set(xlabel="Basis column", ylabel="Position relative to center (mm)",
                  title="Empirical Shift Basis Matrix")
    matrix_fig.colorbar(image, ax=matrix_ax, label="Basis (GHz/mm)")
    print(f"B shape: {B.shape}; shared span: {(right-left)*1000:.3f} mm; "
          f"grid spacing: {np.diff(common_position).mean()*1000:.3f} mm")

    for index, ax in enumerate(np.atleast_1d(axes)):
        ax.plot(
            common_position * 1000,
            B[:, index],
            color="tab:blue",
            linewidth=1.5,
        )

    fig.supxlabel("Position relative to center (mm)")
    fig.supylabel("Basis (GHz/mm)")

    if SAVE_BASIS:
        save_basis(BASIS_DIR / "shift_basis.npz", {
            "position_m": common_position,
            "basis_ghz_per_mm": B,
            "modes": np.array(list(CASES)),
        })
    if SAVE_FIGURES:
        BASIS_DIR.mkdir(parents=True, exist_ok=True)
        fig.savefig(BASIS_DIR / "basis_columns.png", dpi=200, bbox_inches="tight")
        matrix_fig.savefig(BASIS_DIR / "basis_matrix.png", dpi=200, bbox_inches="tight")
        print(f"Saved figures to {BASIS_DIR}")

    plt.show()


if __name__ == "__main__":
    main()
