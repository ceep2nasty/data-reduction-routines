"""Load flat references and test Pass spectra for tare comparison."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "subroutines"))

import numpy as np
import matplotlib.pyplot as plt
from scipy.signal import savgol_filter

from load_fos_case import read_fos_tsv

plt.rcParams.update({'font.size': 20,
                     'font.family': 'serif',
                     'font.serif': ['Times New Roman'],
                     }) # Sets global font size


DATA_DIR = Path(r"Z:\Cole\FTSI\Luna_Data\fixed_fixed\outputs\roi extended")
FLAT_TOP_FILE = (
    DATA_DIR / "spec2/top/flat"
    / "flat_spec2_top_roi_extended.tsv"
)
FLAT_BOTTOM_FILE = (
    DATA_DIR / "spec2/bottom/flat"
    / "flat_spec2_bottom_roi_extended.tsv"
)
# Replace these paths to compare other recordings.
TOP_FILE = (
    DATA_DIR / "spec2/top/k1"
    / "k1a0-5_spec2_top_roi_extended.tsv"
)
BOTTOM_FILE = (
    DATA_DIR / "spec2/bottom/k1"
    / "k1a0-5_spec2_bottom_roi_extended.tsv"
)

save = False
SAVE_DIR = Path(r"Z:\Cole\FTSI\Luna_Data\fixed_fixed")
save_filename = "k1a2"
save_path = (SAVE_DIR / "outputs" / "isolated_bending_figs" / save_filename )


def mean_profile(recording):
    """Time-average each gage, retaining NaN for all-missing gages."""
    shift = recording["spectral_shift_ghz"]
    count = np.sum(~np.isnan(shift), axis=0)
    return np.divide(
        np.nansum(shift, axis=0), count,
        out=np.full(shift.shape[1], np.nan), where=count > 0,
    )

def isolate_bending(FLAT_TOP_FILE, FLAT_BOTTOM_FILE, TOP_FILE, BOTTOM_FILE):
    flat_top = read_fos_tsv(FLAT_TOP_FILE, segment="Pass")
    flat_bottom = read_fos_tsv(FLAT_BOTTOM_FILE, segment="Pass")
    top = read_fos_tsv(TOP_FILE, segment="Pass")
    bottom = read_fos_tsv(BOTTOM_FILE, segment="Pass")

    top_tared = mean_profile(top) - mean_profile(flat_top)
    bottom_tared = mean_profile(bottom) - mean_profile(flat_bottom)
    bending_shift = (bottom_tared - top_tared) / 2

    return bending_shift

def isolate_roi(position_m, bending_shift, *, window_length=15):
    """Select two slope crossings as bounds, then freely select a center.

    Smooth only for boundary detection; return the original ROI samples.
    window_length is an odd number of gages.
    """
    x = np.asarray(position_m, dtype=float)
    y = np.asarray(bending_shift, dtype=float)
    if x.ndim != 1 or y.shape != x.shape or not np.all(np.isfinite(x)) or not np.all(np.isfinite(y)):
        raise ValueError("ROI selection requires matching finite 1D arrays")
    if np.any(np.diff(x) <= 0):
        raise ValueError("Positions must strictly increase")
    smooth = savgol_filter(y, window_length, 3)
    slope = np.gradient(smooth, x)

    # Ignore exact zero samples until the next nonzero slope, so a flat
    # plateau yields one crossing instead of multiple duplicate crossings.
    nonzero = np.flatnonzero(slope != 0)
    crossings = []
    for i, j in zip(nonzero[:-1], nonzero[1:]):
        if np.sign(slope[i]) != np.sign(slope[j]):
            crossings.append(x[i] - slope[i] * (x[j] - x[i]) / (slope[j] - slope[i]))
    crossings = np.asarray(crossings)
    if len(crossings) < 2:
        raise ValueError("At least two slope zero-crossings are required")
    selection_fig, ax = plt.subplots(figsize=(12, 5), constrained_layout=True)
    ax.plot(x, y, color="0.7", label="Raw bending profile")
    ax.plot(x, smooth, label="Smoothed profile")
    ax.scatter(crossings, np.interp(crossings, x, smooth),
               color="red", zorder=3, label="Slope zero-crossings")
    ax.set_xlabel("Fiber position (m)")
    ax.set_ylabel("Spectral shift (GHz)")
    ax.grid(alpha=0.25)
    ax.legend()
    selected = []
    for label in ["left bound", "right bound", "center"]:
        while True:
            ax.set_title(f"Click {label}" + (" (snaps to a red crossing)" if label != "center" else " (within bounds)"))
            selection_fig.canvas.draw_idle()
            clicks = selection_fig.ginput(1, timeout=0)
            if not clicks:
                raise RuntimeError("ROI selection cancelled before all three points were selected")
            value = clicks[0][0]
            if label != "center":
                value = crossings[np.argmin(np.abs(crossings - value))]
            if label == "right bound" and value <= selected[0]:
                print("Choose a right bound to the right of the left bound.")
                continue
            if label == "center" and not selected[0] < value < selected[1]:
                print("Choose a center inside the selected bounds.")
                continue
            selected.append(float(value))
            ax.axvline(value, color="green" if label == "center" else "black", linestyle="--")
            break
    bounds = tuple(selected[:2])
    center_m = selected[2]
    mask = (x >= bounds[0]) & (x <= bounds[1])
    length_m = bounds[1] - bounds[0]
    print(f"ROI length: {length_m:.6f} m ({length_m * 1000:.2f} mm); "
          f"stored samples: {np.count_nonzero(mask)}")
    print(f"Center from left bound: {(center_m - bounds[0]) * 1000:.2f} mm; "
          f"from right bound: {(bounds[1] - center_m) * 1000:.2f} mm")
    ax.axvspan(*bounds, alpha=0.1, color="green")
    ax.set_title(f"Selected ROI: {length_m * 1000:.2f} mm")
    selection_fig.canvas.draw_idle()
    return {"position_m": x[mask], "spectral_shift_ghz": y[mask],
            "bounds_m": bounds, "smoothed_shift_ghz": smooth,
            "length_m": length_m, "center_m": center_m,
            "center_from_left_mm": (center_m - bounds[0]) * 1000,
            "center_from_right_mm": (bounds[1] - center_m) * 1000,
            "figure": selection_fig}






if __name__ == "__main__":
    flat_top = read_fos_tsv(FLAT_TOP_FILE, segment="Pass")
    flat_bottom = read_fos_tsv(FLAT_BOTTOM_FILE, segment="Pass")
    top = read_fos_tsv(TOP_FILE, segment="Pass")
    bottom = read_fos_tsv(BOTTOM_FILE, segment="Pass")

    fig, axes = plt.subplots(1, 2, figsize=(18, 4), constrained_layout=True)
    for ax, recording, flat, title in zip(
        axes, [top, bottom], [flat_top, flat_bottom],
        ["Fiber on top", "Fiber on bottom"],
    ):
        position_m = recording["position_m"]
        if not np.array_equal(position_m, flat["position_m"]):
            raise ValueError(f"{title}: test and flat gage positions must match")
        raw = mean_profile(recording)
        tared = raw - mean_profile(flat)
        ax.plot(position_m, raw, label="Raw", linewidth=1)
        ax.plot(position_m, tared, label="Tared", linewidth=1)
        ax.set_xlabel("Fiber position (m)")
        ax.set_title(title)
        ax.grid(alpha=0.25)
        ax.legend()

    fig.supylabel("Time-averaged spectral shift (GHz)")

    if not np.array_equal(top["position_m"], bottom["position_m"]):
        raise ValueError("Top and bottom gage positions must match")
    top_tared = mean_profile(top) - mean_profile(flat_top)
    bottom_tared = mean_profile(bottom) - mean_profile(flat_bottom)
    bending_shift = (bottom_tared - top_tared) / 2

    bending_fig, bending_ax = plt.subplots(figsize=(9, 4), constrained_layout=True)
    bending_ax.plot(top["position_m"], bending_shift, linewidth=1)
    bending_ax.set_xlabel("Fiber position (m)")
    bending_ax.set_ylabel("Spectral shift (GHz)")
    bending_ax.set_title("Bending component: (bottom - top) / 2")
    bending_ax.grid(alpha=0.25)
    roi = isolate_roi(top["position_m"], bending_shift)
    roi_fig, roi_ax = plt.subplots(figsize=(9, 4), constrained_layout=True)
    roi_ax.plot(top["position_m"], bending_shift, color="0.7", label="Full profile")
    roi_ax.plot(roi["position_m"], roi["spectral_shift_ghz"], label="ROI", linewidth=2)
    for boundary in roi["bounds_m"]:
        roi_ax.axvline(boundary, color="black", linestyle="--", linewidth=1)
    roi_ax.set_xlabel("Fiber position (m)")
    roi_ax.set_ylabel("Spectral shift (GHz)")
    roi_ax.axvline(roi["center_m"], color="green", linestyle="--", label="Selected center")
    roi_ax.set_title("ROI detected from slope zero-crossings")
    roi_ax.grid(alpha=0.25)
    roi_ax.legend()
    if save:
        save_path.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(save_path.with_name("k1a2_tare.png"), dpi=300, bbox_inches="tight")
        bending_fig.savefig(save_path.with_name("k1_a2_isolated_bending.png"), dpi=300, bbox_inches="tight")
        roi_fig.savefig(save_path.with_name(f"{save_filename}_roi.png"), dpi=300, bbox_inches="tight")
    plt.show()
