"""Inspect a cosine optical calibration from a centered ROI recording."""

import importlib
import json
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "subroutines"))
from empirical_basis_inversion import (
    calibrate_basis, fit_amplitudes, load_calibrated_basis,
    save_calibrated_basis, stack_calibrated_basis,
)

from select_luna_rois import select_luna_rois
center_rois = importlib.import_module("1D_find_center").center_rois

# ROI selection and centering settings.
INPUT_FILE = Path(r"Z:\Cole\FTSI\Luna_Data\NOISE_CHARACTERIZATION\1mm\0-65\1MM_BOTTOM_0-65_2026-10-07_01-38-25_ch1_gages.tsv")
ROI_OUTPUT_DIR = Path(r"Z:\Cole\FTSI\Luna_Data\NOISE_CHARACTERIZATION\outputs\1mm\bottom")
SAVE_NAME = "1mm_bottom_0-65_rois"
PASS_COUNT = 1
SMOOTHING_POINTS = 3
USE_EXISTING_ROIS = False  # False opens the interactive selector; Save continues calibration.
ROI_JSON = ROI_OUTPUT_DIR / f"{SAVE_NAME}.json"

# Edit these settings for each pure-mode calibration case.
JSON_PATH = ROI_OUTPUT_DIR / f"{SAVE_NAME}_centered.json"
PASS_NAME = "pass_1"
IMPOSED_AMPLITUDE_MM = 1.0
ACTIVE_LENGTH_MM = 50.0
MODE_NUMBER = 1
ORIGIN_MM = 0.0  # Centered JSON positions start at the active window's left boundary.
ALLOW_OFFSET = True
WINDOW_START_MM = 0.0
TIME_START_S = None  # None uses the whole recording; choose a steady interval if needed.
TIME_END_S = None
SAVE_BASIS = True  # Enable after inspecting the fit; existing files are protected.
OUTPUT_DIR = Path(r"Z:\Cole\FTSI\Luna_Data\NOISE_CHARACTERIZATION\optical_basis_cal")
BASIS_NAME = "1mm_bottom_mode1_0-65"
# Empty: inspect the calibration recording itself (consistency check).
# Set paths to saved mode bases to fit an independent target, stacked in list order.
FIT_BASIS_PATHS = []
FIT_JSON_PATH = JSON_PATH
FIT_PASS_NAME = PASS_NAME
FIT_ALLOW_OFFSET = True
INSPECT_SAMPLE_INDEX = 0  # Index within the selected target time samples.


def prepare_calibration_data():
    """Save/center selected ROIs; stop if the selector closes without saving."""
    saved = False

    def center_selection(path):
        nonlocal saved
        center_rois(path, JSON_PATH, ACTIVE_LENGTH_MM / 1000, SMOOTHING_POINTS)
        saved = True

    if USE_EXISTING_ROIS:
        center_selection(ROI_JSON)
    else:
        select_luna_rois(
            INPUT_FILE, ROI_JSON, PASS_COUNT, on_saved=center_selection,
        )
    plt.show()
    return saved


def main():
    if not prepare_calibration_data():
        print("ROI selection closed without saving; calibration stopped.")
        return None
    data, position, shift, time = load_recording(JSON_PATH, PASS_NAME)
    calibration = calibrate_basis(
        position, shift, IMPOSED_AMPLITUDE_MM, ACTIVE_LENGTH_MM,
        mode_number=MODE_NUMBER, origin_mm=ORIGIN_MM, allow_offset=ALLOW_OFFSET,
    )
    print(f"Source: {JSON_PATH}")
    print(f"Case: {data.get('test_name', JSON_PATH.stem)}; pass: {PASS_NAME}")
    print(f"Selected samples: {len(time)} ({time.min():.4g} to {time.max():.4g} s)")
    print(f"Mode: {MODE_NUMBER}; imposed amplitude: {IMPOSED_AMPLITUDE_MM:g} mm")
    print(f"Optical amplitude: {calibration['optical_amplitude_ghz']:.6g} GHz")
    print(f"Gain: {calibration['optical_amplitude_ghz'] / IMPOSED_AMPLITUDE_MM:.6g} GHz/mm")
    print(f"Baseline: {calibration['offset_ghz']:.6g} GHz")
    print(f"Residual RMS: {calibration['rms_ghz']:.6g} GHz")
    if SAVE_BASIS:
        saved = save_calibrated_basis(calibration, OUTPUT_DIR, BASIS_NAME)
        print(f"Saved basis: {saved}")

    fig, axes = plt.subplots(3, 1, sharex=True, figsize=(10, 9), constrained_layout=True)
    fig.suptitle(f"Optical calibration: {data.get('test_name', JSON_PATH.stem)}, {PASS_NAME}")
    axes[0].plot(position, calibration["mean_shift_ghz"], color="0.5", label="Measured temporal mean")
    axes[0].plot(position, calibration["fitted_shift_ghz"], "--", label="Cosine fit + baseline")
    axes[0].set_ylabel("Optical shift (GHz)")
    axes[0].legend()
    axes[1].plot(position, calibration["residual_ghz"])
    axes[1].axhline(0, color="0.5", linewidth=0.8)
    axes[1].set_ylabel("Measured - fitted (GHz)")
    axes[2].plot(position, calibration["optical_basis_ghz_per_mm"])
    axes[2].set_ylabel("Optical basis (GHz/mm)")
    axes[2].set_title("Normalized cosine response (baseline excluded)")
    axes[2].set_xlabel("Position from active window start (mm)")
    for ax in axes:
        ax.grid(alpha=0.3)
    fits = inspect_amplitude_fits(calibration)
    plt.show()
    return {"calibration": calibration, "fit": fits}


