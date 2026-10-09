"""Peak-anchored arc registration for cosine bending with free axial feeding."""

import numpy as np
from scipy.integrate import cumulative_trapezoid
from scipy.optimize import least_squares
from empirical_basis_inversion import cosine_basis, fit_amplitudes, stack_calibrated_basis


def arc_map(amplitudes, modes, length, origin=0.0):
    x = np.linspace(0, length, 5001)
    q = 2 * np.pi * np.asarray(modes) / length
    slope = np.sum(-np.asarray(amplitudes) * q * np.sin((x[:, None] - origin) * q), axis=1)
    arc = cumulative_trapezoid(np.sqrt(1 + slope**2), x, initial=0)
    # The detected geometric center is held fixed; feeding needs no second shift.
    return x, arc - np.interp(length / 2, x, arc), float(arc[-1])


def correction(position, amplitudes, modes, length, origin=0.0):
    q = 2 * np.pi * np.asarray(modes) / length
    slope = np.sum(-np.asarray(amplitudes) * q * np.sin((position[:, None] - origin) * q), axis=1)
    return (1 + slope**2)**-1.5


def mean_profile(data, length, pass_name="pass_1"):
    reference = np.asarray(data["position_mm"][pass_name], dtype=float) - length / 2
    shifts = np.asarray(data["spectral_shift_ghz"][pass_name], dtype=float)
    count = np.isfinite(shifts).sum(axis=0)
    mean = np.divide(np.nansum(shifts, axis=0), count, out=np.full(reference.shape, np.nan), where=count > 0)
    return reference, mean


def registered_profile(reference, mean, position, amplitudes, modes, length, origin=0.0):
    x, arc, total = arc_map(amplitudes, modes, length, origin)
    requested = np.interp(position, x, arc)
    if requested[0] < reference[0] or requested[-1] > reference[-1]:
        raise ValueError("Arc window exceeds retained ROI; increase padding and select a broader ROI")
    # Fixed horizontal grid prevents discontinuous inclusion/exclusion of edge gages.
    # Keep missing-data gaps as NaNs rather than extrapolating across them.
    measured = np.interp(requested, reference, mean)
    return measured, requested, total


def calibrate_registered(data, amplitude, mode, length, *, finite_slope=False):
    reference, mean = mean_profile(data, length)
    position = np.linspace(0, length, int(np.ceil(length / data["gage_pitch_mm"])) + 1)
    measured, requested, total = registered_profile(reference, mean, position, [amplitude], [mode], length)
    cosine = cosine_basis(position, length, [mode])[:, 0]
    shape = cosine * (correction(position, [amplitude], [mode], length) if finite_slope else 1)
    fit = fit_amplitudes((amplitude * shape)[:, None], measured, allow_offset=True)
    gain = fit["amplitudes_mm"][0]
    return dict(mode_number=mode, active_length_mm=length, origin_mm=0.0,
                imposed_amplitude_mm=amplitude, optical_amplitude_ghz=gain * amplitude,
                optical_basis_ghz_per_mm=gain * cosine, position_mm=position,
                mean_shift_ghz=measured, fitted_shift_ghz=fit["predicted_shift_ghz"],
                residual_ghz=fit["residual_ghz"], offset_ghz=fit["offset_ghz"], rms_ghz=fit["rms_ghz"],
                allow_offset=True, arc_registered=True, finite_slope=finite_slope,
                arc_length_mm=total, reference_position_from_center_mm=requested)


def fit_registered(data, calibrations, *, finite_slope=False, max_iterations=100,
                   amplitude_tolerance=1e-4, arc_tolerance=0.001, relaxation=0.5):
    length = calibrations[0]["active_length_mm"]
    modes = np.array([c["mode_number"] for c in calibrations])
    if any(bool(c.get("finite_slope", False)) for c in calibrations):
        raise ValueError("Use linear calibration gains for this comparison")
    reference, mean = mean_profile(data, length)
    position = np.linspace(0, length, int(np.ceil(length / data["gage_pitch_mm"])) + 1)
    stacked = stack_calibrated_basis(calibrations, position)
    basis, origin = stacked["optical_basis"], stacked["origin_mm"]
    initial_mean, _, _ = registered_profile(reference, mean, position, np.zeros(len(modes)), modes, length, origin)
    initial = fit_amplitudes(basis, initial_mean, allow_offset=True)
    amplitudes, offset = initial["amplitudes_mm"], initial["offset_ghz"]
    history, converged = [], False
    for iteration in range(1, max_iterations + 1):
        measured, requested, total = registered_profile(reference, mean, position, amplitudes, modes, length, origin)
        fit = fit_amplitudes(basis, measured, allow_offset=True)
        updated, offset = fit["amplitudes_mm"], fit["offset_ghz"]
        success = True
        if finite_slope:
            valid = np.isfinite(measured)
            def residual(parameters):
                prediction = correction(position, parameters[:-1], modes, length, origin) * (basis @ parameters[:-1]) + parameters[-1]
                return (prediction - measured)[valid]
            solution = least_squares(residual, np.r_[amplitudes, offset])
            updated, offset, success = solution.x[:-1], solution.x[-1], bool(solution.success)
        predicted = basis @ updated
        if finite_slope:
            predicted *= correction(position, updated, modes, length, origin)
        predicted += offset
        _, _, new_total = arc_map(updated, modes, length, origin)
        delta = float(np.max(np.abs(updated - amplitudes)))
        history.append(dict(iteration=iteration, mapping_amplitudes_mm=amplitudes.copy(),
                            fitted_amplitudes_mm=updated.copy(), mapping_arc_length_mm=total,
                            fitted_arc_length_mm=new_total, amplitude_change_mm=delta,
                            arc_change_mm=abs(new_total-total), optimizer_success=success))
        if success and delta < amplitude_tolerance and abs(new_total-total) < arc_tolerance:
            converged = True
            break
        amplitudes = amplitudes + relaxation * (updated - amplitudes)
    return dict(amplitudes_mm=updated, offset_ghz=offset, predicted_shift_ghz=predicted,
                mean_shift_ghz=measured, residual_ghz=measured-predicted,
                rms_ghz=float(np.sqrt(np.nanmean((measured-predicted)**2))),
                position_mm=position, reference_position_from_center_mm=requested,
                arc_length_mm=new_total, mapping_arc_length_mm=total, converged=converged,
                history=history, mode_numbers=modes, finite_slope=finite_slope)
