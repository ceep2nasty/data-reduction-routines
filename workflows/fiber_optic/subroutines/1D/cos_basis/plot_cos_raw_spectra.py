"""Plot time-averaged Luna spectral shifts for static COS tests."""

import sys
from pathlib import Path

# Shared readers remain in the parent subroutines directory.
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import argparse
import csv
import re
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

DATA_DIR = Path(r"C:\Users\coled\Notre Dame\FTSI F26\lunaData\1D COS BASIS")
X_MAX_M = 2.1   # Exclude the noisy fiber tail from display and autoscaling.
K1_2_5_X_MAX_M = 1.9


def read_full_tsv(path):
    """Read full-profile exports, which have no named-gage header."""
    path = Path(path)
    positions = None
    samples = []
    metadata = {}
    with path.open(encoding="utf-8-sig", newline="") as file:
        for line, row in enumerate(csv.reader(file, delimiter="\t"), start=1):
            if not row:
                continue
            if row[0].endswith(":"):
                metadata[row[0][:-1]] = "\t".join(row[1:]).strip()
            if row[0] == "x-axis":
                positions = np.asarray(row[3:], dtype=float)
            elif len(row) >= 3 and row[1] == "measurement":
                if positions is None or len(row) != len(positions) + 3:
                    raise ValueError(f"{path.name}, line {line}: invalid profile width")
                if row[2] != "xcorr shift":
                    raise ValueError(f"{path.name}, line {line}: unexpected measurement type")
                samples.append([float(value) if value.strip() else np.nan for value in row[3:]])
    if metadata.get("Units") != "spectral shift (GHz)" or metadata.get("X-Axis Units") != "m":
        raise ValueError(f"{path.name}: expected spectral shift (GHz) and positions in m")
    if positions is None or not samples:
        raise ValueError(f"{path.name}: missing positions or measurements")
    if not np.all(np.isfinite(positions)) or np.any(np.diff(positions) <= 0):
        raise ValueError(f"{path.name}: positions must be finite and increasing")
    shift = np.asarray(samples)
    if np.any(np.isinf(shift)):
        raise ValueError(f"{path.name}: measurements contain infinite values")
    return {"source_file": path, "position_m": positions, "spectral_shift_ghz": shift}


def recording_label(path):
    """Extract mode and amplitude from names such as k2_amp_2_5_..."""
    match = re.search(r"k(\d+)_amp_?(\d+)_(\d+)(?:_|$)", Path(path).stem)
    if match is None:
        return Path(path).stem
    mode, whole, fraction = match.groups()
    amplitude = float(f"{whole}.{fraction}")
    label = f"k = {int(mode)}, amp = {amplitude}mm"
    stem = Path(path).stem.lower()
    if "loose" in stem:
        label += ", unconstrained ends"
    elif "tight" in stem:
        label += ", constrained ends"
    if "post" in stem.split("_"):
        label += ", post"
    return label


def mean_profile(recording, x_max_m=X_MAX_M):
    """Average available samples at each gage, preserving all-missing gages."""
    keep = recording["position_m"] <= x_max_m
    if not np.any(keep):
        raise ValueError(f"No gages at or below {x_max_m:g} m")
    x = recording["position_m"][keep]
    shift = recording["spectral_shift_ghz"][:, keep]
    count = np.sum(~np.isnan(shift), axis=0)
    mean_shift = np.divide(
        np.nansum(shift, axis=0), count,
        out=np.full(x.shape, np.nan), where=count > 0,
    )
    return x, mean_shift


def plot_recording(recording, x_max_m=X_MAX_M):
    if re.search(r"k1_amp_?2_5(?:_|$)", recording["source_file"].stem):
        x_max_m = min(x_max_m, K1_2_5_X_MAX_M)
    x, mean_shift = mean_profile(recording, x_max_m)
    fig, ax = plt.subplots(figsize=(9, 4), constrained_layout=True)
    ax.plot(x, mean_shift, linewidth=1)
    ax.set_xlim(x[0], x_max_m)
    ax.set_xlabel("Fiber position (m)")
    ax.set_ylabel("Time-averaged spectral shift (GHz)")
    ax.grid(alpha=0.25)
    ax.set_title(recording_label(recording["source_file"]))
    return fig


def tensile_peak_profile(x, shift):
    """Clip the contiguous negative lobe containing the minimum and center it."""
    negative = np.isfinite(shift) & (shift < 0)
    if not np.any(negative):
        raise ValueError("No negative spectral-shift peak available for comparison")
    peak = int(np.argmin(np.where(negative, shift, np.inf)))
    start = peak
    stop = peak + 1
    while start > 0 and negative[start - 1]:
        start -= 1
    while stop < len(shift) and negative[stop]:
        stop += 1
    return x[start:stop] - x[peak], shift[start:stop], x[peak]


