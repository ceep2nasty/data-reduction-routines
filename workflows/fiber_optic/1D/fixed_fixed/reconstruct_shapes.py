"""Load a calibration and test case; leave reconstruction to the user."""

import json
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


OUTPUT_ROOT = Path(r"C:\Users\coled_agkeohi\Notre Dame\FTSI F26\fixed-fixed\outputs")
BASIS_PATH = OUTPUT_ROOT / "basis_cal/k1_k2/shift_basis.npz"
TEST_CASES = {
    "k1a2_k2a1_spec2": {1: 2.0, 2: 1.0},
    "k1a1_k2a0-5_spec2": {1: 1.0, 2: 0.5},
}
RUN_RECONSTRUCTION = True
SAVE_FIGURES = True
SAVE_RESULTS = True
TEST_NOMINAL_OFFSET_MM = None  # None references displacement to zero at +/-25 mm.
PLOT_DIR = OUTPUT_ROOT / "reconstruction_k1_k2"

plt.rcParams.update({'font.size': 20,
                     'font.family': 'serif',
                     'font.serif': ['Times New Roman'],
                     }) # Sets global font size

def load_archive(path):
    with np.load(path, allow_pickle=False) as archive:
        data = {name: archive[name] for name in archive.files}
    data["metadata"] = json.loads(data.pop("metadata_json").item())
    return data


def align_inputs(calibration, test):
    """Align unfiltered test shifts to the calibration grid, without extrapolation.

    Preserve NaNs during interpolation so missing-data gaps are excluded,
    rather than bridged. Apply the same row mask to positions and basis.
    """
    x = test["fit50_position_m"] - float(test["center_m"])
    y = test["fit50_measured_shift_ghz"]
    position = calibration["position_m"]
    measured = np.interp(position, x, y, left=np.nan, right=np.nan)
    basis = calibration["basis_ghz_per_mm"]
    valid = np.isfinite(measured) & np.all(np.isfinite(basis), axis=1)
    position, basis, measured = position[valid], basis[valid], measured[valid]
    if calibration["metadata"].get("linear_detrend", False):
        # Apply the same trend removal over the actual shared valid coordinates.
        trend = np.column_stack((np.ones(len(position)), position))
        basis = basis - trend @ np.linalg.lstsq(trend, basis, rcond=None)[0]
        measured = measured - trend @ np.linalg.lstsq(trend, measured, rcond=None)[0]
    return position, basis, measured


def reconstruct_shape(position_m, basis_ghz_per_mm, measured_shift_ghz,
                      *, modes, span_m, nominal_offset_mm=None):
    """Scientific work: implement the reconstruction here.

    position_m: (N,) center-relative coordinates in meters.
    basis_ghz_per_mm: (N, K), columns ordered by modes.
    measured_shift_ghz: (N,) aligned, finite, unfiltered measurements.
    modes: (K,) integer wavenumbers; span_m: physical imposed span.

    Choose amplitude estimation, offsets, displacement-mode definitions,
    and boundary/reference conditions here. Return your desired results.
    """

    L = span_m
    amplitudes_mm, _, rank, singular_values = np.linalg.lstsq(
        basis_ghz_per_mm,
        measured_shift_ghz,
        rcond=None,
    )
    predicted_shift_ghz = basis_ghz_per_mm @ amplitudes_mm
    residual_shift_ghz = measured_shift_ghz - predicted_shift_ghz
    rmse_ghz = np.sqrt(np.mean(residual_shift_ghz**2))

    # Imposed cosines use x=0 at the LEFT end; input positions are center-relative.
    phase = 2 * np.pi * (position_m[:, None] + span_m/2) * modes / span_m
    shape_modes = np.cos(phase)
    if nominal_offset_mm is None:
        nominal_offset_mm = np.sum(amplitudes_mm)
    displacement_mm = shape_modes @ amplitudes_mm - nominal_offset_mm

    return {
        "amplitudes_mm": amplitudes_mm,
        "predicted_shift_ghz": predicted_shift_ghz,
        "residual_shift_ghz": residual_shift_ghz,
        "rmse_ghz": rmse_ghz,
        "displacement_mm": displacement_mm,
    }


def plot_reconstruction(position, measured, result, *, title, modes,
                        span_m, nominal_offset_mm, expected_amplitudes_mm=None):
    fig, ax = plt.subplots(figsize=(10, 5), constrained_layout=True)
    x = position*1000
    ax.plot(x, result["displacement_mm"], label="Reconstructed displacement")
    if expected_amplitudes_mm is not None:
        expected_offset = (np.sum(expected_amplitudes_mm)
                           if nominal_offset_mm is None else nominal_offset_mm)
        expected = np.cos(2*np.pi*(position[:, None]+span_m/2)*modes/span_m) @ expected_amplitudes_mm - expected_offset
        ax.plot(x, expected, "--", label="Imposed displacement")
    ax.set(xlabel="Position relative to center (mm)", ylabel="Displacement (mm)", title=title)
    ax.grid(alpha=0.25)
    ax.legend()
    print(f"{title}: amplitudes {dict(zip(modes.tolist(), result['amplitudes_mm'].tolist()))} mm")
    return fig


