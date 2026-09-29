"""Calibrate bonded PR100 optical shift from the 25 Sep three-point bend test."""

import argparse
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "subroutines"))
from load_fos_case import read_fos_tsv


DATA_DIR = Path(r"C:\Users\coled\Notre Dame\FTSI F26\bend_tests\25SEP26_tests")
SAVE_DIR = Path(r"C:\Users\coled\Notre Dame\FTSI F26\bend_tests\25SEP26_tests\output_figs")
DEFLECTION_FILE = DATA_DIR / "deflection_test_2_pr100.csv"
FOS_FILE = DATA_DIR / (
    "BendTest_Deflectometer_PR100_5Load5Unload_1mm_Test2_"
    "2026-09-25_22-29-01_ch1_gages.tsv"
)
SPAN_MM = 127.0
DELRIN_THICKNESS_MM = 0.254
FIBER_DIAMETER_MM = 0.155
HOLD_LEVELS_MM = (1, 2, 3, 4, 5, 4, 3, 2, 1, 0)


def smooth(values):
    return np.convolve(values, np.ones(20) / 20, mode="same")


def find_onset(time_s, signal):
    filtered = smooth(signal)
    baseline = filtered[time_s <= time_s[0] + 3]
    center = np.median(baseline)
    noise = 1.4826 * np.median(np.abs(baseline - center))
    threshold = max(8 * noise, 0.01 * np.ptp(np.percentile(filtered, [1, 99])))
    changed = np.abs(filtered - center) > threshold
    sustained = np.convolve(changed.astype(int), np.ones(20, dtype=int), mode="valid")
    candidates = np.flatnonzero(sustained == 20)
    candidates = candidates[candidates >= len(baseline)]
    if not len(candidates):
        raise ValueError("Could not detect loading onset")
    return int(candidates[0])


def find_holds(time_s, deflection_mm):
    holds = []
    search_after = np.searchsorted(time_s, 0)
    filtered = smooth(deflection_mm)
    for number, level in enumerate(HOLD_LEVELS_MM, start=1):
        near = np.abs(filtered - level) <= 0.20
        changes = np.diff(np.pad(near.astype(int), (1, 1)))
        regions = zip(np.flatnonzero(changes == 1), np.flatnonzero(changes == -1))
        regions = [(a, b) for a, b in regions
                   if a >= search_after and time_s[b - 1] - time_s[a] >= 2.5]
        if not regions:
            raise ValueError(f"Could not find hold {number} near {level} mm")
        start, stop = regions[0]
        fit_start = time_s[start] + 1
        holds.append({
            "number": number,
            "level": level,
            "direction": "loading" if number <= 5 else "unloading",
            "start": time_s[start],
            "stop": time_s[stop - 1],
            "fit_start": fit_start,
            "fit_stop": min(fit_start + 3, time_s[stop - 1]),
        })
        search_after = stop
    return holds


def marker_indices(fos, begin, end):
    x = fos["position_m"]
    markers = fos["markers"]
    return np.flatnonzero(
        (x >= markers[begin]["position_m"]) & (x <= markers[end]["position_m"])
    )


def spatial_change(fos, time_s, indices, hold):
    shifts = fos["spectral_shift_ghz"][:, indices]
    baseline = (time_s >= -3) & (time_s <= -0.5)
    loaded = (time_s >= hold["fit_start"]) & (time_s <= hold["fit_stop"])
    valid = np.any(np.isfinite(shifts[baseline]), axis=0) & np.any(
        np.isfinite(shifts[loaded]), axis=0
    )
    change = np.full(len(indices), np.nan)
    change[valid] = np.nanmedian(shifts[loaded][:, valid], axis=0) - np.nanmedian(
        shifts[baseline][:, valid], axis=0
    )
    return change


def peak_shift(fos, time_s, indices):
    """Track the largest absolute change per sample, retaining its sign."""
    shifts = fos["spectral_shift_ghz"][:, indices]
    baseline = (time_s >= -3) & (time_s <= -0.5)
    valid = np.any(np.isfinite(shifts[baseline]), axis=0)
    indices = indices[valid]
    changes = shifts[:, valid] - np.nanmedian(shifts[baseline][:, valid], axis=0)
    available = np.any(np.isfinite(changes), axis=1)
    scores = np.where(np.isfinite(changes), np.abs(changes), -np.inf)
    peak = np.argmax(scores, axis=1)
    signal = changes[np.arange(len(changes)), peak]
    signal[~available] = np.nan
    positions = fos["position_m"][indices[peak]].copy()
    positions[~available] = np.nan
    return signal, positions


def fit_line(x, y):
    zero_slope = np.dot(x, y) / np.dot(x, x)
    slope, intercept = np.polyfit(x, y, 1)
    prediction = slope * x + intercept
    r_squared = 1 - np.sum((y - prediction) ** 2) / np.sum((y - np.mean(y)) ** 2)
    return zero_slope, slope, intercept, r_squared


