"""Predict cosine-shape optical shift along the deformed sensor arc.

The imposed cosine is specified in horizontal coordinates. The sensor follows
the sheet at signed normal offset z_sensor; axial stretching of the sheet's
neutral line is omitted. Luna reference-state positions require a separate
material-coordinate registration before direct comparison with this arc axis.
"""

import numpy as np
import matplotlib.pyplot as plt

# Part and measurement constants
L_active = 50.0  # Active length (mm)
t_sheet = 0.18  # Sheet thickness (mm)
d_fiber = 0.155  # Coated fiber diameter (mm)
z_sensor = (t_sheet + d_fiber) / 2
k_fiber = -2.0  # LUNA strain/GHz calibration constant (unknown)

n_points = 2001
x_shape = np.linspace(0, L_active, n_points)


# Define basis modes as A*cos(k*x).
amplitudes = np.array([5.0, 2.5])  # Nominal imposed amplitudes (mm)
mode_numbers = np.arange(1, amplitudes.size + 1)
wave_numbers = mode_numbers * 2 * np.pi / L_active

# displacement basis (modes with no amplitude applied)
Phi = np.cos(np.outer(x_shape, wave_numbers))

# Small-slope strain basis, retained as a comparison.
Psi = z_sensor * wave_numbers**2 * Phi

# Apply modal amplitudes and combine the modes.
imposed_shape = Phi @ amplitudes
linearized_strain = Psi @ amplitudes
imposed_slope = -np.sin(np.outer(x_shape, wave_numbers)) @ (wave_numbers * amplitudes)
imposed_second_derivative = -Phi @ (wave_numbers**2 * amplitudes)


def arc_geometry(x, slope, second_derivative, sensor_offset_mm=0.0):
    """Return neutral/sensor arc coordinates and signed neutral curvature.

    For the chosen normal, the offset sensor has ds_sensor=(1-z*kappa)ds.
    The bending strain -z*kappa uses the same sign convention.
    """
    metric = np.sqrt(1 + slope**2)
    curvature = second_derivative / metric**3
    sensor_metric = metric * (1 - sensor_offset_mm * curvature)
    if np.any(sensor_metric <= 0):
        raise ValueError("Sensor offset creates a singular or reversed offset curve")

    def cumulative_arc(integrand):
        increments = 0.5 * (integrand[:-1] + integrand[1:]) * np.diff(x)
        return np.concatenate(([0.0], np.cumsum(increments)))

    return cumulative_arc(metric), cumulative_arc(sensor_metric), curvature


neutral_arc_mm, sensor_arc_mm, imposed_curvature = arc_geometry(
    x_shape, imposed_slope, imposed_second_derivative, z_sensor
)
imposed_strain = -z_sensor * imposed_curvature
expected_shift = imposed_strain / k_fiber

fig, (ax_shape, ax_shift) = plt.subplots(
    2, 1, figsize=(7, 6), constrained_layout=True, sharex=True
)

ax_shape.plot(sensor_arc_mm, imposed_shape, color="tab:blue", linewidth=2)
ax_shape.set_ylabel("Expected Displacement (mm)")

ax_shift.plot(sensor_arc_mm, expected_shift, color="tab:orange", linewidth=2,
              label="Finite-slope curvature")
ax_shift.plot(sensor_arc_mm, linearized_strain / k_fiber, color="0.5",
              linestyle="--", label="Small-slope curvature")
ax_shift.legend()
ax_shift.set_ylabel("Expected Shift (GHz)")
ax_shift.set_xlabel("Deformed sensor arc length (mm)")
print(f"Horizontal span: {L_active:.3f} mm; neutral arc: {neutral_arc_mm[-1]:.3f} mm; "
      f"sensor arc: {sensor_arc_mm[-1]:.3f} mm")

for ax in (ax_shape, ax_shift):
    ax.grid(alpha=0.25)
    ax.spines[["top", "right"]].set_visible(False)

plt.show()
