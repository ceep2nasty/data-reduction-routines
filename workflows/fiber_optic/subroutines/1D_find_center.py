"""Find centers from time-averaged profiles and crop all original time samples.

Call center_rois() with data or a JSON path from select_luna_rois.py. Each
pass is averaged independently, ignoring missing readings. Save only the active
window in a six-field format with position_mm from 0 to active length in mm.
The temporal average is used only to find the center, not as the saved signal.
"""

import json
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

from select_luna_rois import save_recording


SMOOTHING_POINTS = 5  # Odd moving-average width; 1 disables spatial smoothing.


def find_center(position_m, spectral_shift_ghz, roi_bounds_m, active_length_m,
                smoothing_points=SMOOTHING_POINTS):
    """Find a smoothed slope zero crossing nearest the estimated ROI midpoint.

    Apply a short centered moving average to the mean profile, then compute
    its slope on the original spatial grid. Interpolate sign changes to locate
    zero crossings between gages. Missing data and incomplete edge windows are
    excluded, not bridged. Raise if there is no crossing instead of choosing
    a nonzero slope. Smoothing affects center detection only.

    Return inclusive bounds and indices, plus positions relative to the center.
    The active window may extend beyond the estimated ROI, but must fit within
    the recorded fiber. Supply the time-averaged profile here; the returned
    indices can slice every original time sample of the recording.
    """
    x = np.asarray(position_m, dtype=float)
    nu = np.asarray(spectral_shift_ghz, dtype=float)
    bounds = np.asarray(roi_bounds_m, dtype=float)
    if x.ndim != 1 or len(x) < 3 or not np.all(np.isfinite(x)) or np.any(np.diff(x) <= 0):
        raise ValueError("Positions must contain at least three finite, increasing values")
    if nu.shape != x.shape or np.any(np.isinf(nu)):
        raise ValueError("Supply one spectral-shift sample matching the position array")
    if bounds.shape != (2,) or not np.all(np.isfinite(bounds)) or bounds[0] >= bounds[1]:
        raise ValueError("ROI bounds must be two finite, increasing positions")
    if not np.isfinite(active_length_m) or active_length_m <= 0:
        raise ValueError("Active length must be finite and positive")
    if (not isinstance(smoothing_points, int) or smoothing_points < 1 or
            smoothing_points % 2 == 0 or smoothing_points > len(x) - 2):
        raise ValueError("Smoothing points must be positive, odd, and leave at least three full windows")

    smooth = np.full(len(x), np.nan)
    half = smoothing_points // 2
    windows = np.lib.stride_tricks.sliding_window_view(nu, smoothing_points)
    smooth[half:len(x) - half] = np.mean(windows, axis=1)
    slope = np.gradient(smooth, x)
    finite_values = np.abs(smooth[np.isfinite(smooth)])
    scale = float(np.max(finite_values)) if len(finite_values) else 0.0
    tolerance = 32 * np.finfo(float).eps * scale / np.min(np.diff(x))
    slope[np.abs(slope) <= tolerance] = 0  # Ignore roundoff on flat profiles.
    valid = np.zeros(len(x), dtype=bool)
    valid[1:-1] = np.isfinite(smooth[:-2]) & np.isfinite(smooth[1:-1]) & np.isfinite(smooth[2:])
    valid &= np.isfinite(slope) & (x >= bounds[0]) & (x <= bounds[1])
    # Consecutive nonzero slopes may enclose exact-zero plateaus, but never gaps.
    nonzero = np.flatnonzero(valid & (slope != 0))
    crossings = []
    for i, j in zip(nonzero[:-1], nonzero[1:]):
        if np.all(valid[i:j + 1]) and np.signbit(slope[i]) != np.signbit(slope[j]):
            if j == i + 1:
                crossings.append(float(x[i] - slope[i] * (x[j] - x[i]) / (slope[j] - slope[i])))
            else:
                crossings.append(float((x[i + 1] + x[j - 1]) / 2))
    if not crossings:
        raise ValueError("No slope zero crossing in ROI; adjust the ROI or smoothing width")
    midpoint = float(np.mean(bounds))
    center = min(crossings, key=lambda value: abs(value - midpoint))
    center_index = int(np.argmin(np.abs(x - center)))
    left, right = center - active_length_m / 2, center + active_length_m / 2
    if left < x[0] or right > x[-1]:
        raise ValueError("Centered active length extends beyond the recorded fiber")
    indices = np.flatnonzero((x >= left) & (x <= right))
    if len(indices) < 2:
        raise ValueError("Active window contains fewer than two measured positions")
    return {
        "center_m": center,
        "center_index": center_index,  # Nearest gage; center may lie between gages.
        "smoothing_points": smoothing_points,
        "active_length_m": float(active_length_m),
        "bounds_m": [left, right],
        "indices": indices.tolist(),
        "position_relative_m": (x[indices] - center).tolist(),
    }


