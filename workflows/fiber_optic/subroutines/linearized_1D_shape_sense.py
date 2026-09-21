## Script to process 1D imposed sine-basis deformation on OBR data by applying Moore-Penrose pseudoinverse

from pathlib import Path
from load_fos_case import read_fos_tsv

import numpy as np
import matplotlib.pyplot as plt

# source file data
source_file = Path("C:/Users/coled/Notre Dame/FTSI F26/lunaData/1D_1Mode_test1/5.0mm_NoLoad_2026-09-17_19-54-34_ch1_gages.tsv") # full path to data

recording = read_fos_tsv(source_file) # read it in as recording

# baseline file data
baseline_file = Path("C:/Users/coled/Notre Dame/FTSI F26/lunaData/1D_1Mode_test1/Baseline_NoLoad_2026-09-17_19-43-57_ch1_gages.tsv")
baseline = read_fos_tsv(baseline_file)

# convert optical shift to strain
strain_per_ghz = -6.67 * 1e-6 #uv run strain or microstrain per GHz freq shift; check with luna
shift = recording["spectral_shift_ghz"] # tared data

# restore both files to untared state
recording_tare = recording["tare_shift_ghz"]
shift = shift + recording_tare

baseline_tare = baseline["tare_shift_ghz"]
baseline_shift = baseline["spectral_shift_ghz"] + baseline_tare

# extract flat mounted data as "new tare"
baseline_mean_shift = np.nanmean(baseline_shift, axis = 0)

# apply new tare
shift = shift - baseline_mean_shift[None, :]

# OBR Data
x_strain = recording["position_m"] # M locations where strain data is stored (x, mm)
roi_start_x = recording["markers"]["Beginning ROI"]["position_m"]
roi_end_x = recording["markers"]["End ROI"]["position_m"]
gage_x = 2.8e-3 # gage length in m
P = 100 
x_shape = np.linspace(roi_start_x, roi_end_x, P) # P locations where shape is reconstructed
strain_measured = strain_per_ghz * shift # Values of recorded strain data at x_strain


# Pass mask on x
# Keep gages within the ROI, including its boundaries.
roi_mask = (x_strain >= roi_start_x) & (x_strain <= roi_end_x)

if not np.any(roi_mask):
    raise ValueError("No strain gages fall within the ROI.")

x_strain = x_strain[roi_mask]                     # (M,)
strain_measured = strain_measured[:, roi_mask]    # (T, M)

# Convert to mm and relative length
x_strain = (x_strain - roi_start_x) * 1000.0
x_shape = (x_shape - roi_start_x) * 1000.0

# Average each gage over time
mean_strain = np.nanmean(strain_measured, axis = 0)

# Spatial basis functions 
n_modes = 1 # number of modes included in analysis
L_p = 127 # panel length in mm, x direction

mode_numbers = np.arange(1, n_modes+1) # number the modes (1, 2, ...)
wave_numbers = mode_numbers * np.pi / L_p # convert mode numbers to half-sines present 
imposed_amplitude = 5.0 # imposed amplitude in mm


h = 0.254 # panel thickness, mm
r_fiber = 0.01 # radius of fiber, mm
z_sensor = (h+r_fiber)/2.0 # z location of measurements taken

# Displacement matrix shape (P,N)
Phi = np.sin(
    np.outer(x_shape, wave_numbers)  # should encode sin(x*r*pi/L) for r modes. each column is a mode with data at each x_shape value going down
)

# Strain matrix shape (M, N)
Psi = (
    z_sensor *
    (wave_numbers)**2 *
    np.sin(np.outer(x_strain,wave_numbers)) # encodes matrix containing strain data at each matrix
)

# Estimate modal amplitudes using least-squares fitting

modal_amplitudes, residuals, rank, singular_values = np.linalg.lstsq(
    Psi, mean_strain, rcond=None
)

displacement = Phi @ modal_amplitudes # P, in mm
fitted_strain = Psi @ modal_amplitudes # (M,) dimensionless
given_shape = imposed_amplitude * np.sin(wave_numbers*x_shape)

# Plot results
fig, (ax_shape, ax_strain) = plt.subplots(
    2, 1,
    figsize = (9,7),
    sharex = True,
    constrained_layout = True,
)

# Reconstructed displacement
ax_shape.plot(x_shape, displacement, color="tab:blue", linewidth=2, label = "reconstructed shape")
ax_shape.plot(x_shape, given_shape, color="tab:gray", linewidth=2, label = "imposed shape")
ax_shape.axhline(0, color="gray", linewidth=0.8)
ax_shape.set_ylabel("Displacement (mm)")
ax_shape.set_title("Shape reconstructed vs shape imposed")
ax_shape.grid(True, alpha=0.3)
ax_shape.legend()

# Measured and fitted strain, displayed in microstrain
ax_strain.plot(
    x_strain, mean_strain * 1e6,
    ".", markersize=4, color="tab:gray",
    label="Measured time average",
)
ax_strain.plot(
    x_strain, fitted_strain * 1e6,
    color="tab:orange", linewidth=2,
    label="Modal fit",
)
ax_strain.set_xlabel("Position from ROI start (mm)")
ax_strain.set_ylabel("Strain (µε)")
ax_strain.legend()
ax_strain.grid(True, alpha=0.3)

plt.show()