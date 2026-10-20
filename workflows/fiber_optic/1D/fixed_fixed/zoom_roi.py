"""Select and save an unfiltered ROI with its outside end-effect regions."""

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "subroutines"))

import matplotlib.pyplot as plt
import numpy as np
from scipy.signal import savgol_filter

from bending_profile import load_bending_profile


plt.rcParams.update({'font.size': 20,
                     'font.family': 'serif',
                     'font.serif': ['Times New Roman'],
                     }) # Sets global font size

CASE = "k3a0-5_spec2"  # Change this for each recording.
PROFILE_PATH = (
    Path(r"C:\Users\coled_agkeohi\Notre Dame\FTSI F26\fixed-fixed")
    / "outputs/isolated_bending" / f"{CASE}.npz"
)
SAVE_PROFILE = False
SAVE_FIGURE = True
OUTPUT_DIR = PROFILE_PATH.parent.parent / "roi_zoomed" / CASE.split("a", 1)[0]
FIGURE_PATH = OUTPUT_DIR / f"{CASE}_roi.png"
WINDOW_LENGTH = 15  # Odd number of gages; smoothing is only for slope detection.


def isolate_roi(position_m, bending_shift, *, window_length=15):
    """Select two slope crossings as bounds, then a slope crossing as center.

    Smooth only for boundary detection; return the original ROI samples.
    window_length is an odd number of gages.
    """
    x = np.asarray(position_m, dtype=float)
    y = np.asarray(bending_shift, dtype=float)
    if x.ndim != 1 or y.shape != x.shape or not np.all(np.isfinite(x)):
        raise ValueError("ROI selection requires matching 1D arrays and finite positions")
    if np.any(np.diff(x) <= 0):
        raise ValueError("Positions must strictly increase")
    # Filter each valid stretch separately; keep missing gages and their positions.
    smooth = np.full_like(y, np.nan)
    slope = np.full_like(y, np.nan)
    valid = np.flatnonzero(np.isfinite(y))
    for run in np.split(valid, np.flatnonzero(np.diff(valid) > 1) + 1):
        if len(run) >= window_length:
            smooth[run] = savgol_filter(y[run], window_length, 3)
            slope[run] = np.gradient(smooth[run], x[run])

    # Ignore exact zero samples until the next nonzero slope, so a flat
    # plateau yields one crossing instead of multiple duplicate crossings.
    nonzero = np.flatnonzero(np.isfinite(slope) & (slope != 0))
    crossings = []
    for i, j in zip(nonzero[:-1], nonzero[1:]):
        if np.all(np.isfinite(slope[i:j+1])) and np.sign(slope[i]) != np.sign(slope[j]):
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
            ax.set_title(f"Click {label} (snaps to a red crossing)")
            selection_fig.canvas.draw_idle()
            clicks = selection_fig.ginput(1, timeout=0)
            if not clicks:
                raise RuntimeError("ROI selection cancelled before all three points were selected")
            value = clicks[0][0]
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
            "crossings_m": crossings,
            "figure": selection_fig}


def select_end_effect_bounds(roi):
    """Mark the outer end-effect bounds on either side of the primary ROI."""
    fig = roi["figure"]
    ax = fig.axes[0]
    crossings = roi["crossings_m"]
    left, right = roi["bounds_m"]
    selected = []
    for label in ["left end-effect bound", "right end-effect bound"]:
        while True:
            ax.set_title(f"Click {label} (snaps to a red crossing)")
            fig.canvas.draw_idle()
            clicks = fig.ginput(1, timeout=0)
            if not clicks:
                raise RuntimeError("End-effect selection cancelled")
            value = float(crossings[np.argmin(abs(crossings - clicks[0][0]))])
            if (not selected and value >= left) or (selected and value <= right):
                print("Choose the left end-effect bound left of the ROI, or the right bound right of it.")
                continue
            selected.append(value)
            ax.axvline(value, color="orange", linestyle="--")
            break
    left_end, right_end = selected
    ax.axvspan(left_end, left, color="orange", alpha=0.25, label="End-effect regions")
    ax.axvspan(right, right_end, color="orange", alpha=0.25)
    ax.set_title("Selected ROI and end-effect bounds")
    ax.legend()
    fig.canvas.draw_idle()
    print(f"End-effect widths: left {(left-left_end)*1000:.2f} mm; "
          f"right {(right_end-right)*1000:.2f} mm")
    return tuple(selected)


