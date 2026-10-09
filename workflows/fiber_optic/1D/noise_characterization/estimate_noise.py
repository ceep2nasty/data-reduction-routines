"""Estimate sample-to-sample noise for static, fixed-free, "ideal" bending
using imposed cosine deformation shapes"""

import importlib
import numpy as np
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "subroutines"))

from empirical_basis_inversion import (
    load_calibrated_basis,
    fit_amplitudes,
    cosine_basis,
)

import matplotlib.pyplot as plt

from select_luna_rois import select_luna_rois
from plot_format import format_plot

# The existing module name starts with a digit, so use importlib to import it.
center_rois = importlib.import_module("1D_find_center").center_rois


# Overrides for every figure; shared defaults live in subroutines/plot_format.py.
PLOT_FORMAT = {}  # Example: {"legend_loc": "upper right", "legend_size": 14}

# window selection settings
INPUT_FILE = Path("/mnt/lab_storage/Cole/FTSI/Luna_Data/NOISE_CHARACTERIZATION/collected data/1mm/0-65/1MM_BOTTOM_0-65_2026-10-07_01-38-25_ch1_gages.tsv")
OUTPUT_DIR = Path("/mnt/lab_storage/Cole/FTSI/Luna_Data/NOISE_CHARACTERIZATION/outputs/1mm/0-65/bottom")
SAVE_NAME = "1mm_bottom_0-65_rois"
PASS_COUNT = 1
SAVE_PLOTS = False  # True saves the analysis figures as PNGs in OUTPUT_DIR.
METADATA = {"gage_pitch": 0.65}  # mm; test name and sampling rate come from TSV.
ACTIVE_LENGTH_M = 0.050
SMOOTHING_POINTS = 3
USE_EXISTING_ROIS = True  # True skips selection and centers the saved ROIs below.
ROI_JSON = OUTPUT_DIR / f"{SAVE_NAME}.json"

# Displacement comparison: 1 mm cosine amplitude gives 2 mm maximum deflection.
IMPOSED_AMPLITUDE_MM = 1.0
IMPOSED_DIRECTION = -1  # Actual target: -1 downward; +1 upward.
CALIBRATION_DIRECTION = -1  # Positive amplitude in the saved calibration: top +1, bottom -1.

# calibration file settings
basis_cal_path = Path("/mnt/lab_storage/Cole/FTSI/Luna_Data/NOISE_CHARACTERIZATION/optical_basis_cal/1mm/1mm_bottom_mode1_0-65.npz")



def prepare_noise_data(input_file, output_dir, save_name, pass_count,
                       active_length_m, smoothing_points=5, metadata=None,
                       *, existing_roi_json=None):
    """Open selection; Save writes ROI and centered JSONs and shows both plots.

    Closing the selector without saving stops the workflow. Noise statistics
    can be added later using the returned state's centered_data and centers.
    Supply existing_roi_json to skip selection and center saved ROI data.
    Use the uncentered ROI JSON so the full active window is still available.
    """
    output_dir = Path(output_dir)
    state = {}
    initial_figures = set(plt.get_fignums())

    def process_selection(saved):
        trimmed, centers = center_rois(
            saved, output_dir / f"{save_name}_centered.json",
            active_length_m, smoothing_points,
        )
        # Include the saved-ROI preview created by the selector before this callback.
        for number in set(plt.get_fignums()) - initial_figures:
            format_plot(plt.figure(number), **PLOT_FORMAT)
        state.update(centered_data=trimmed, centers=centers)

    if existing_roi_json is not None:
        process_selection(Path(existing_roi_json))
        return state, None

    _, fig = select_luna_rois(
        input_file, output_dir / f"{save_name}.json", pass_count,
        metadata, on_saved=process_selection,
    )
    format_plot(fig, **PLOT_FORMAT)
    return state, fig

def load_noise_data(json_path, pass_name="pass_1"):
    """Load a centered ROI JSON; spectral shift has shape (time, position)."""
    json_path = Path(json_path)
    with json_path.open("r", encoding="utf-8") as file:
        data = json.load(file)
    loaded = {}
    loaded["gage_pitch_mm"] = data["gage_pitch_mm"]
    loaded["test_name"] = data["test_name"]
    loaded["sampling_rate_hz"] = data["sampling_rate_hz"]
    loaded["time_s"] = np.asarray(data["time_s"], dtype=float)
    loaded["position_mm"] = np.asarray(data["position_mm"][pass_name], dtype=float)
    loaded["spectral_shift_ghz"] = np.asarray(data["spectral_shift_ghz"][pass_name], dtype=float)

    expected_shape = (len(loaded["time_s"]), len(loaded["position_mm"]))
    if loaded["spectral_shift_ghz"].shape != expected_shape:
        raise ValueError(f"Expected spectral shift shape {expected_shape}")
    return loaded

