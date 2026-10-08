"""Calibrate and invert empirical optical bases, then evaluate cosine shapes.

Numerical functions accept prepared arrays. File loading, coordinate
registration, plotting, and workflow configuration belong to the caller.
"""


from pathlib import Path

import numpy as np


def calibrate_basis(
    position_mm,
    calibration_shift_ghz,
    imposed_amplitude_mm,
    active_length_mm,
    mode_number=1,
    *,
    origin_mm=0.0,
    allow_offset=True,
):
    """Fit a pure-mode optical profile and normalize by imposed amplitude.

    position_mm: shape (positions,)
    calibration_shift_ghz: shape (positions,) or (time, positions)

    Returns a cosine optical basis in GHz/mm plus fit diagnostics.
    Coordinates and origin must use the intended cosine phase.
    """
    position = np.asarray(position_mm, dtype=float)
    shift = np.asarray(calibration_shift_ghz, dtype=float)

    if not np.isfinite(imposed_amplitude_mm) or imposed_amplitude_mm == 0:
        raise ValueError("Imposed amplitude must be finite and nonzero.")

    if not np.isfinite(active_length_mm) or active_length_mm <= 0:
        raise ValueError("Active length must be finite and positive.")

    if mode_number < 1 or int(mode_number) != mode_number:
        raise ValueError("Mode number must be a positive integer.")

    if position.ndim != 1:
        raise ValueError("Position must be a one-dimensional array.")

    # Average over time, keeping entirely missing positions as NaN.
    if shift.ndim == 2:
        if shift.shape[1] != position.size:
            raise ValueError("Shift columns must match positions.")

        count = np.sum(np.isfinite(shift), axis=0)
        total = np.sum(np.where(np.isfinite(shift), shift, 0.0), axis=0)
        mean_shift = np.full(position.shape, np.nan)
        np.divide(total, count, out=mean_shift, where=count > 0)

    elif shift.ndim == 1 and shift.shape == position.shape:
        mean_shift = shift
    else:
        raise ValueError("Shift must have shape (positions,) or (time, positions).")

    # Prescribed unit-amplitude cosine; phase is fixed by origin_mm.
    cosine = np.cos(
        2 * np.pi * mode_number
        * (position - origin_mm) / active_length_mm
    )

    valid = np.isfinite(position) & np.isfinite(mean_shift)
    design = cosine[valid, None]

    if allow_offset:
        design = np.column_stack([design, np.ones(valid.sum())])

    if valid.sum() < design.shape[1]:
        raise ValueError("Not enough valid positions for calibration.")

    coefficients, _, rank, _ = np.linalg.lstsq(
        design, mean_shift[valid], rcond=None
    )

    if rank < design.shape[1]:
        raise ValueError("Calibration design is rank deficient.")

    optical_amplitude_ghz = coefficients[0]
    offset_ghz = coefficients[1] if allow_offset else 0.0

    fitted_shift = optical_amplitude_ghz * cosine + offset_ghz
    residual = mean_shift - fitted_shift

    # Exclude the baseline from the deformation response.
    optical_basis = (
        optical_amplitude_ghz / imposed_amplitude_mm
    ) * cosine

    return {
        "mode_number": int(mode_number),
        "active_length_mm": float(active_length_mm),
        "origin_mm": float(origin_mm),
        "allow_offset": bool(allow_offset),
        "position_mm": position,
        "optical_basis_ghz_per_mm": optical_basis,
        "optical_amplitude_ghz": optical_amplitude_ghz,
        "imposed_amplitude_mm": imposed_amplitude_mm,
        "offset_ghz": offset_ghz,
        "mean_shift_ghz": mean_shift,
        "fitted_shift_ghz": fitted_shift,
        "residual_ghz": residual,
        "valid_mask": valid,
        "rms_ghz": np.sqrt(np.mean(residual[valid] ** 2)),
    }


