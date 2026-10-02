"""Predict expected optical shift for a given imposed shape"""

import numpy as np
import matplotlib.pyplot as plt

# Part and measurement constants
L_active = 50.0  # Active length (mm)
t_sheet = 0.18  # Sheet thickness (mm)
d_fiber = 0.155  # Coated fiber diameter (mm)
z_sensor = (t_sheet + d_fiber) / 2
k_fiber = -2.0  # LUNA strain/GHz calibration constant (unknown)

n_points = 100
x_shape = np.linspace(0, L_active, n_points)


# Define basis modes as A*cos(k*x).
amplitudes = np.array([5.0, 2.5])  # Nominal imposed amplitudes (mm)
mode_numbers = np.arange(1, amplitudes.size + 1)
wave_numbers = mode_numbers * 2 * np.pi / L_active

# displacement basis (modes with no amplitude applied)
Phi = np.cos(np.outer(x_shape, wave_numbers))

# Strain basis: strain = -z * curvature
Psi = z_sensor * wave_numbers**2 * Phi

# Apply modal amplitudes and combine the modes.
imposed_shape = Phi @ amplitudes
imposed_strain = Psi @ amplitudes
expected_shift = imposed_strain / k_fiber

fig, (ax_shape, ax_shift) = plt.subplots(
    2, 1, figsize=(7, 6), constrained_layout=True, sharex=True
)

ax_shape.plot(x_shape, imposed_shape, color="tab:blue", linewidth=2)
ax_shape.set_ylabel("Expected Displacement (mm)")

ax_shift.plot(x_shape, expected_shift, color="tab:orange", linewidth=2)
ax_shift.set_ylabel("Expected Shift (GHz)")
ax_shift.set_xlabel("x Position (mm)")

for ax in (ax_shape, ax_shift):
    ax.grid(alpha=0.25)
    ax.spines[["top", "right"]].set_visible(False)

plt.show()