def fit_center_50mm(profile, center_m, case):
    """Fit offset + imposed cosine modes on the physical centered 50 mm span."""
    x, y = profile["position_m"], profile["bending_shift_ghz"]
    bounds = np.array([center_m - 0.025, center_m + 0.025])
    window = (x >= bounds[0]) & (x <= bounds[1])
    position, measured = x[window], y[window]
    modes = np.array(sorted({int(k) for k in re.findall(r"k(\d+)", case)}))
    basis = np.column_stack((np.ones(len(position)),
                             np.cos(2*np.pi*(position[:, None]-center_m)*modes/0.050)))
    valid = np.isfinite(measured)
    coefficients, _, rank, _ = np.linalg.lstsq(basis[valid], measured[valid], rcond=None)
    if rank < basis.shape[1]:
        raise ValueError("Not enough independent samples for the centered 50 mm fit")
    fitted = basis @ coefficients
    return {
        "fit50_bounds_m": bounds, "fit50_length_m": 0.050,
        "fit50_position_m": position, "fit50_measured_shift_ghz": measured,
        "fit50_valid_mask": valid, "fit50_modes": modes,
        "fit50_offset_ghz": coefficients[0], "fit50_cosine_coefficients_ghz": coefficients[1:],
        "fit50_fitted_shift_ghz": fitted,
        "fit50_rmse_ghz": np.sqrt(np.mean((measured[valid]-fitted[valid])**2)),
    }


def plot_selection(profile, selection):
    """Show the original profile and centered 50 mm window."""
    x, y = profile["position_m"], profile["bending_shift_ghz"]
    left, right = selection["bounds_m"]
    left_end, right_end = selection["end_effect_bounds_m"]
    center = selection["center_m"]
    fig, ax = plt.subplots(figsize=(12, 5), constrained_layout=True)
    ax.plot(x, y, color="0.6", linewidth=1)
    window_left, window_right = center - 0.025, center + 0.025
    mask = (x >= window_left) & (x <= window_right)
    ax.plot(x[mask], y[mask], color="tab:blue", linewidth=2, label="Centered 50 mm window")
    ax.axvspan(window_left, window_right, color="tab:blue", alpha=0.15)
    ax.axvline(center, color="green", linestyle="--", label="Detected center")
    for boundary in (window_left, window_right):
        ax.axvline(boundary, color="purple", linestyle=":")
    ax.set_xlim(window_left - 0.005, window_right + 0.005)
    ax.set_xlabel("Fiber position (m)")
    ax.set_ylabel("Bending spectral shift (GHz)")
    ax.set_title("50mm Center-Fit ROI, $A_3$ = 50mm")
    ax.grid(alpha=0.25)
    ax.legend()
    print(f"\nPrimary ROI length: {(right-left)*1000:.2f} mm")
    print(f"Detected center: {center:.6f} m "
          f"({(center-left)*1000:.2f} mm from left ROI bound)")
    print(f"Left end-effect length: {(left-left_end)*1000:.2f} mm")
    print(f"Right end-effect length: {(right_end-right)*1000:.2f} mm")
    return fig


def save_zoomed_profile(path, profile, selection, source_path):
    """Save original samples spanning both end effects, with a primary ROI mask."""
    x = profile["position_m"]
    left, right = selection["bounds_m"]
    left_end, right_end = selection["end_effect_bounds_m"]
    crop = (x >= left_end) & (x <= right_end)
    position = x[crop]
    arrays = {name: profile[name][crop] for name in (
        "position_m", "bending_shift_ghz", "top_tared_shift_ghz",
        "bottom_tared_shift_ghz",
    )}
    metadata = dict(profile["metadata"])
    metadata.update(profile_kind="roi_zoomed", source_profile=str(source_path),
                    spatial_filter_applied=False,
                    fit50_basis="offset + sum(a_k*cos(2*pi*k*(x-center_m)/0.050))",
                    selection_filter={"window_length": WINDOW_LENGTH, "polyorder": 3})
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(
        path, **arrays,
        **fit_center_50mm(profile, selection["center_m"], Path(source_path).stem),
        roi_mask=(position >= left) & (position <= right),
        left_end_effect_mask=position < left,
        right_end_effect_mask=position > right,
        bounds_m=selection["bounds_m"], center_m=selection["center_m"],
        end_effect_bounds_m=selection["end_effect_bounds_m"],
        roi_length_m=right-left,
        end_effect_lengths_m=[left-left_end, right_end-right],
        metadata_json=json.dumps(metadata),
    )
    print(f"Saved zoomed profile: {path}")
    return path


if __name__ == "__main__":
    profile = load_bending_profile(PROFILE_PATH)
    selection = isolate_roi(profile["position_m"], profile["bending_shift_ghz"],
                            window_length=WINDOW_LENGTH)
    selection["end_effect_bounds_m"] = select_end_effect_bounds(selection)
    summary_fig = plot_selection(profile, selection)
    if SAVE_FIGURE:
        FIGURE_PATH.parent.mkdir(parents=True, exist_ok=True)
        summary_fig.savefig(FIGURE_PATH, dpi=300, bbox_inches="tight")
        print(f"Saved ROI figure: {FIGURE_PATH}")
    if SAVE_PROFILE:
        save_zoomed_profile(OUTPUT_DIR / PROFILE_PATH.name, profile, selection, PROFILE_PATH)
    plt.show()