def save_calibrated_basis(calibration, output_dir, name):
    """Save a calibration dictionary as a compressed NumPy .npz file.

    Creates output_dir as needed. Supply a descriptive filename stem (for
    example, 'bottom_mode1_1mm') or a filename ending in .npz. Existing files
    are not overwritten. Saves positions, normalized optical basis, cosine
    settings, prescribed amplitude, baseline, and fit diagnostics.

    Returns the saved Path. Only numerical arrays and scalars are accepted,
    so loading never requires pickle.
    """
    name = str(name)
    if not name or name in {".", ".."} or "/" in name or "\\" in name:
        raise ValueError("Name must be a filename, not a path")
    filename = name if name.endswith(".npz") else name + ".npz"
    arrays = {key: np.asarray(value) for key, value in calibration.items()}
    if any(value.dtype.kind not in "biufc" for value in arrays.values()):
        raise ValueError("Calibration fields must be numerical arrays or scalars")
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    path = output_dir / filename
    with path.open("xb") as file:
        np.savez_compressed(file, **arrays)
    return path


def load_calibrated_basis(path):
    """Load a saved .npz calibration into a dictionary without using pickle.

    Array fields retain their shapes and NaNs; scalar fields are restored
    as Python scalars. Use optical_basis_ghz_per_mm and position_mm for later
    inversion, checking registration and modal settings against the target.
    """
    with np.load(Path(path), allow_pickle=False) as archive:
        return {
            key: archive[key].item() if archive[key].ndim == 0 else archive[key].copy()
            for key in archive.files
        }


def stack_calibrated_basis(calibrations, target_position_mm, *, window_start_mm=0.0):
    """Evaluate saved cosine calibrations on a registered target grid.

    Supply calibration dictionaries in the desired modal order and finite,
    increasing target positions (P,). All calibrations must share length and
    cosine origin and have unique modes. window_start_mm sets the active
    window boundary independently of cosine phase.

    Returns optical_basis (P, modes) in GHz/mm, position_mm, mode_numbers,
    gains_ghz_per_mm, active_length_mm, origin_mm, and window_start_mm.
    Baselines are excluded. Caller handles registration and verifies matching
    sensor/setup; positions are not rescaled or automatically aligned.
    """
    calibrations = list(calibrations)
    position = np.asarray(target_position_mm, dtype=float)
    if not calibrations:
        raise ValueError("Supply at least one calibration")
    if (position.ndim != 1 or position.size == 0 or
            not np.all(np.isfinite(position)) or np.any(np.diff(position) <= 0)):
        raise ValueError("Target positions must be finite, nonempty, and strictly increasing")
    if not np.isfinite(window_start_mm):
        raise ValueError("Window start must be finite")

    columns, modes, gains = [], [], []
    length = origin = None
    for calibration in calibrations:
        mode = float(calibration["mode_number"])
        current_length = float(calibration["active_length_mm"])
        current_origin = float(calibration["origin_mm"])
        optical_amplitude = float(calibration["optical_amplitude_ghz"])
        imposed_amplitude = float(calibration["imposed_amplitude_mm"])
        if not np.all(np.isfinite([mode, current_length, current_origin, optical_amplitude, imposed_amplitude])):
            raise ValueError("Calibration coefficients and settings must be finite")
        if mode < 1 or int(mode) != mode or current_length <= 0 or imposed_amplitude == 0:
            raise ValueError("Invalid calibration mode, length, or imposed amplitude")
        if int(mode) in modes:
            raise ValueError("Each stacked cosine mode must be unique")
        if length is None:
            length, origin = current_length, current_origin
        elif not (np.isclose(length, current_length, rtol=1e-10, atol=1e-10) and
                  np.isclose(origin, current_origin, rtol=1e-10, atol=1e-10)):
            raise ValueError("Calibrations must share active length and cosine origin")
        gain = optical_amplitude / imposed_amplitude
        if not np.isfinite(gain) or gain == 0:
            raise ValueError("Calibration gain must be finite and nonzero")
        columns.append(gain * np.cos(2 * np.pi * mode * (position - origin) / length))
        modes.append(int(mode))
        gains.append(gain)

    tolerance = 1e-10 * max(1.0, length)
    if np.any(position < window_start_mm - tolerance) or np.any(position > window_start_mm + length + tolerance):
        raise ValueError("Target positions must lie inside the prescribed active window")
    return {
        "optical_basis": np.column_stack(columns),
        "position_mm": position.copy(),
        "mode_numbers": np.asarray(modes, dtype=int),
        "gains_ghz_per_mm": np.asarray(gains),
        "active_length_mm": length,
        "origin_mm": origin,
        "window_start_mm": float(window_start_mm),
    }


