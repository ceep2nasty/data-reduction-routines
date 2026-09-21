## Script to process 1D imposed sine-basis deformation on OBR data by applying Moore-Penrose pseudoinverse

from pathlib import Path
from load_fos_case import read_fos_tsv

import numpy as np

# source file data
source_file = Path() # full path to data

recording = read_fos_tsv(source_file) # read it in as recording

# convert optical shift to strain
strain_per_ghz = 0.0 # strain or microstrain per GHz freq shift; check with luna
shift = recording["spectral_shift_ghz"] # pre-tared data

# OBR Data
x_strain = recording["position_m"] # M locations where strain data is stored (x, mm)
x_shape = np.ndarray() # P locations where shape is reconstructed
strain_measured = strain_per_ghz * shift # Values of recorded strain data at x_strain

# Spatial basis functions 
n_modes = 1 # number of modes included in analysis
L_p = 100 # panel length in x direction

mode_numbers = np.arange(1, n_modes+1) # number the modes (1, 2, ...)
wave_numbers = mode_numbers * np.pi / L_p # convert mode numbers to half-sines present 


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

modal_amplitudes, residuals, rank, singular_values = np.linalg.lstsq( Psi, strain_measured, rcond=None, )

