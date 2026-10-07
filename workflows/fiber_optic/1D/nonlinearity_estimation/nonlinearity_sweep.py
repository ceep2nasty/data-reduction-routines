"""Sweep all four-mode cosine combinations for curvature and bending yield."""

import argparse
from pathlib import Path

import numpy as np
import pandas as pd

# 301 spring-temper stainless steel reference values. Young's modulus:
# https://www.tokkin.com/search/stainless-steels/austenitic/301/
# Supplier-listed yield (160 ksi; not a guaranteed minimum for this specimen):
# https://www.oshcut.com/materialdetails/stainless-steel-shim-stock-301-spring-temper
STEEL_301_SPRING_TEMPER_E_MPA = 193_000.0
STEEL_301_SPRING_TEMPER_YIELD_MPA = 160_000 * 0.006894757293168  # psi to MPa
SPECIMEN_THICKNESS_MM = 0.18


def dw_dx(k, A, N=100, L = 50.):
    """Generate slope at N points for an integer number of modes, k for modal amplitude array, A"""
    x = np.linspace(0.0,L, N) # N points x to reconstruct at
    wave_numbers = np.arange(1, k + 1) * (2 * np.pi / L)

    # Assuming cosine basis, dw/dx analytically is -A(2pi*k/L)sin(2pi*k/L)
    slope = np.zeros_like(x)
    for amplitude, wave_number in zip(A, wave_numbers):
        slope += -amplitude * wave_number * np.sin(wave_number * x)

    return x, slope

def d2w_dx2(k,A, N=100, L=50):
    """Generate second derivative at N points for an integer number of modes, k, 
    for modal amplitude array, A"""
    x = np.linspace(0.0,L, N) # N points x to reconstruct at
    wave_numbers = np.arange(1, k + 1) * (2 * np.pi / L)

    d2 = np.zeros_like(x)
    for amplitude, wave_number in zip(A, wave_numbers):
        d2 += -amplitude * (wave_number)**2 * np.cos(wave_number*x)

    return x, d2

# linear curvature is w''(x). Nonlinear is longer

def nl_curvature_diff(k, A, L=50, N=100):
    """Signed fractional curvature correction relative to linear curvature."""
    x, slope = dw_dx(k, A, N=N, L=L)
    delta = (1 + slope**2)**(-1.5) - 1
    return x, delta

def sweep_superposed_modes(amplitudes, modes, thickness_mm,
                           youngs_modulus_mpa, yield_strength_mpa,
                           L=50.0, N=2001):
    """Evaluate every amplitude tuple for the supplied cosine modes.

    For nonnegative amplitudes, all cosine curvatures align at x=0. Thus
    peak absolute curvature is exactly sum(A_k * (2*pi*k/L)**2).
    """
    if L <= 0 or thickness_mm <= 0 or youngs_modulus_mpa <= 0 or yield_strength_mpa <= 0:
        raise ValueError("L, thickness, Young's modulus, and yield strength must be positive")
    modes = np.asarray(modes)
    amplitudes = np.asarray(amplitudes)
    if np.any(modes < 1) or np.any(modes != modes.astype(int)) or len(modes) != len(np.unique(modes)):
        raise ValueError("Modes must be distinct positive integers")
    if np.any(amplitudes < 0):
        raise ValueError("This sweep expects nonnegative amplitudes")

    coefficients = np.stack(
        np.meshgrid(*([amplitudes] * len(modes)), indexing="ij"), axis=-1
    ).reshape(-1, len(modes))
    wave_numbers = modes * (2 * np.pi / L)
    peak_curvature = coefficients @ wave_numbers**2
    peak_strain = thickness_mm / 2 * peak_curvature
    stress = youngs_modulus_mpa * peak_strain
    utilization = stress / yield_strength_mpa
    viable = utilization < 1
    viable_coefficients = coefficients[viable]

    # Only viable cases need the sampled slope calculation. Work in batches
    # so a finer grid does not require a large slope-by-position array.
    x = np.linspace(0.0, L, N)
    basis_slopes = -wave_numbers[:, None] * np.sin(np.outer(wave_numbers, x))
    reduction = np.empty(len(viable_coefficients))
    for start in range(0, len(viable_coefficients), 512):
        batch = viable_coefficients[start:start + 512]
        max_slope = np.max(np.abs(batch @ basis_slopes), axis=1)
        reduction[start:start + 512] = 100 * (1 - (1 + max_slope**2)**(-1.5))

    result = pd.DataFrame(
        viable_coefficients,
        columns=[f"A{int(mode)} (mm)" for mode in modes],
    )
    result["Peak curvature reduction (%)"] = reduction
    result["Peak bending strain"] = peak_strain[viable]
    result["Peak von Mises stress (MPa)"] = stress[viable]
    result["Yield utilization"] = utilization[viable]
    result["Below yield"] = True
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--thickness-mm", type=float,
                        default=SPECIMEN_THICKNESS_MM,
                        help="default: 0.18 mm")
    parser.add_argument("--youngs-modulus-mpa", type=float,
                        default=STEEL_301_SPRING_TEMPER_E_MPA,
                        help="default: 193000 MPa for 301 spring temper")
    parser.add_argument("--yield-strength-mpa", type=float,
                        default=STEEL_301_SPRING_TEMPER_YIELD_MPA,
                        help="default: about 1103 MPa supplier reference for 301 spring temper")
    parser.add_argument("--output-dir", type=Path,
                        default=Path(__file__).resolve().parents[5] / "outputs" / "nonlinearity_estimation")
    args = parser.parse_args()

    amplitudes = np.arange(0, 5.25, 0.25)  # 0, 0.25, ..., 5 mm
    modes = np.arange(1, 5)                # Modes 1 through 4

    args.output_dir.mkdir(parents=True, exist_ok=True)
    viable_cases = sweep_superposed_modes(
        amplitudes, modes, args.thickness_mm,
        args.youngs_modulus_mpa, args.yield_strength_mpa,
    )
    rounded_cases = viable_cases.round({
        "Peak curvature reduction (%)": 2,
        "Peak bending strain": 6,
        "Peak von Mises stress (MPa)": 1,
        "Yield utilization": 3,
    })
    print(f"\n{len(rounded_cases)} of {len(amplitudes) ** len(modes)} four-mode cases below yield:")
    print(rounded_cases.to_string(index=False))
    rounded_cases.to_csv(args.output_dir / "bending_yield_comparison.csv", index=False)
    print(f"\nSaved viable combinations to {args.output_dir / 'bending_yield_comparison.csv'}")