def process_noise_raw_spectra(data, *, make_plots=True):
    """Calculate temporal spread at each position and plot the optical profile."""
    shift = np.asarray(data["spectral_shift_ghz"], dtype=float)
    position = np.asarray(data["position_mm"], dtype=float)

    mean_shift = np.nanmean(shift, axis=0)
    std_shift = np.nanstd(shift, axis=0, ddof=1)
    average_std = float(np.nanmean(std_shift))
    # Spread of single readings, not a confidence interval for their mean.
    average_half_width = 1.96 * average_std
    stats = {
        "mean": mean_shift,
        "std": std_shift,
        "var": std_shift ** 2,
        "valid_count": np.sum(np.isfinite(shift), axis=0),
        "noise_95_half_width": 1.96 * std_shift,
        "average_std": average_std,
        "average_noise_95_half_width": average_half_width,
    }

    if not make_plots:
        return stats

    fig, axes = plt.subplots(
        3, 1, sharex=True, figsize=(10, 10), constrained_layout=True
    )

    axes[0].plot(position, mean_shift)
    axes[0].set_ylabel("Mean spectral shift (GHz)")
    axes[0].set_title("Mean spectral shift versus position")
    axes[0].grid(True)

    axes[1].plot(position, std_shift)
    axes[1].set_ylabel("Standard deviation (GHz)")
    axes[1].set_title("Temporal standard deviation versus position")
    axes[1].axhline(
        average_std, color="tab:orange", linestyle="--",
        label=f"Average standard deviation: {average_std:.4g} GHz",
    )
    axes[1].legend()
    axes[1].grid(True)

    if np.isfinite(average_half_width):
        noise_label = (
            "Approx. 95% noise band\n"
            rf"$\pm {average_half_width:.4g}\;\mathrm{{GHz}}$"
        )
    else:
        noise_label = "Noise band unavailable (insufficient valid samples)"

    axes[2].plot(position, mean_shift, label="Mean spectral shift")
    axes[2].fill_between(
        position, mean_shift - average_half_width, mean_shift + average_half_width,
        alpha=0.25, label="Mean +/- 1.96 x average standard deviation",
    )
    axes[2].set_xlabel("Position (mm)")
    axes[2].set_ylabel("Mean spectral shift (GHz)")
    axes[2].set_title("Mean profile with constant 95% noise band")
    axes[2].legend(loc="upper left")
    axes[2].text(
        0.98, 0.97, noise_label, transform=axes[2].transAxes,
        ha="right", va="top", fontsize=11,
        bbox=dict(boxstyle="round,pad=0.4", facecolor="white", edgecolor="0.75", alpha=0.9),
    )
    axes[2].grid(True)

    format_plot(fig, **PLOT_FORMAT)
    stats["figure"] = fig
    return stats

def process_fit_noise(data, optical_basis, *, imposed_amplitude_mm,
                      imposed_direction, calibration_direction,
                      active_length_mm=None, make_plots=True):
    """Fit one cosine amplitude per frame, reconstruct shapes, and measure spread."""
    position_mm = data["position_mm"]
    shift_ghz = data["spectral_shift_ghz"]
    active_length = optical_basis["active_length_mm"]
    if active_length_mm is not None and not np.isclose(active_length, active_length_mm):
        raise ValueError("Calibration and recording active lengths differ")

    # 1. Evaluate the unit displacement cosine at the recorded positions.
    shape_basis = cosine_basis(
        position_mm, active_length, [optical_basis["mode_number"]],
        origin_mm=optical_basis["origin_mm"],
    )
    # 2. Scale it by the saved optical response per mm of displacement.
    basis_ghz_per_mm = shape_basis * (
        optical_basis["optical_amplitude_ghz"] / optical_basis["imposed_amplitude_mm"]
    )
    # 3. Fit the displacement amplitude and optical baseline for each frame.
    fit = fit_amplitudes(basis_ghz_per_mm, shift_ghz, allow_offset=True)
    amplitudes_mm = fit["amplitudes_mm"]
    # 4. Set zero at the active-window endpoints and choose deflection direction.
    displacement_basis = calibration_direction * (1.0 - shape_basis)
    shape_mm = amplitudes_mm @ displacement_basis.T
    imposed_shape_mm = imposed_direction * imposed_amplitude_mm * (1.0 - shape_basis[:, 0])
    # 5. Measure temporal variability down each position column.
    mean_shape_mm = np.nanmean(shape_mm, axis=0)
    shape_std_mm = np.nanstd(shape_mm, axis=0, ddof=1)
    amplitude_std_mm = np.nanstd(amplitudes_mm, axis=0, ddof=1)
    noise_half_width_mm = 1.96 * shape_std_mm

    stats = {
        "fit": fit,
        "mean_amplitude_mm": float(np.nanmean(amplitudes_mm[:, 0])),
        "amplitude_std_mm": amplitude_std_mm,
        "shape_mm": shape_mm,
        "imposed_shape_mm": imposed_shape_mm,
        "shape_std_mm": shape_std_mm,
        "mean_shape_mm": mean_shape_mm,
        "shape_noise_95_half_width_mm": noise_half_width_mm,
    }
    if not make_plots:
        return stats

    fig, ax = plt.subplots(figsize=(10, 5), constrained_layout=True)
    mean_amplitude_mm = stats["mean_amplitude_mm"]
    ax.plot(position_mm, mean_shape_mm,
            label=f"Mean reconstructed shape (fitted amplitude {mean_amplitude_mm:.4g} mm)")
    ax.plot(position_mm, imposed_shape_mm, "--", color="black",
            label=f"Imposed shape (cosine amplitude {imposed_amplitude_mm:g} mm)")
    ax.fill_between(
        position_mm, mean_shape_mm - noise_half_width_mm,
        mean_shape_mm + noise_half_width_mm, alpha=0.25,
        label="Approx. 95% noise spread (1.96 x temporal std)",
    )
    ax.set_xlabel("Position (mm)")
    ax.set_ylabel("Reconstructed displacement (mm)")
    ax.set_title("Reconstructed shape with temporal noise spread")
    ax.text(
        0.98, 0.97,
        "Amplitude noise spread\n" + rf"$\pm {1.96 * amplitude_std_mm[0]:.4g}\;\mathrm{{mm}}$",
        transform=ax.transAxes, ha="right", va="top",
        bbox=dict(boxstyle="round,pad=0.4", facecolor="white", edgecolor="0.75", alpha=0.9),
    )
    ax.legend(loc="lower left")
    ax.grid(True)
    format_plot(fig, **PLOT_FORMAT)
    stats["figure"] = fig
    return stats