def save_figure(fig, filename):
    if SAVE_FIGURES:
        path = PLOT_DIR / filename
        path.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(path, dpi=200, bbox_inches="tight")
        print(f"Saved figure: {path}")


def plot_calibration_cases(calibration):
    modes = calibration["modes"]
    span_m = calibration["metadata"]["span_m"]
    amplitude = calibration["metadata"]["reference_amplitude_mm"]
    sources = calibration["metadata"]["source_profiles"]
    fig, axes = plt.subplots(len(sources), 1, figsize=(10, 9),
                             sharex=True, sharey=True, constrained_layout=True)
    for ax, source in zip(np.atleast_1d(axes), sources):
        path = Path(source)
        test = load_archive(path)
        position, basis, measured = align_inputs(calibration, test)
        mode = int(path.stem.split("a", 1)[0][1:])
        expected = np.where(modes == mode, amplitude, 0.0)
        result = reconstruct_shape(position, basis, measured, modes=modes,
                                   span_m=span_m)
        imposed = (np.cos(2*np.pi*(position[:, None]+span_m/2)*modes/span_m)
                   @ expected - np.sum(expected))
        ax.plot(position*1000, result["displacement_mm"], label="Reconstructed displacement")
        ax.plot(position*1000, imposed, "--", label="Imposed displacement")
        ax.set_title(rf"$A_{mode} = {amplitude:g}\,\mathrm{{mm}}$")
        ax.grid(alpha=0.25)
    np.atleast_1d(axes)[0].legend()
    fig.suptitle("Calibration Reconstruction Check")
    fig.supxlabel("Position relative to center (mm)")
    fig.supylabel("Displacement (mm)")
    save_figure(fig, "calibration_reconstruction_check.png")
    return fig


def main():
    calibration = load_archive(BASIS_PATH)
    modes = calibration["modes"]
    span_m = calibration["metadata"]["span_m"]
    print(f"Calibration: {BASIS_PATH.name}; modes {modes.tolist()}")

    if RUN_RECONSTRUCTION:
        for case, amplitudes in TEST_CASES.items():
            test_path = OUTPUT_ROOT / "roi_zoomed/k1" / f"{case}.npz"
            test = load_archive(test_path)
            position, basis, measured = align_inputs(calibration, test)
            expected_amplitudes = np.array([amplitudes.get(int(mode), 0.0) for mode in modes])
            result = reconstruct_shape(position, basis, measured, modes=modes, span_m=span_m,
                                       nominal_offset_mm=TEST_NOMINAL_OFFSET_MM)
            title = ", ".join(rf"$A_{mode} = {amplitudes[int(mode)]:g}\,\mathrm{{mm}}$" for mode in modes)
            result_fig = plot_reconstruction(position, measured, result, title=title,
                                             modes=modes, span_m=span_m,
                                             nominal_offset_mm=TEST_NOMINAL_OFFSET_MM,
                                             expected_amplitudes_mm=expected_amplitudes)
            save_figure(result_fig, f"{case}/shape_reconstruction.png")
            if SAVE_RESULTS:
                expected_offset = (np.sum(expected_amplitudes) if TEST_NOMINAL_OFFSET_MM is None
                                   else TEST_NOMINAL_OFFSET_MM)
                imposed = (np.cos(2*np.pi*(position[:, None]+span_m/2)*modes/span_m)
                           @ expected_amplitudes - expected_offset)
                error = result["displacement_mm"] - imposed
                folder = PLOT_DIR / case
                folder.mkdir(parents=True, exist_ok=True)
                np.savez_compressed(
                    folder / "reconstruction.npz", position_m=position, modes=modes,
                    basis_ghz_per_mm=basis, measured_shift_ghz=measured,
                    imposed_amplitudes_mm=expected_amplitudes, imposed_displacement_mm=imposed,
                    displacement_error_mm=error, displacement_mae_mm=np.mean(abs(error)),
                    **result, metadata_json=json.dumps({"basis_path": str(BASIS_PATH),
                        "test_path": str(test_path), "span_m": span_m,
                        "linear_detrend": calibration["metadata"].get("linear_detrend", False)}),
                )
                print(f"{case}: displacement MAE {np.mean(abs(error)):.6g} mm; saved to {folder}")
        plot_calibration_cases(calibration)
    plt.show()


if __name__ == "__main__":
    main()
