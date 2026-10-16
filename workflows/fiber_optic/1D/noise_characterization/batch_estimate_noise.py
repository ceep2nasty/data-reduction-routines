"""Calibrate full Luna cases and estimate noise using each case's own basis.

Run this script for all amplitude folders. process_batch() also accepts an
explicit list such as CASES for later analysis of already-centered recordings.
"""

import csv
import json
import re

import matplotlib.pyplot as plt
import numpy as np
from pathlib import Path

from estimate_noise import analyze_recording, load_noise_data, center_rois
from select_luna_rois import load_recording, save_recording, json_ready
from plot_format import format_plot
from empirical_basis_inversion import calibrate_basis, save_calibrated_basis, load_calibrated_basis


DATA_ROOT = Path("/mnt/lab_storage/Cole/FTSI/Luna_Data/NOISE_CHARACTERIZATION")
OUTPUT_DIR = DATA_ROOT / "outputs"
ACTIVE_LENGTH_MM = 50.0
SMOOTHING_POINTS = 3
# Broad physical fiber windows from the existing top/bottom selections (meters).
# Center detection refines the active window separately for every recording.
ROI_BOUNDS_M = {"top": (1.692, 1.804), "bottom": (1.695, 1.791)}
CALIBRATION_PATH = DATA_ROOT / "optical_basis_cal" / "1mm" / "1mm_top_mode1_0-65.npz"
CALIBRATION_DIRECTION = 1  # +1 for this top calibration; -1 for a bottom calibration.
SAVE_PLOTS = True

# Add one entry per amplitude/recording. These must be CENTERED ROI JSONs.
# Each case may also override calibration_path, calibration_direction, or pass_name.
CASES = [
    {
        "name": "1mm_bottom_0-65",
        "centered_json": DATA_ROOT / "outputs" / "1mm" / "0-65" / "bottom" / "1mm_bottom_0-65_rois_centered.json",
        "imposed_amplitude_mm": 1.0,  # Cosine coefficient; peak deflection is 2x this.
        "imposed_direction": -1,
    },
    # Copy the entry above for your next amplitude and change its name, path,
    # imposed_amplitude_mm, and imposed_direction to match that recording.
]