def plot_aligned(td, deflection, tf, passes):
    fig, axes = plt.subplots(2, 1, figsize=(12, 7), sharex=True,
                             constrained_layout=True)
    axes[0].plot(td, deflection)
    axes[0].set(title="Aligned raw deflection and peak optical shift",
                ylabel="Deflection change (mm)")
    for data in passes:
        axes[1].plot(tf, data["signal"], label=data["name"], linewidth=0.8)
    axes[1].set(xlabel="Time from loading onset (s)",
                ylabel="Peak shift change (GHz)")
    axes[1].legend()
    for ax in axes:
        ax.axvline(0, color="k", linestyle="--", linewidth=0.8)
        ax.grid(alpha=0.3)
    return fig


def plot_hold_stability(td, deflection, tf, signals, holds):
    fig, axes = plt.subplots(2, 1, figsize=(11, 8), sharex=True, constrained_layout=True)
    colors = plt.get_cmap("viridis")(np.linspace(0, 1, len(holds)))
    for color, hold in zip(colors, holds):
        stop = min(hold["stop"], hold["start"] + 6)
        mask = (td >= hold["start"]) & (td <= stop)
        values = deflection[mask]
        axes[0].plot(td[mask] - hold["start"], values - np.median(values), color=color,
                     label=f"{hold['number']}: {hold['level']} mm {hold['direction'][0].upper()}")
        mask = (tf >= hold["start"]) & (tf <= stop)
        for number, signal in enumerate(signals):
            values = signal[mask]
            axes[1].plot(tf[mask] - hold["start"], values - np.nanmedian(values),
                         color=color, linestyle="-" if number == 0 else "--")
    for ax in axes:
        ax.axvspan(1, 4, color="0.5", alpha=0.12)
        ax.axhline(0, color="0.3", linewidth=0.8)
        ax.grid(alpha=0.3)
    axes[0].set(title="Within-hold stability", ylabel="Deflection residual (mm)")
    axes[0].legend(fontsize=7, ncol=5)
    axes[1].set(xlabel="Time since entering nominal band (s)",
                ylabel="Optical-shift residual (GHz)", xlim=(0, 6))
    axes[1].text(0.99, 0.04, "solid: pass 1   dashed: pass 2",
                 transform=axes[1].transAxes, ha="right")
    return fig


def plot_spatial_selection(fos, time_s, passes, holds):
    fig, axes = plt.subplots(2, 1, figsize=(11, 8), constrained_layout=True)
    loading = {hold["level"]: hold for hold in holds[:5]}
    for ax, data in zip(axes, passes):
        indices = data["indices"]
        x = fos["position_m"][indices]
        x = (x[-1] - x if data["reverse"] else x - x[0]) * 1000
        for level in (1, 3, 5):
            profile = spatial_change(fos, time_s, indices, loading[level])
            line, = ax.plot(x, profile, ".-", markersize=3,
                            label=f"{level} mm loading hold")
            peak = np.nanargmax(np.abs(profile))
            ax.plot(x[peak], profile[peak], "*", markersize=12, color=line.get_color())
        ax.set(title=f"{data['name']}: stars mark peaks of hold-median profiles",
               ylabel="Shift change (GHz)")
        ax.grid(alpha=0.3)
        ax.legend()
    axes[-1].set_xlabel("Distance from physical pass edge (mm)")
    return fig


