"""Compare linear and finite-slope fits with peak-anchored arc registration."""

import csv
import importlib
import json
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "subroutines"))
from arc_registration import calibrate_registered, fit_registered
from empirical_basis_inversion import load_calibrated_basis, cosine_basis
from plot_format import format_plot
from select_luna_rois import select_luna_rois, load_recording, save_recording, json_ready

center_rois = importlib.import_module("1D_find_center").center_rois
DATA_ROOT = Path("/mnt/lab_storage/Cole/FTSI/Luna_Data/NONLINEARITY_ESTIMATION")
OUTPUT_ROOT = DATA_ROOT / "outputs" / "arc_registered"
INPUT_FILE = DATA_ROOT / "collected data/mode1/2mm/0-65/2MM_BOTTOM_0-65_2026-10-06_22-53-09_ch1_full.tsv"
OUTPUT_DIR = OUTPUT_ROOT / "mode1/2mm/0-65"
ROI_JSON = OUTPUT_DIR / f"{INPUT_FILE.stem}_rois.json"
FIGURE_OUTPUT_DIR = OUTPUT_DIR / "figures"
CALIBRATION_FILES = [OUTPUT_ROOT / "calibration/1mm_bottom_mode1_0-65_linear.npz"]
ACTIVE_LENGTH_MM = 50.0
CALIBRATION_PADDING_MM = 1.0  # Per end, beyond the nominal active region.
ROI_PADDING_MM = 5.0
IMPOSED_AMPLITUDES_MM = np.array([2.0])  # Plot reference only; never used in target fitting.
DISPLACEMENT_DIRECTION = -1
SMOOTHING_POINTS = 5
PASS_COUNT = 1
USE_EXISTING_ROIS = True
SAVE_FIGURES = True
MAX_ITERATIONS = 100
AMPLITUDE_TOLERANCE_MM = 0.0001
ARC_TOLERANCE_MM = 0.001
RELAXATION = 0.5
BATCH_ROI_BOUNDS_M = (1.67705, 1.81225)


def save_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(json_ready(payload), indent=2, allow_nan=False), encoding="utf-8")


def prepare_roi(source, folder):
    path = folder / f"{source.stem}_rois.json"
    if not path.exists():
        relative = source.relative_to(DATA_ROOT / "collected data")
        candidates = [DATA_ROOT / "outputs" / relative.parent / path.name,
                      DATA_ROOT / "outputs" / relative.parts[0] / relative.parts[1] / path.name]
        previous = next((p for p in candidates if p.exists()), None)
        if previous:
            save_recording(json.loads(previous.read_text()), path, roi_only=False)
        else:
            recording = load_recording(source)
            recording["rois"] = [{"pass_id": 1, "bounds_m": BATCH_ROI_BOUNDS_M}]
            save_recording(recording, path)
    return path


def recalibrate(source):
    folder = OUTPUT_ROOT / "calibration"
    roi = prepare_roi(source, folder)
    data, centers = center_rois(roi, folder / f"{source.stem}_centered.json",
                               ACTIVE_LENGTH_MM / 1000, SMOOTHING_POINTS, show=False,
                               padding_m=CALIBRATION_PADDING_MM / 1000)
    path = CALIBRATION_FILES[0]
    # Known 1 mm amplitude determines calibration registration directly.
    calibration = calibrate_registered(data, 1.0, 1, ACTIVE_LENGTH_MM, finite_slope=False)
    calibration["padding_mm"] = CALIBRATION_PADDING_MM
    np.savez_compressed(path, **calibration)
    save_json(path.with_suffix(".json"), dict(source_file=str(source), centers=centers,
              coordinate_convention="Peak-relative material distance mapped to horizontal CAD position",
              calibration=calibration))
    if SAVE_FIGURES:
        fig, ax = plt.subplots(figsize=(10, 5), constrained_layout=True)
        ax.plot(calibration["position_mm"], calibration["mean_shift_ghz"], label="Registered calibration mean")
        ax.plot(calibration["position_mm"], calibration["fitted_shift_ghz"], "--", label="Calibration fit")
        ax.set(xlabel="Horizontal position (mm)", ylabel="Optical shift (GHz)", title=path.stem)
        ax.grid(True)
        ax.legend()
        format_plot(fig)
        fig.savefig(path.with_suffix(".png"), dpi=300)
        plt.close(fig)
    print(f"Saved calibration: {path.name}; gain={calibration['optical_amplitude_ghz']:.6g} GHz/mm")


