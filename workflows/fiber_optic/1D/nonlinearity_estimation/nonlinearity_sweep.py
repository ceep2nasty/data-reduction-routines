"""Sweep all four-mode cosine combinations for curvature and bending yield."""


import csv
from pathlib import Path
from itertools import product

import numpy as np
import pandas as pd

spacing = 0.25 # spacing between amplitudes in mm
max_amp = 5
min_amp = 0.0
n_amplitudes = int(np.floor((max_amp - min_amp) / spacing)) + 1
AMPLITUDES_MM = min_amp + spacing * np.arange(n_amplitudes)
MODE_CASES = [(1, 2)]  # Superposed modes 1 and 2
ACTIVE_LENGTH_MM = 50
THICKNESS_MM = 0.10
YOUNGS_MODULUS_MPA = 193_000.0  # Configurable 301 spring-temper reference
YIELD_STRENGTH_MPA = 1103.0  # Configurable supplier reference, MPa
YIELD_SAFETY_FACTOR = 1.0
MIN_NONLINEAR_DIFFERENCE = 0.05  # Fraction: 5%
GAGE_PITCH = 0.65 # gage pitch parameter, mm
N_POINTS = 2001
OUTPUT_FILE = Path("/mnt/lab_storage/Cole/FTSI/nonlinearity_1D/nonlinearity sweep results.csv")


def max_strain_grad(GAGE_PITCH):
    match GAGE_PITCH:
        case 0.65:
            return 1480
        case 1.30:
            return 465
        case 2.60:
            return 67
        case 5.20:
            return 63


def dw_dx(k, A, N=100, L = 50.):
    """Generate slope at N points for an integer number of modes, k for modal amplitude array, A"""
    modes = np.atleast_1d(np.asarray(k, dtype=float))
    amplitudes = np.atleast_1d(np.asarray(A, dtype=float))

    x = np.linspace(0, L, N)
    q = modes * 2 * np.pi / L
    slope = np.sum(
        -amplitudes[:, None] * q[:, None]
        * np.sin(q[:, None] * x),
        axis=0,
    )
    return x, slope


def d2w_dx2(k,A, N=100, L=50):
    """Generate second derivative at N points for an integer number of modes, k, 
    for modal amplitude array, A"""
    modes = np.atleast_1d(np.asarray(k, dtype=float))
    amplitudes = np.atleast_1d(np.asarray(A, dtype=float))

    x = np.linspace(0, L, N)
    q = modes * 2 * np.pi / L
    d2 = np.sum(
        -amplitudes[:, None] * q[:, None]**2
        * np.cos(q[:, None] * x),
        axis=0,
    )
    return x, d2

def exact_curvature(k, A, L=50, N=100):
        x, second_derivative = d2w_dx2(k, A, N=N, L=L)
        _, slope = dw_dx(k, A, N=N, L=L)
        curvature = second_derivative / (1 + slope**2)**1.5

        return x, curvature

def eps(k, A, t, L=50, N=100):
    x, curvature = exact_curvature(k, A, L, N)
    strain = -t/2 * curvature
    return x, strain

# linear curvature is w''(x). Nonlinear is longer

def nl_curvature_diff(k, A, L=50, N=100):
    """Signed fractional curvature correction relative to linear curvature."""
    x, slope = dw_dx(k, A, N=N, L=L)
    delta = (1 + slope**2)**(-1.5) - 1
    return x, delta


def main(amplitude_options, modes, thickness_mm, E, sigma, sf,
         gage, active_length_mm=50, n_points=2001,
         min_nonlinearity=0.05):
    gradient_limit = max_strain_grad(gage)
    if gradient_limit is None:
        raise ValueError(f"Unsupported gage pitch: {gage}")
    accepted = []

    # Ensure nonlinearity difference is high enough to be observable
    for amplitudes in product(amplitude_options, repeat=len(modes)):
        # Linear surface strain from the combined shape.
        x, second_derivative = d2w_dx2(
            modes, amplitudes, N=n_points, L=active_length_mm
        )
        linear_strain = -thickness_mm / 2 * second_derivative

        peak_linear_strain = np.max(np.abs(linear_strain))
        if peak_linear_strain == 0:
            continue

        # Exact surface strain from that same combined shape.
        _, exact_strain = eps(
            modes, amplitudes, thickness_mm,
            L=active_length_mm, N=n_points
        )

        max_difference = np.max(np.abs(exact_strain - linear_strain))
        nonlinearity = max_difference / peak_linear_strain

        # check against yield strength
        max_stress = np.max(np.abs(exact_strain)) * E  # MPa, uniaxial bending

        # check against strain gradient limit

        strain_gradient = np.gradient(exact_strain, x, edge_order=2)
        peak_gradient = np.max(np.abs(strain_gradient)) * 1e6
        if peak_gradient <= gradient_limit:
            dropout = False
        else:
            dropout = True

        if nonlinearity < min_nonlinearity or (max_stress > sigma/sf) or dropout:
            continue

        accepted.append({
            "amplitudes": amplitudes,
            "max_nonlinearity": nonlinearity,
            "max_strain_difference": max_difference,
            "max_strain_gradient": peak_gradient,
            "max_stress": max_stress
        })

    return accepted