def load_recording(path, pass_name):
    """Load centered JSON arrays and select the configured steady time interval."""
    with Path(path).open(encoding="utf-8") as file:
        data = json.load(file)
    position = np.asarray(data["position_mm"][pass_name], dtype=float)
    shift = np.asarray(data["spectral_shift_ghz"][pass_name], dtype=float)
    time = np.asarray(data["time_s"], dtype=float)
    if position.ndim != 1 or time.ndim != 1 or shift.shape != (time.size, position.size):
        raise ValueError("Expected time-by-position data matching coordinates")
    selected = np.isfinite(time)
    if TIME_START_S is not None:
        selected &= time >= TIME_START_S
    if TIME_END_S is not None:
        selected &= time <= TIME_END_S
    if not selected.any():
        raise ValueError("No samples in the selected interval")
    return data, position, shift[selected], time[selected]


def inspect_amplitude_fits(calibration):
    """Fit one set of calibrated modes and inspect a sample and its time history."""
    _, position, shift, time = load_recording(FIT_JSON_PATH, FIT_PASS_NAME)
    if not 0 <= INSPECT_SAMPLE_INDEX < len(time):
        raise ValueError("Inspection sample index is outside selected samples")
    bases = [load_calibrated_basis(path) for path in FIT_BASIS_PATHS] if FIT_BASIS_PATHS else [calibration]
    stacked = stack_calibrated_basis(bases, position, window_start_mm=WINDOW_START_MM)
    fit = fit_amplitudes(stacked["optical_basis"], shift, allow_offset=FIT_ALLOW_OFFSET)
    fit["mode_numbers"] = stacked["mode_numbers"]
    print(f"\nAmplitude fitting target: {FIT_JSON_PATH}, {FIT_PASS_NAME}")
    if not FIT_BASIS_PATHS and FIT_JSON_PATH == JSON_PATH:
        print("Same-recording consistency check; this is not independent validation.")
    fig, axes = plt.subplots(3, 1, figsize=(10, 9), constrained_layout=True)
    axes[0].plot(position, shift[INSPECT_SAMPLE_INDEX], color="0.6", label="Measured sample")
    print(f"Mean RMS: {fit['rms_ghz'].mean():.6g} GHz; max condition: {fit['condition_number'].max():.6g}")
    for column, mode in enumerate(stacked["mode_numbers"]):
        amplitudes = fit["amplitudes_mm"][:, column]
        print(f"Mode {mode}: mean amplitude={amplitudes.mean():.6g} mm; std={np.std(amplitudes):.6g} mm")
        axes[2].plot(time, amplitudes, label=f"Mode {mode}")
    print(f"Sample {INSPECT_SAMPLE_INDEX}: amplitudes={fit['amplitudes_mm'][INSPECT_SAMPLE_INDEX]} mm; offset={fit['offset_ghz'][INSPECT_SAMPLE_INDEX]:.6g} GHz")
    axes[0].plot(position, fit["predicted_shift_ghz"][INSPECT_SAMPLE_INDEX], "--", label="Fit")
    axes[1].plot(position, fit["residual_ghz"][INSPECT_SAMPLE_INDEX], label="Measured - fitted")
    axes[0].set_title(f"Target sample {INSPECT_SAMPLE_INDEX}, t={time[INSPECT_SAMPLE_INDEX]:.4g} s")
    axes[0].set_ylabel("Optical shift (GHz)")
    axes[0].set_xlabel("Registered position (mm)")
    axes[1].axhline(0, color="0.5", linewidth=0.8)
    axes[1].set_ylabel("Residual (GHz)")
    axes[1].set_xlabel("Registered position (mm)")
    axes[2].set_ylabel("Fitted amplitude (mm)")
    axes[2].set_xlabel("Time (s)")
    for ax in axes:
        ax.legend()
        ax.grid(alpha=0.3)
    return fit


if __name__ == "__main__":
    calibrations = main()
