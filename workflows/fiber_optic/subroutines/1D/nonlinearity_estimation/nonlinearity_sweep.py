"""Do a sweep of amplitudes and wavenumbers to estimate when nonlinear terms contribute"""

import numpy as np
import pandas as pd


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

import pandas as pd

def sweep_curvature(amplitudes, modes, L=50.0, N=2001):
    results = []

    for amplitude in amplitudes:
        row = []

        for mode in modes:
            # Activate only the selected mode.
            A = np.zeros(mode)
            A[mode - 1] = amplitude

            x, slope = dw_dx(mode, A, N=N, L=L)

            # Positive fractional reduction relative to linear curvature.
            reduction = 1 - (1 + slope**2)**(-1.5)
            row.append(100 * np.max(reduction))

        results.append(row)

    return pd.DataFrame(
        results,
        index=pd.Index(amplitudes, name="Amplitude"),
        columns=[f"Mode {mode}" for mode in modes],
    )


amplitudes = np.linspace(0, 5, 11)  # 0, 0.5, ..., 5
modes = np.arange(1, 7)           # Modes 1 through 6

table = sweep_curvature(amplitudes, modes)

print(table.round(2))
table.to_csv("curvature_reduction_percent.csv")