def plot_results(source, imposed, linear, corrected, folder, *, show):
    modes = linear["mode_numbers"]
    x = np.linspace(0, ACTIVE_LENGTH_MM, 501)
    shape = DISPLACEMENT_DIRECTION * (1 - cosine_basis(x, ACTIVE_LENGTH_MM, modes))
    fig, ax = plt.subplots(figsize=(10, 5), constrained_layout=True)
    for label, amplitudes, style in [("Imposed", imposed, "k--"),
                                     ("Arc-registered linear", linear["amplitudes_mm"], "-"),
                                     ("Arc + finite slope", corrected["amplitudes_mm"], "-")]:
        text = ", ".join(f"A{m}={a:.4g} mm" for m, a in zip(modes, amplitudes))
        ax.plot(x, shape @ amplitudes, style, label=f"{label}: {text}")
    ax.set(xlabel="Horizontal position (mm)", ylabel="Displacement (mm)", title="Time-averaged shape reconstruction")
    ax.grid(True)
    ax.legend()
    format_plot(fig)

    optical, axes = plt.subplots(2, 1, sharex=True, figsize=(10, 8), constrained_layout=True)
    # Each model selects its own material window; show both registered means.
    for label, fit in [("Linear", linear), ("Finite slope", corrected)]:
        position = fit["position_mm"]
        axes[0].plot(position, fit["mean_shift_ghz"], ":", label=f"{label} registered mean")
        axes[0].plot(position, fit["predicted_shift_ghz"], label=f"{label} prediction")
        axes[1].plot(position, fit["residual_ghz"], label=f"{label}: RMS {fit['rms_ghz']:.4g} GHz")
    axes[0].set(ylabel="Optical shift (GHz)", title=source.stem)
    axes[1].set(xlabel="Horizontal position (mm)", ylabel="Measured - predicted (GHz)")
    axes[1].axhline(0, color="0.5")
    for ax in axes:
        ax.grid(True)
        ax.legend()
    format_plot(optical)
    if SAVE_FIGURES:
        folder.mkdir(parents=True, exist_ok=True)
        fig.savefig(folder / f"{source.stem}_shape_comparison.png", dpi=300)
        optical.savefig(folder / f"{source.stem}_optical_fit_residuals.png", dpi=300)
    if show:
        plt.show()
    else:
        plt.close(fig)
        plt.close(optical)