def analyze_recording(centered_json, calibration_path, *, imposed_amplitude_mm,
                      imposed_direction, calibration_direction, pass_name="pass_1",
                      active_length_mm=None, make_plots=True, output_dir=None,
                      save_name=None, show=False):
    """Analyze one recording without selecting or recentering its ROI.

    Directions are +1 upward or -1 downward. Calibration direction describes
    the saved calibration; imposed direction describes this recording.
    Amplitude is the cosine coefficient (half the maximum deflection).
    Pass output_dir to save PNGs. show=False closes this call's figures after
    saving, so batches do not accumulate windows. make_plots=False only computes
    statistics. Returned data, raw_stats, and reconstruction arrays can be reused.
    """
    if imposed_direction not in (-1, 1) or calibration_direction not in (-1, 1):
        raise ValueError("Directions must be +1 or -1")
    if not make_plots and output_dir is not None:
        raise ValueError("Saving plots requires make_plots=True")
    data = load_noise_data(centered_json, pass_name)
    calibration = load_calibrated_basis(calibration_path)
    raw_stats = process_noise_raw_spectra(data, make_plots=make_plots)
    reconstruction = process_fit_noise(
        data, calibration, imposed_amplitude_mm=imposed_amplitude_mm,
        imposed_direction=imposed_direction, calibration_direction=calibration_direction,
        active_length_mm=active_length_mm, make_plots=make_plots,
    )
    figures = {
        "raw_spectra_noise": raw_stats.pop("figure", None),
        "reconstructed_shape_noise": reconstruction.pop("figure", None),
    }
    if output_dir is not None:
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)
        name = save_name or Path(centered_json).stem
        for suffix, figure in figures.items():
            figure.savefig(output_dir / f"{name}_{suffix}.png", dpi=300)
    print(f"{data['test_name']} ({pass_name}): "
          f"mean amplitude = {reconstruction['mean_amplitude_mm']:.6g} mm, "
          f"amplitude std = {reconstruction['amplitude_std_mm'][0]:.6g} mm")
    if show:
        plt.show()
    else:
        for figure in figures.values():
            if figure is not None:
                plt.close(figure)
    return {"data": data, "raw_stats": raw_stats, **reconstruction}


def main():
    state, _ = prepare_noise_data(
        INPUT_FILE, OUTPUT_DIR, SAVE_NAME, PASS_COUNT,
        ACTIVE_LENGTH_M, SMOOTHING_POINTS, METADATA,
        existing_roi_json=ROI_JSON if USE_EXISTING_ROIS else None,
    )
    if not USE_EXISTING_ROIS:
        plt.show()  # Interactive selection must finish before analysis.
        if not state:
            return state
    state.update(analyze_recording(
        OUTPUT_DIR / f"{SAVE_NAME}_centered.json", basis_cal_path,
        imposed_amplitude_mm=IMPOSED_AMPLITUDE_MM,
        imposed_direction=IMPOSED_DIRECTION,
        calibration_direction=CALIBRATION_DIRECTION,
        active_length_mm=ACTIVE_LENGTH_M * 1000,
        output_dir=OUTPUT_DIR if SAVE_PLOTS else None,
        save_name=SAVE_NAME, show=True,
    ))
    return state

if __name__ == "__main__":
    results = main()