def trim_to_active_length(data, active_length_m, smoothing_points=SMOOTHING_POINTS, *, padding_m=0.0):
    """Return a centered, optionally padded profile and coordinate metadata.

    Each pass is processed separately so derivatives never cross ROI gaps.
    Bounds include optional padding beyond center +/- half the active length; only measured positions
    inside those inclusive bounds are retained, without interpolation.
    Output position_mm uses the active window's left boundary as zero.
    Input positions and active_length_m remain in meters.
    """
    if not data["position_m"]:
        raise ValueError("Input has no selected ROIs")
    output = {key: data[key] for key in ("gage_pitch_mm", "test_name", "sampling_rate_hz", "time_s")}
    output.update(position_mm={}, spectral_shift_ghz={})
    centers = {}
    for name, positions in data["position_m"].items():
        x = np.asarray(positions, dtype=float)
        shifts = np.asarray(data["spectral_shift_ghz"][name], dtype=float)
        if x.ndim != 1 or len(x) < 3:
            raise ValueError(f"{name}: need at least three positions")
        if shifts.shape != (len(data["time_s"]), len(x)) or not len(shifts) or np.any(np.isinf(shifts)):
            raise ValueError(f"{name}: invalid time-by-position array")
        count = np.sum(np.isfinite(shifts), axis=0)
        mean = np.divide(np.nansum(shifts, axis=0), count,
                         out=np.full(len(x), np.nan), where=count > 0)
        try:
            result = find_center(x, mean, [x[0], x[-1]], active_length_m, smoothing_points)
        except ValueError as exc:
            raise ValueError(f"{name}: {exc}") from exc
        if padding_m < 0:
            raise ValueError("Padding must be nonnegative")
        retained_bounds = [result["bounds_m"][0] - padding_m, result["bounds_m"][1] + padding_m]
        if retained_bounds[0] < x[0] or retained_bounds[1] > x[-1]:
            raise ValueError(f"{name}: selected ROI does not cover the requested padding")
        indices = np.flatnonzero((x >= retained_bounds[0]) & (x <= retained_bounds[1]))
        result["retained_bounds_m"] = retained_bounds
        result["padding_m"] = padding_m
        result["retained_indices"] = indices.tolist()
        output["position_mm"][name] = (x[indices] - result["bounds_m"][0]) * 1000
        output["spectral_shift_ghz"][name] = shifts[:, indices]
        centers[name] = result
    output["centers"] = centers
    output["coordinate_convention"] = "Reference fiber distance from detected center plus active_length/2; not horizontal position"
    return output, centers


def plot_centered_spectra(data, centers):
    """Show trimmed mean profiles in active-window coordinates (millimeters)."""
    fig, axes = plt.subplots(len(centers), 1, squeeze=False,
                             figsize=(9, 3 * len(centers)), constrained_layout=True)
    for ax, (name, result) in zip(axes[:, 0], centers.items()):
        x = np.asarray(data["position_mm"][name])
        shifts = np.asarray(data["spectral_shift_ghz"][name], dtype=float)
        count = np.sum(np.isfinite(shifts), axis=0)
        mean = np.divide(np.nansum(shifts, axis=0), count,
                         out=np.full(len(x), np.nan), where=count > 0)
        ax.plot(x, mean)
        active_length_mm = result["active_length_m"] * 1000
        ax.axvline(active_length_mm / 2, color="0.5", linestyle=":", linewidth=1)
        ax.set(xlabel="Centered reference position (mm)",
               ylabel="Mean spectral shift (GHz)", xlim=(-result.get("padding_m", 0) * 1000, active_length_mm + result.get("padding_m", 0) * 1000),
               title=f"{name} | fiber center = {result['center_m']:.6g} m")
        ax.grid(alpha=0.25)
    fig.suptitle(data["test_name"])
    return fig


def center_rois(data, output_path, active_length_m, smoothing_points=SMOOTHING_POINTS,
                *, show=True, padding_m=0.0):
    """Center and save ROI data, retaining padding_m beyond each active endpoint.

    With show=True, create the centered plot without blocking the caller.
    Call plt.show() in the experiment script to keep figures open.
    """
    if isinstance(data, (str, Path)):
        data = json.loads(Path(data).read_text(encoding="utf-8"))
    trimmed, centers = trim_to_active_length(data, active_length_m, smoothing_points, padding_m=padding_m)
    for name, result in centers.items():
        print(f"{name}: center = {result['center_m']:.6g} m, "
              f"bounds = {result['bounds_m']}")
    save_recording(trimmed, output_path, roi_only=False)
    print(f"Saved: {output_path}")
    if show:
        plot_centered_spectra(trimmed, centers)
    return trimmed, centers