def fit_proportionality(x_small, small, x_large, large):
    """Fit large = offset + scale * small on the coarse recording grid.

    Positions are already peak-centered. Search a bounded residual alignment;
    retain a fixed comparison window throughout that search. Edge exclusions
    are fractions of the common lobe width, removed from each end.
    """
    pitch = float(np.median(np.diff(x_small)))
    alignment_bound = 2 * pitch
    left = max(x_small[0], x_large[0] + alignment_bound)
    right = min(x_small[-1], x_large[-1] - alignment_bound)
    width = right - left
    if width <= 0:
        raise ValueError("Insufficient common lobe for proportionality fit")
    results = []
    for fraction in (0.0, 0.05, 0.10, 0.15, 0.20):
        keep = (x_small >= left + fraction * width) & (x_small <= right - fraction * width)
        keep &= np.isfinite(small)
        x, reference = x_small[keep], small[keep]
        if len(x) < 5:
            print(f"Skipping {fraction:.0%} trim: only {len(x)} coarse-grid points")
            continue
        design = np.column_stack((np.ones(len(x)), reference))
        best = None
        for delta in np.linspace(-alignment_bound, alignment_bound, 801):
            observed = np.interp(x + delta, x_large, large)
            if not np.all(np.isfinite(observed)):
                continue
            offset, scale = np.linalg.lstsq(design, observed, rcond=None)[0]
            residual = observed - (offset + scale * reference)
            rms = float(np.sqrt(np.mean(residual**2)))
            if best is None or rms < best[0]:
                best = (rms, offset, scale, delta, observed, residual)
        if best is None:
            raise ValueError("No finite alignment available for fit")
        rms, offset, scale, delta, observed, residual = best
        signal_rms = np.sqrt(np.mean((observed - offset)**2))
        results.append(dict(edge_fraction=fraction, n_points=len(x), scale=scale,
                            scale_error_pct=100 * (scale / 2 - 1), offset_ghz=offset,
                            alignment_m=delta, residual_rms_ghz=rms,
                            residual_pct=100 * rms / signal_rms if signal_rms else np.nan,
                            alignment_at_bound=abs(delta) >= alignment_bound * 0.999))
    if not results:
        raise ValueError("Insufficient coarse-grid samples for any fit")
    return results