def main(*, show=True):
    results = {}

    def on_saved(roi):
        data, centers = center_rois(roi, OUTPUT_DIR / f"{INPUT_FILE.stem}_rois_centered.json",
                                   ACTIVE_LENGTH_MM / 1000, SMOOTHING_POINTS, show=False,
                                   padding_m=ROI_PADDING_MM / 1000)
        for name, paths, finite in [("linear", CALIBRATION_FILES, False),
                                    ("corrected", CALIBRATION_FILES, True)]:
            calibrations = [load_calibrated_basis(path) for path in paths]
            results[name] = fit_registered(data, calibrations, finite_slope=finite,
                max_iterations=MAX_ITERATIONS, amplitude_tolerance=AMPLITUDE_TOLERANCE_MM,
                arc_tolerance=ARC_TOLERANCE_MM, relaxation=RELAXATION)
            fit = results[name]
            print(f"{name}: A={fit['amplitudes_mm']} mm; arc={fit['arc_length_mm']:.6f} mm; "
                  f"iterations={len(fit['history'])}; converged={fit['converged']}")
        results.update(source_file=str(INPUT_FILE), centers=centers,
                       calibration_files=[str(p) for p in CALIBRATION_FILES],
                       corrected_calibration_files=[str(p) for p in CALIBRATION_FILES],
                       calibration_model="Shared arc-registered linear 1 mm calibration for both fits",
                       imposed_amplitudes_mm=IMPOSED_AMPLITUDES_MM, padding_mm=ROI_PADDING_MM,
                       smoothing_points=SMOOTHING_POINTS,
                       iteration_settings=dict(max_iterations=MAX_ITERATIONS, amplitude_tolerance_mm=AMPLITUDE_TOLERANCE_MM,
                                               arc_tolerance_mm=ARC_TOLERANCE_MM, relaxation=RELAXATION),
                       assumptions="Zero membrane strain; material distance approximates midplane arc length; center fixed at detected peak; far end free, no additional global feed shift")
        shape_x = np.linspace(0, ACTIVE_LENGTH_MM, 501)
        shape_basis = DISPLACEMENT_DIRECTION * (1 - cosine_basis(shape_x, ACTIVE_LENGTH_MM, results["linear"]["mode_numbers"]))
        results["shapes"] = dict(position_mm=shape_x, imposed_mm=shape_basis @ IMPOSED_AMPLITUDES_MM,
                                 linear_mm=shape_basis @ results["linear"]["amplitudes_mm"],
                                 corrected_mm=shape_basis @ results["corrected"]["amplitudes_mm"])
        save_json(OUTPUT_DIR / f"{INPUT_FILE.stem}_fit_results.json", results)
        plot_results(INPUT_FILE, IMPOSED_AMPLITUDES_MM, results["linear"], results["corrected"], FIGURE_OUTPUT_DIR, show=show)

    if USE_EXISTING_ROIS:
        on_saved(ROI_JSON)
    else:
        select_luna_rois(INPUT_FILE, ROI_JSON, PASS_COUNT, on_saved=on_saved)
        plt.show()
    return results


def run_batch():
    global INPUT_FILE, OUTPUT_DIR, ROI_JSON, FIGURE_OUTPUT_DIR, IMPOSED_AMPLITUDES_MM
    sources = sorted(p for p in (DATA_ROOT / "collected data" / "mode1").rglob("*.tsv")
                     if "bottom_0-65_" in p.name.lower() and p.name.lower().endswith("_full.tsv"))
    calibration_source = next(p for p in sources if float(p.name.lower().split("mm")[0]) == 1)
    recalibrate(calibration_source)
    rows = []
    for source in sources:
        INPUT_FILE = source
        OUTPUT_DIR = OUTPUT_ROOT / source.relative_to(DATA_ROOT / "collected data").parent
        ROI_JSON = prepare_roi(source, OUTPUT_DIR)
        FIGURE_OUTPUT_DIR = OUTPUT_DIR / "figures"
        IMPOSED_AMPLITUDES_MM = np.array([float(source.name.lower().split("mm")[0])])
        print(f"\n{source.name}")
        result = main(show=False)
        rows.append(dict(source_file=str(source), imposed_amplitude_mm=IMPOSED_AMPLITUDES_MM[0],
                         linear_amplitude_mm=result["linear"]["amplitudes_mm"][0],
                         corrected_amplitude_mm=result["corrected"]["amplitudes_mm"][0],
                         linear_arc_mm=result["linear"]["arc_length_mm"], corrected_arc_mm=result["corrected"]["arc_length_mm"],
                         linear_converged=result["linear"]["converged"], corrected_converged=result["corrected"]["converged"]))
    with (OUTPUT_ROOT / "summary.csv").open("w", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    return rows


if __name__ == "__main__":
    results = run_batch()
