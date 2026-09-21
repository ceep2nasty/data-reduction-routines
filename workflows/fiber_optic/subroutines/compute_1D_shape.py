"""Compute one baseline-relative, time-averaged fiber shape without plotting."""

import numpy as np

if __package__:
    from .load_fos_case import read_fos_tsv
else:
    from load_fos_case import read_fos_tsv


def compute_1D_shape(source_file, baseline_file, *, imposed_amplitude_mm,
                     strain_per_ghz=-6.67e-6, n_modes=1, L_p=127,
                     h=0.254, r_fiber=0.155/2, P=100):
    """Return unnormalized data and fit results for one run.

    Positions/displacements are in mm; strain is dimensionless.
    strain_measured has shape (times, ROI gages); modal_amplitudes is (modes,).
    Preserves the original tare arithmetic and least-squares procedure.
    Assumes aligned gages and compatible exported tare references.
    """
    recording = read_fos_tsv(source_file)
    baseline = read_fos_tsv(baseline_file)
    shift = recording["spectral_shift_ghz"]

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

    mode_numbers = np.arange(1, n_modes+1) # number the modes (1, 2, ...)
    wave_numbers = mode_numbers * np.pi / L_p # convert mode numbers to half-sines present 


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

    return {
        "source_file": recording["source_file"],
        "baseline_file": baseline["source_file"],
        "imposed_amplitude_mm": imposed_amplitude_mm,
        "settings": dict(strain_per_ghz=strain_per_ghz, n_modes=n_modes,
                         L_p=L_p, h=h, r_fiber=r_fiber, P=P),
        "recording": recording,
        "baseline": baseline,
        "roi_start_m": roi_start_x,
        "roi_end_m": roi_end_x,
        "roi_mask": roi_mask,
        "x_strain_mm": x_strain,
        "x_shape_mm": x_shape,
        "baseline_mean_shift_ghz": baseline_mean_shift,
        "corrected_shift_ghz": shift,
        "strain_measured": strain_measured,
        "mean_strain": mean_strain,
        "Phi": Phi,
        "Psi": Psi,
        "modal_amplitudes": modal_amplitudes,
        "residuals": residuals,
        "rank": rank,
        "singular_values": singular_values,
        "displacement_mm": displacement,
        "fitted_strain": fitted_strain,
    }