def fit_amplitudes(optical_basis, measured_shift_ghz, *, allow_offset=False):
    """Fit amplitudes in mm from a registered optical basis using least squares.

    Basis: (positions, modes), GHz/mm. Measurements: (positions,) or
    (time, positions), GHz. Each sample excludes nonfinite measurements/basis
    rows. An optional constant optical baseline is separate from amplitudes.

    Returns amplitudes_mm, offset_ghz, predicted_shift_ghz, residual_ghz,
    valid_mask, valid_count, rms_ghz, rank, singular_values, condition_number.
    Predictions/residuals match the input shape; excluded points are NaN.
    Batch amplitudes are (time, modes) and scalar diagnostics are (time,).
    Single-profile amplitudes are (modes,) and scalar diagnostics are scalars.
    Raises ValueError for shape mismatch, insufficient data, or rank deficiency.
    """
    basis = np.asarray(optical_basis, dtype=float)
    measured = np.asarray(measured_shift_ghz, dtype=float)
    if basis.ndim != 2 or min(basis.shape) == 0:
        raise ValueError("Optical basis must be a nonempty (positions, modes) matrix")
    single = measured.ndim == 1
    if measured.ndim not in (1, 2) or measured.shape[-1] != basis.shape[0] or measured.size == 0:
        raise ValueError("Measurements must have shape (positions,) or (time, positions) matching the basis")
    samples = measured[None, :] if single else measured
    n_times = len(samples)
    n_modes = basis.shape[1]
    n_parameters = n_modes + int(allow_offset)
    amplitudes = np.empty((n_times, n_modes))
    offsets = np.zeros(n_times)
    prediction = np.full(samples.shape, np.nan)
    residual = np.full(samples.shape, np.nan)
    masks = np.zeros(samples.shape, dtype=bool)
    ranks = np.empty(n_times, dtype=int)
    singular_values = np.empty((n_times, n_parameters))
    condition = np.empty(n_times)
    rms = np.empty(n_times)
    full_design = np.column_stack((basis, np.ones(len(basis)))) if allow_offset else basis
    finite_basis = np.all(np.isfinite(basis), axis=1)
    for index, sample in enumerate(samples):
        valid = finite_basis & np.isfinite(sample)
        if valid.sum() < n_parameters:
            raise ValueError(f"Sample {index}: insufficient valid positions for {n_parameters} coefficients")
        design = full_design[valid]
        coefficients, _, rank, singular = np.linalg.lstsq(design, sample[valid], rcond=None)
        if rank < n_parameters:
            raise ValueError(f"Sample {index}: rank-deficient optical basis")
        amplitudes[index] = coefficients[:n_modes]
        if allow_offset:
            offsets[index] = coefficients[-1]
        prediction[index, valid] = design @ coefficients
        residual[index, valid] = sample[valid] - prediction[index, valid]
        masks[index] = valid
        ranks[index] = rank
        singular_values[index] = singular
        condition[index] = singular[0] / singular[-1]
        rms[index] = np.sqrt(np.mean(residual[index, valid] ** 2))
    result = {
        "amplitudes_mm": amplitudes, "offset_ghz": offsets,
        "predicted_shift_ghz": prediction, "residual_ghz": residual,
        "valid_mask": masks, "valid_count": masks.sum(axis=1),
        "rms_ghz": rms, "rank": ranks, "singular_values": singular_values,
        "condition_number": condition,
    }
    if single:
        return {key: value[0].item() if value[0].ndim == 0 else value[0]
                for key, value in result.items()}
    return result


def cosine_basis(position_mm, active_length_mm, mode_numbers, *, origin_mm=0.0):
    """Return unit-amplitude cosine columns, shaped (positions, modes).

    Positions, active length, and origin are in mm. Multiply by amplitudes
    in mm to obtain displacement: basis @ amplitudes for a single sample,
    or amplitudes @ basis.T for a (time, modes) batch. Mode order is preserved.
    """
    position = np.asarray(position_mm, dtype=float)
    modes = np.atleast_1d(np.asarray(mode_numbers, dtype=float))
    return np.cos(
        2 * np.pi * (position[:, None] - origin_mm)
        * modes[None, :] / active_length_mm
    )