def plot_calibration(results, strain, holds, boundary_factor):
    fig, axes = plt.subplots(2, 2, figsize=(13, 9), sharex="col",
                             constrained_layout=True, gridspec_kw={"height_ratios": (3, 1)})
    strain = strain * 1e6
    for column, result in enumerate(results):
        shift = result["shift"]
        zero, slope, intercept, r_squared = result["fit"]
        ax, residual_ax = axes[:, column]
        ax.plot(shift[:5], strain[:5], "o-", label="Loading")
        ax.plot(shift[5:], strain[5:], "s--", fillstyle="none", label="Unloading")
        for x, y, hold in zip(shift, strain, holds):
            ax.annotate(str(hold["level"]), (x, y), xytext=(5, 4),
                        textcoords="offset points", fontsize=8)
        fit_x = np.linspace(min(0, shift.min()), max(0, shift.max()), 100)
        ax.plot(fit_x, zero * fit_x * 1e6, "k", label="Zero-intercept fit")
        ax.plot(fit_x, (slope * fit_x + intercept) * 1e6, color="0.4",
                linestyle=":", label="Free-intercept fit")
        ax.set_title(f"{result['name']}\n{zero:.3e} strain/GHz; $R^2$={r_squared:.4f}")
        ax.set_ylabel("Reference strain change (microstrain)")
        ax.grid(alpha=0.3)
        ax.legend(fontsize="small")
        residual = strain - zero * shift * 1e6
        residual_ax.plot(shift[:5], residual[:5], "o-")
        residual_ax.plot(shift[5:], residual[5:], "s--", fillstyle="none")
        residual_ax.axhline(0, color="k", linewidth=0.8)
        residual_ax.set(xlabel="Optical-shift change (GHz)", ylabel="Residual\n(microstrain)")
        residual_ax.grid(alpha=0.3)
    fig.suptitle(f"Hold-based calibration, boundary factor = {boundary_factor:g}")
    return fig


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--deflection-file", type=Path, default=DEFLECTION_FILE)
    parser.add_argument("--fos-file", type=Path, default=FOS_FILE)
    parser.add_argument("--boundary-factor", type=float, default=12.0)
    parser.add_argument("--save-dir", type=Path, default=SAVE_DIR,
                        help=f"Figure output folder (default: {SAVE_DIR})")
    parser.add_argument("--no-plot", action="store_true")
    args = parser.parse_args()

    elapsed_ms, deflection = np.loadtxt(
        args.deflection_file, delimiter=",", usecols=(1, 2), unpack=True
    )
    td = elapsed_ms / 1000
    fos = read_fos_tsv(args.fos_file)
    tf = fos["time_s"]
    pass_specs = (
        ("First pass", "First Pass Begin", "First Pass End", False),
        ("Second pass", "Second Pass Start", "Second Pass End", True),
    )
    pass_indices = [marker_indices(fos, begin, end) for _, begin, end, _ in pass_specs]
    whole_pass_signals = [
        np.nanmedian(fos["spectral_shift_ghz"][:, indices], axis=1)
        for indices in pass_indices
    ]

    td -= td[find_onset(td, deflection)]
    tf -= tf[find_onset(tf, np.mean(whole_pass_signals, axis=0))]
    baseline = (td >= -3) & (td <= -0.5)
    deflection_change = deflection - np.median(deflection[baseline])
    holds = find_holds(td, deflection_change)

    passes = []
    for spec, indices in zip(pass_specs, pass_indices):
        name, _, _, reverse = spec
        signal, peak_positions = peak_shift(fos, tf, indices)
        passes.append({"name": name, "indices": indices, "peak_positions_m": peak_positions,
                       "reverse": reverse, "signal": signal})

    hold_deflection = np.asarray([
        np.median(deflection_change[(td >= h["fit_start"]) & (td <= h["fit_stop"])])
        for h in holds
    ])
    fiber_offset = DELRIN_THICKNESS_MM / 2 + FIBER_DIAMETER_MM / 2
    strain_per_mm = args.boundary_factor * fiber_offset / SPAN_MM**2
    strain = strain_per_mm * hold_deflection

    results = []
    for data in passes:
        shift = np.asarray([
            np.nanmedian(data["signal"][(tf >= h["fit_start"]) & (tf <= h["fit_stop"])])
            for h in holds
        ])
        results.append({
            "name": data["name"], "shift": shift,
            "deflection_fit": fit_line(shift, hold_deflection),
            "fit": fit_line(shift, strain),
            "loading_fit": fit_line(shift[:5], strain[:5]),
            "unloading_fit": fit_line(shift[5:], strain[5:]),
        })

    print(f"Elapsed time: {elapsed_ms[-1] / 1000:.3f} s")
    print(f"Total deflection: {np.ptp(deflection):.6f} mm")
    print(f"Reference strain rate: {strain_per_mm * 1e6:.3f} microstrain/mm")
    for data, result in zip(passes, results):
        print(f"{result['name']}: peak shift tracked independently at each sample")
        print(f"  deflection/GHz: {result['deflection_fit'][0]:.6e} mm/GHz")
        print(f"  strain/GHz: {result['fit'][0]:.6e}")
        print(f"  loading/unloading: {result['loading_fit'][0]:.6e} / "
              f"{result['unloading_fit'][0]:.6e}")

    figures = {
        "01_aligned_signals.png": plot_aligned(td, deflection_change, tf, passes),
        "02_hold_stability.png": plot_hold_stability(
            td, deflection, tf, [data["signal"] for data in passes], holds
        ),
        "03_spatial_gage_selection.png": plot_spatial_selection(fos, tf, passes, holds),
        "04_calibration.png": plot_calibration(results, strain, holds, args.boundary_factor),
    }
    if args.save_dir:
        args.save_dir.mkdir(parents=True, exist_ok=True)
        for filename, figure in figures.items():
            figure.savefig(args.save_dir / filename, dpi=200, bbox_inches="tight")
        print(f"Saved {len(figures)} figures to {args.save_dir.resolve()}")
    if not args.no_plot:
        plt.show()
    return {"holds": holds, "passes": passes, "results": results, "strain": strain}


if __name__ == "__main__":
    calibration = main()
