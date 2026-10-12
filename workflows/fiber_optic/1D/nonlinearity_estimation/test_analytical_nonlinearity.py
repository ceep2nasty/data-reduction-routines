"""Compare linear and finite-slope amplitude fits to noiseless analytical curvature."""

import csv
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from scipy.optimize import least_squares

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "subroutines"))
from plot_format import format_plot


ACTIVE_LENGTH_MM = 50.0
AMPLITUDES_MM = np.arange(1.0, 6.0)
MODES = (1, 2, 3)
SAMPLE_POINTS = 2001
OUTPUT_DIR = Path(__file__).resolve().parents[4] / "outputs/analytical_nonlinearity"
SHOW_PLOTS = False


def generate_curvature(x, amplitude, k):
    """Exact graph curvature for w(x) = A cos(kx), with no membrane strain."""
    slope = -amplitude * k * np.sin(k * x)
    second_derivative = -amplitude * k**2 * np.cos(k * x)
    return second_derivative / (1.0 + slope**2)**1.5


def fit_amplitudes(x, curvature, k):
    # Fit amplitude and a constant baseline, as in the experimental workflow.
    basis = -k**2 * np.cos(k * x)
    linear, *_ = np.linalg.lstsq(
        np.column_stack((basis, np.ones(x.size))), curvature, rcond=None,
    )

    def residual(parameters):
        amplitude, baseline = parameters
        prediction = amplitude * basis / (1 + (amplitude * k * np.sin(k * x))**2)**1.5
        return prediction + baseline - curvature

    # Start from the linear estimate; the known amplitude is not supplied here.
    nonlinear = least_squares(residual, linear, x_scale="jac",
                              ftol=1e-12, xtol=1e-12, gtol=1e-12)
    linear_prediction = linear[0] * basis + linear[1]
    return linear, nonlinear, linear_prediction, residual(nonlinear.x) + curvature


def main():
    x = np.linspace(0, ACTIVE_LENGTH_MM, SAMPLE_POINTS)
    rows = []
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for mode in MODES:
        k = 2 * np.pi * mode / ACTIVE_LENGTH_MM  # radians/mm, not the mode number
        for amplitude in AMPLITUDES_MM:
            measured = generate_curvature(x, amplitude, k)
            linear, nonlinear, linear_profile, nonlinear_profile = fit_amplitudes(x, measured, k)
            rows.append(dict(
                mode=mode, wavenumber_rad_per_mm=k, imposed_amplitude_mm=amplitude,
                peak_abs_slope=amplitude * k, linear_amplitude_mm=linear[0],
                nonlinear_amplitude_mm=nonlinear.x[0],
                linear_normalized_amplitude=linear[0] / amplitude,
                nonlinear_normalized_amplitude=nonlinear.x[0] / amplitude,
                linear_error_mm=linear[0] - amplitude,
                nonlinear_error_mm=nonlinear.x[0] - amplitude,
                linear_offset_per_mm=linear[1], nonlinear_offset_per_mm=nonlinear.x[1],
                linear_rms_per_mm=np.sqrt(np.mean((linear_profile - measured)**2)),
                nonlinear_rms_per_mm=np.sqrt(np.mean((nonlinear_profile - measured)**2)),
                nonlinear_success=nonlinear.success,
            ))
            np.savez_compressed(
                OUTPUT_DIR / f"mode{mode}_{amplitude:g}mm.npz", position_mm=x,
                curvature_per_mm=measured, linear_curvature_per_mm=linear_profile,
                nonlinear_curvature_per_mm=nonlinear_profile,
            )
            print(f"Mode {mode}, A={amplitude:g} mm, max|w'|={amplitude*k:.3f}: "
                  f"linear={linear[0]:.6f}, nonlinear={nonlinear.x[0]:.6f} mm")
    with (OUTPUT_DIR / "summary.csv").open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

    fig, axes = plt.subplots(1, len(MODES), figsize=(15, 5), sharey=True,
                             constrained_layout=True, squeeze=False)
    for ax, mode in zip(axes[0], MODES):
        selected = [row for row in rows if row["mode"] == mode]
        amplitudes = [row["imposed_amplitude_mm"] for row in selected]
        for key, label, style in (
            ("imposed_amplitude_mm", "Perfect recovery", "k--"),
            ("linear_amplitude_mm", "Linear fit", "o-"),
            ("nonlinear_amplitude_mm", "Finite-slope fit", "x-"),
        ):
            ax.plot(amplitudes, [row[key] / row["imposed_amplitude_mm"] for row in selected],
                    style, label=label)
        ax.set(title=f"Mode {mode}: k = {2*np.pi*mode/ACTIVE_LENGTH_MM:.3f} rad/mm",
               xlabel="Imposed amplitude (mm)", xticks=AMPLITUDES_MM)
        ax.grid(alpha=0.3)
    axes[0, 0].set_ylabel(r"Normalized amplitude $A_{fit}/A_{imposed}$")
    axes[0, 0].legend()
    fig.suptitle("Analytical finite-slope data: 1–5 mm amplitudes over a 50 mm span")
    format_plot(fig)
    fig.savefig(OUTPUT_DIR / "normalized_amplitude_vs_imposed_amplitude.png", dpi=200)
    (OUTPUT_DIR / "README.txt").write_text(
        "Noiseless, mode-isolated cosine shapes on a fixed horizontal grid.\n"
        "Signal: exact curvature w''/(1+w'^2)^1.5; no empirical calibration, arc interpolation, or membrane strain.\n"
        "A known constant strain lever arm or optical gain would only rescale this noiseless comparison.\n"
        "Both fits solve amplitude and baseline. Nonlinear fit starts from the linear estimate.\n"
        "Plot: imposed amplitude versus fitted/imposed amplitude; perfect recovery is 1.\n"
        "This is model self-consistency, not independent physical validation or uncertainty estimation.\n"
        f"Length: {ACTIVE_LENGTH_MM} mm; sample points: {SAMPLE_POINTS}.\n",
        encoding="utf-8",
    )
    if SHOW_PLOTS:
        plt.show()
    else:
        plt.close(fig)
    assert all(row["nonlinear_success"] and abs(row["nonlinear_error_mm"]) < 1e-6 for row in rows), \
        "Nonlinear recovery failed; inspect summary.csv"
    print(f"Verified nonlinear recovery within 1e-6 mm for all {len(rows)} cases. Outputs: {OUTPUT_DIR}")
    return rows


if __name__ == "__main__":
    main()