if __name__ == "__main__":
    for mode_case in MODE_CASES:
        MODES = np.asarray(mode_case)
        mode_label = " and ".join(str(mode) for mode in MODES)
        output_file = OUTPUT_FILE.with_name(
            f"{OUTPUT_FILE.stem} modes {mode_label}{OUTPUT_FILE.suffix}"
        )
        results = main(
            AMPLITUDES_MM, MODES, THICKNESS_MM,
            YOUNGS_MODULUS_MPA, YIELD_STRENGTH_MPA, YIELD_SAFETY_FACTOR,
            GAGE_PITCH, active_length_mm=ACTIVE_LENGTH_MM,
            n_points=N_POINTS, min_nonlinearity=MIN_NONLINEAR_DIFFERENCE,
        )
        print(f"\nAccepted {len(results)} of {len(AMPLITUDES_MM) ** len(MODES)} combinations.")
        print(f"Mode order: {tuple(int(mode) for mode in MODES)}")
        print(f"Minimum nonlinearity: {100 * MIN_NONLINEAR_DIFFERENCE:g}%")
        print(f"Allowable uniaxial stress: {YIELD_STRENGTH_MPA / YIELD_SAFETY_FACTOR:g} MPa")
        print(f"Gradient limit: {max_strain_grad(GAGE_PITCH):g} microstrain/mm")
        if results:
            table = pd.DataFrame(results)
            table["max_nonlinearity"] *= 100
            table["max_strain_difference"] *= 1e6
            table = table.rename(columns={
                "amplitudes": "Amplitudes (mm)",
                "max_nonlinearity": "Max Nonlinearity (%)",
                "max_strain_difference": "Strain difference (microstrain)",
                "max_strain_gradient": "Peak gradient (microstrain/mm)",
                "max_stress": "Peak stress (MPa)",
            })
            print(table.to_string(index=False, float_format=lambda value: f"{value:.4g}"))
        else:
            print("No combinations satisfy all configured limits.")

        # Save configuration first, followed by the same results shown in the terminal.
        if not results:
            table = pd.DataFrame(columns=[
                "Amplitudes (mm)", "Max Nonlinearity (%)",
                "Strain difference (microstrain)",
                "Peak gradient (microstrain/mm)", "Peak stress (MPa)",
            ])
        parameters = {
            "Amplitude spacing (mm)": spacing,
            "Minimum amplitude (mm)": min_amp,
            "Maximum amplitude (mm)": max_amp,
            "Amplitude options (mm)": AMPLITUDES_MM.tolist(),
            "Modes (amplitude tuple order)": MODES.tolist(),
            "Active length (mm)": ACTIVE_LENGTH_MM,
            "Thickness (mm)": THICKNESS_MM,
            "Young's modulus (MPa)": YOUNGS_MODULUS_MPA,
            "Yield strength (MPa)": YIELD_STRENGTH_MPA,
            "Yield safety factor": YIELD_SAFETY_FACTOR,
            "Minimum nonlinearity (fraction)": MIN_NONLINEAR_DIFFERENCE,
            "Gage pitch (mm)": GAGE_PITCH,
            "Strain-gradient limit (microstrain/mm)": max_strain_grad(GAGE_PITCH),
            "Position sample count": N_POINTS,
            "Stress model": "Uniaxial elastic bending: E * abs(strain)",
            "Total combinations": len(AMPLITUDES_MM) ** len(MODES),
            "Accepted combinations": len(results),
        }
        output_file.parent.mkdir(parents=True, exist_ok=True)
        with output_file.open("w", newline="", encoding="utf-8") as file:
            writer = csv.writer(file)
            writer.writerow(["Input parameter", "Value"])
            writer.writerows(parameters.items())
            writer.writerow([])
            table.to_csv(file, index=False)
        print(f"Saved: {output_file}")