def plot_k1_comparison(recordings, x_max_m=X_MAX_M, output_dir=None):
    """Compare unconstrained k1 recordings, using small gages at 5 mm."""
    selected = {}
    for amplitude in (2.5, 5.0):
        candidates = [
            recording for recording in recordings
            if recording_label(recording["source_file"])
            == f"k = 1, amp = {amplitude}mm, unconstrained ends"
            and (amplitude != 5.0 or "small_gage" in recording["source_file"].stem.lower())
        ]
        if not candidates:
            qualifier = " small-gage" if amplitude == 5.0 else ""
            print(f"Skipping k1 comparison: missing unconstrained {amplitude:g} mm{qualifier} recording")
            return None
        selected[amplitude] = max(
            candidates,
            key=lambda recording: re.search(
                r"\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}",
                recording["source_file"].stem,
            ).group(0) if re.search(
                r"\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}",
                recording["source_file"].stem,
            ) else recording["source_file"].stem,
        )
    small_x_max_m = min(x_max_m, K1_2_5_X_MAX_M)
    x_small, small = mean_profile(selected[2.5], small_x_max_m)
    x_large, large = mean_profile(selected[5.0], x_max_m)
    x_small, small, small_peak_m = tensile_peak_profile(x_small, small)
    x_large, large, large_peak_m = tensile_peak_profile(x_large, large)
    results = fit_proportionality(x_small, small, x_large, large)
    print("Proportionality fits (edge exclusion from EACH end of common window):")
    for result in results:
        print(f"  trim={result['edge_fraction']:.0%}, n={result['n_points']}, "
              f"scale={result['scale']:.5f} ({result['scale_error_pct']:+.2f}% vs 2), "
              f"offset={result['offset_ghz']:.5f} GHz, "
              f"alignment={1000 * result['alignment_m']:.3f} mm, "
              f"residual={result['residual_pct']:.2f}%" +
              (" [alignment at search bound]" if result['alignment_at_bound'] else ""))
    if output_dir is not None:
        with (output_dir / "k1_proportionality.csv").open("w", newline="", encoding="utf-8") as file:
            writer = csv.DictWriter(file, fieldnames=list(results[0]))
            writer.writeheader()
            writer.writerows(results)
    diagnostic, diagnostic_axes = plt.subplots(2, 1, figsize=(10, 7), sharex=True, constrained_layout=True)
    diagnostic_axes[0].plot(x_small, 2 * small, label="2.5 mm × 2", color="tab:blue")
    chosen = min(results, key=lambda result: abs(result['edge_fraction'] - 0.10))
    aligned = np.interp(x_small + chosen['alignment_m'], x_large, large, left=np.nan, right=np.nan)
    fitted = chosen['offset_ghz'] + chosen['scale'] * small
    diagnostic_axes[0].plot(x_small, aligned, label="5 mm, aligned on coarse grid", color="tab:orange")
    diagnostic_axes[0].plot(x_small, fitted, label="Fitted scale + offset (10% trim)", linestyle="--")
    diagnostic_axes[0].set_ylabel("Spectral shift (GHz)")
    diagnostic_axes[0].legend()
    diagnostic_axes[1].plot(x_small, aligned - fitted)
    diagnostic_axes[1].axhline(0, color="0.5", linewidth=0.8)
    diagnostic_axes[1].set_ylabel("Residual (GHz)")
    diagnostic_axes[1].set_xlabel("Position relative to 2.5 mm tensile peak (m)")
    bound = 2 * float(np.median(np.diff(x_small)))
    left, right = max(x_small[0], x_large[0] + bound), min(x_small[-1], x_large[-1] - bound)
    for ax in diagnostic_axes:
        ax.axvspan(left + 0.1 * (right - left), right - 0.1 * (right - left), color="green", alpha=0.08)
        ax.grid(alpha=0.25)
    diagnostic.suptitle("k1 proportionality: shaded interior fitted; full-lobe residual shown")
    if output_dir is not None:
        diagnostic.savefig(output_dir / "k1_proportionality.png", dpi=150)
    fig, axes = plt.subplots(
        3, 1, figsize=(10, 9), sharex=True, sharey=True, constrained_layout=True
    )
    axes[0].plot(x_small, small, color="tab:blue", linewidth=1)
    axes[0].set_title("k = 1, amplitude = 2.5 mm")
    axes[1].plot(x_large, large, color="tab:orange", linewidth=1)
    axes[1].set_title("k = 1, amplitude = 5 mm")
    axes[2].plot(x_small, 2 * small, color="tab:blue", linewidth=1, label="2.5 mm × 2")
    axes[2].plot(x_large, large, color="tab:orange", linewidth=1, label="5 mm")
    axes[2].set_title("k = 1: tensile peaks aligned, amplitude scaling comparison")
    axes[2].legend()
    for ax in axes:
        ax.axvline(0, color="0.5", linestyle=":", linewidth=0.8)
        ax.set_xlabel("Fiber position relative to tensile peak (m)")
        ax.grid(alpha=0.25)
    axes[0].set_xlim(min(x_small[0], x_large[0]), max(x_small[-1], x_large[-1]))
    fig.supylabel("Time-averaged spectral shift (GHz)")
    fig.suptitle("k = 1, unconstrained ends — negative spectral-shift lobes")
    print(f"Aligned tensile peaks: 2.5 mm at {small_peak_m:.6f} m; 5 mm at {large_peak_m:.6f} m")
    for amplitude, recording in selected.items():
        print(f"k1 comparison ({amplitude:g} mm): {recording['source_file'].name}")
    return fig


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_dir", nargs="?", type=Path, default=DATA_DIR)
    parser.add_argument("--pattern", default="*_full.tsv", help="Input glob for full-profile exports (default: *_full.tsv)")
    parser.add_argument("--output-dir", type=Path, help="Save PNGs only when explicitly supplied")
    parser.add_argument("--x-max", type=float, default=X_MAX_M, help=f"Maximum plotted fiber position in m (default: {X_MAX_M:g})")
    parser.add_argument("--no-show", action="store_true", help="Run without interactive figures")
    args = parser.parse_args()
    if args.no_show:
        plt.switch_backend("Agg")
    files = sorted(args.data_dir.glob(args.pattern))
    if not files:
        parser.error(f"No files matching {args.pattern!r} in {args.data_dir}")
    if args.output_dir is not None:
        args.output_dir.mkdir(parents=True, exist_ok=True)
    recordings = []
    for path in files:
        recording = read_full_tsv(path)
        recordings.append(recording)
        fig = plot_recording(recording, x_max_m=args.x_max)
        if args.output_dir is not None:
            fig.savefig(args.output_dir / f"{path.stem}.png", dpi=150)
        print(f"{path.name}: {recording['spectral_shift_ghz'].shape} samples x positions", flush=True)
        if args.no_show:
            plt.close(fig)
    comparison = plot_k1_comparison(recordings, x_max_m=args.x_max, output_dir=args.output_dir)
    if comparison is not None:
        if args.output_dir is not None:
            comparison.savefig(args.output_dir / "k1_amplitude_comparison.png", dpi=150)
        if args.no_show:
            plt.close(comparison)
    if not args.no_show:
        plt.show()
    else:
        plt.close("all")


if __name__ == "__main__":
    main()