def process_batch(cases, calibration_path, *, calibration_direction,
                  output_dir, save_plots=True):
    """Analyze cases, save optional PNGs and summary.csv, and return summary rows.

    Uses existing registration and tared data. Full per-frame results are not
    retained across recordings; call analyze_recording directly to inspect them.
    CSV optical std is the average of per-position temporal standard deviations.
    Noise bands are +/- 1.96 times std, exported as positive half-widths;
    they describe single-sample spread, not confidence intervals for the mean.
    Missing/invalid input stops the batch with its exception.
    """
    names = [case["name"] for case in cases]
    if len(names) != len(set(names)):
        raise ValueError("Each batch case needs a unique name")
    output_dir = Path(output_dir)
    rows = []
    for case in cases:
        case_output = Path(case.get("output_dir", output_dir))
        selected_calibration = case.get("calibration_path", calibration_path)
        selected_direction = case.get("calibration_direction", calibration_direction)
        result = analyze_recording(
            case["centered_json"], selected_calibration,
            imposed_amplitude_mm=case["imposed_amplitude_mm"],
            imposed_direction=case["imposed_direction"],
            calibration_direction=selected_direction,
            pass_name=case.get("pass_name", "pass_1"),
            output_dir=case_output if save_plots else None,
            make_plots=save_plots, save_name=case["name"], show=False,
        )
        rows.append({
            "name": case["name"],
            "centered_json": str(case["centered_json"]),
            "calibration_path": str(selected_calibration),
            "pass_name": case.get("pass_name", "pass_1"),
            "imposed_amplitude_mm": case["imposed_amplitude_mm"],
            "imposed_direction": case["imposed_direction"],
            "calibration_direction": selected_direction,
            "mean_amplitude_mm": result["mean_amplitude_mm"],
            "amplitude_std_mm": float(result["amplitude_std_mm"][0]),
            "amplitude_noise_95_half_width_mm": 1.96 * float(result["amplitude_std_mm"][0]),
            "average_shift_std_ghz": result["raw_stats"]["average_std"],
            "average_shift_noise_95_half_width_ghz": result["raw_stats"]["average_noise_95_half_width"],
            "sample_count": len(result["data"]["time_s"]),
        })
    if rows:
        output_dir.mkdir(parents=True, exist_ok=True)
        with (output_dir / "summary.csv").open("w", newline="", encoding="utf-8") as file:
            writer = csv.DictWriter(file, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
    return rows


def discover_full_cases(data_root):
    """Find only raw *_full.tsv files in amplitude folders, including FLAT."""
    cases = []
    folders = sorted(path for path in Path(data_root).iterdir()
                     if path.is_dir() and (re.fullmatch(r"\d+mm", path.name, re.I)
                                           or path.name.upper() == "FLAT"))
    for folder in folders:
        for source in sorted(folder.rglob("*_full.tsv")):
            match = re.match(r"(\d+mm|flat)_(top|bottom)(?:_(\d+-\d+))?", source.name, re.I)
            if match is None:
                raise ValueError(f"Cannot identify case: {source}")
            amplitude, side, pitch = match.groups()
            cases.append({
                "input_file": source,
                "amplitude_folder": amplitude.lower(),
                "imposed_amplitude_mm": 0.0 if amplitude.lower() == "flat" else float(amplitude[:-2]),
                "side": side.lower(),
                "pitch_name": pitch,  # Actual pitch is checked from the recorded positions.
                "imposed_direction": 1 if side.lower() == "top" else -1,
            })
    return cases


def calibrate_full_case(case, data_root, *, save_plots=True):
    """Crop/register a full recording, retain its tare, and save its own basis.

    No tare restoration or signal smoothing is applied. smoothing_points only
    affects center detection. Existing identical bases are reused; differing
    bases are protected from overwrite.
    """
    amplitude = case["imposed_amplitude_mm"]
    if amplitude == 0:
        # The current normalization divides by imposed amplitude, so FLAT
        # cannot define a response per mm. Leave it untouched for later work.
        raise ValueError("Zero-amplitude calibration is undefined (GHz/mm divides by zero)")
    recording = load_recording(case["input_file"])
    pitch_mm = float(np.median(np.diff(recording["recording"]["position_m"])) * 1000)
    pitch_name = f"{pitch_mm:.4g}".replace(".", "-")
    side = case["side"]
    name = f"{case['amplitude_folder']}_{side}_{pitch_name}_full"
    output_dir = Path(data_root) / "outputs" / case["amplitude_folder"] / pitch_name / side
    calibration_dir = Path(data_root) / "optical_basis_cal" / case["amplitude_folder"]
    recording["metadata"]["gage_pitch_mm"] = pitch_mm
    recording["rois"] = [{"pass_id": 1, "bounds_m": ROI_BOUNDS_M[side]}]
    roi = save_recording(recording, output_dir / f"{name}_rois.json")
    centered_path = output_dir / f"{name}_rois_centered.json"
    _, centers = center_rois(roi, centered_path, ACTIVE_LENGTH_MM / 1000,
                             SMOOTHING_POINTS, show=False)
    data = load_noise_data(centered_path)
    calibration = calibrate_basis(
        data["position_mm"], data["spectral_shift_ghz"], amplitude,
        ACTIVE_LENGTH_MM, mode_number=1, origin_mm=0, allow_offset=True,
    )
    calibration["tare_added_back"] = False
    calibration["calibration_direction"] = case["imposed_direction"]
    basis_name = f"{case['amplitude_folder']}_{side}_mode1_{pitch_name}_full"
    calibration_path = calibration_dir / f"{basis_name}.npz"
    if calibration_path.exists():
        saved = load_calibrated_basis(calibration_path)
        if saved.keys() != calibration.keys() or any(
            not np.array_equal(saved[key], value, equal_nan=True)
            for key, value in calibration.items()
        ):
            raise FileExistsError(f"Different calibration already exists: {calibration_path}")
    else:
        save_calibrated_basis(calibration, calibration_dir, basis_name)
    # Record source and registration alongside the numerical calibration.
    manifest = dict(source_file=str(case["input_file"]), centered_json=str(centered_path),
                    calibration_path=str(calibration_path), tare_added_back=False,
                    imposed_amplitude_mm=amplitude, centers=centers)
    (calibration_dir / f"{basis_name}.json").write_text(
        json.dumps(json_ready(manifest), indent=2, allow_nan=False), encoding="utf-8")
    if save_plots:
        fig, axes = plt.subplots(2, 1, sharex=True, figsize=(10, 7), constrained_layout=True)
        fig.suptitle(name)
        axes[0].plot(data["position_mm"], calibration["mean_shift_ghz"], label="Measured temporal mean")
        axes[0].plot(data["position_mm"], calibration["fitted_shift_ghz"], "--", label="Cosine fit + baseline")
        axes[0].set_ylabel("Spectral shift (GHz)")
        axes[0].legend()
        axes[1].plot(data["position_mm"], calibration["residual_ghz"])
        axes[1].set(xlabel="Position (mm)", ylabel="Fit residual (GHz)")
        for ax in axes:
            ax.grid(True)
        format_plot(fig)
        fig.savefig(calibration_dir / f"{basis_name}.png", dpi=300)
        plt.close(fig)
    return dict(name=name, centered_json=centered_path, calibration_path=calibration_path,
                imposed_amplitude_mm=amplitude, imposed_direction=case["imposed_direction"],
                calibration_direction=case["imposed_direction"], output_dir=output_dir), calibration



def plot_noise_vs_amplitude(rows, output_dir, *, show=False):
    """Save top/bottom figures comparing temporal std across imposed amplitudes.

    Optical std is averaged over recorded positions. Deformation std is the
    fitted cosine-amplitude std, not displacement std at an individual position.
    Each curve represents one gage pitch; both figures use matching axis limits.
    Accepts result dictionaries or rows loaded from the summary CSV.
    """
    groups = {"top": {}, "bottom": {}}
    for row in rows:
        match = re.search(r"_(top|bottom)_([0-9]+-[0-9]+)(?:_|$)", row["name"])
        if match is None:
            raise ValueError(f"Cannot identify side and pitch: {row['name']}")
        side, pitch = match.groups()
        groups[side].setdefault(float(pitch.replace("-", ".")), []).append(row)
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    paths, figures = [], []
    metrics = [("average_shift_std_ghz", "Average optical shift std (GHz)"),
               ("amplitude_std_mm", "Fitted deformation amplitude std (mm)")]
    for side, pitches in groups.items():
        fig, axes = plt.subplots(2, 1, sharex=True, figsize=(9, 8), constrained_layout=True)
        fig.suptitle(f"{side.capitalize()} pass: temporal noise versus imposed amplitude")
        for pitch, cases in sorted(pitches.items()):
            cases = sorted(cases, key=lambda row: float(row["imposed_amplitude_mm"]))
            amplitude = [float(row["imposed_amplitude_mm"]) for row in cases]
            for ax, (key, _) in zip(axes, metrics):
                ax.plot(amplitude, [float(row[key]) for row in cases], "o-",
                        label=f"{pitch:g} mm gage pitch")
        for ax, (key, label) in zip(axes, metrics):
            ax.set_ylabel(label)
            ax.set_ylim(0, 1.1 * max(float(row[key]) for row in rows))
            ax.grid(alpha=0.3)
            ax.legend()
        axes[-1].set_xlabel("Imposed cosine amplitude (mm)")
        axes[-1].set_xticks(sorted({float(row["imposed_amplitude_mm"]) for row in rows}))
        path = output_dir / f"{side}_noise_std_vs_amplitude.png"
        format_plot(fig)
        fig.savefig(path, dpi=300)
        paths.append(path)
        figures.append(fig)
    if show:
        plt.show()
    else:
        for fig in figures:
            plt.close(fig)
    return paths


def calibrate_and_process_batch(data_root=DATA_ROOT, *, save_plots=True):
    """Calibrate nonzero full cases and analyze each with its own tared basis.

    FLAT cases are logged separately and left untouched because the current
    calibration cannot normalize a zero imposed amplitude.
    """
    data_root = Path(data_root)
    rows, skipped = [], []
    for case in discover_full_cases(data_root / "collected data"):
        if case["imposed_amplitude_mm"] == 0:
            skipped.append({"input_file": str(case["input_file"]),
                            "reason": "Zero-amplitude calibration is undefined; left untouched"})
            print(f"Skipped FLAT: {case['input_file'].name}")
            continue
        prepared, calibration = calibrate_full_case(case, data_root, save_plots=save_plots)
        result_rows = process_batch(
            [prepared], prepared["calibration_path"],
            calibration_direction=prepared["calibration_direction"],
            output_dir=prepared["output_dir"], save_plots=save_plots,
        )
        row = result_rows[0]
        row.update(input_file=str(case["input_file"]),
                   gain_ghz_per_mm=calibration["optical_amplitude_ghz"] / case["imposed_amplitude_mm"],
                   calibration_rms_ghz=calibration["rms_ghz"], tare_added_back=False)
        rows.append(row)
    for filename, entries in [("full_batch_summary.csv", rows), ("full_batch_skipped.csv", skipped)]:
        if entries:
            directory = data_root / "outputs"
            directory.mkdir(parents=True, exist_ok=True)
            with (directory / filename).open("w", newline="", encoding="utf-8") as file:
                writer = csv.DictWriter(file, fieldnames=list(entries[0]))
                writer.writeheader()
                writer.writerows(entries)
    if save_plots and rows:
        plot_noise_vs_amplitude(rows, data_root / "outputs")
    return rows


if __name__ == "__main__":
    summary = calibrate_and_process_batch(save_plots=SAVE_PLOTS)
