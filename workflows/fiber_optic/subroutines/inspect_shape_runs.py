"""Collect runs for interactive inspection: uv run python -i <this file>."""
from pathlib import Path

import numpy as np
import matplotlib.pyplot as plt

if __package__:
    from .compute_1D_shape import compute_1D_shape
else:
    from compute_1D_shape import compute_1D_shape

DATA_DIR = Path("C:/Users/coled/Notre Dame/FTSI F26/lunaData/1D_1Mode_test1")
BASELINE_FILE = DATA_DIR / "Baseline_NoLoad_2026-09-17_19-43-57_ch1_gages.tsv"
# Nominal filename amplitudes; update to measured values if available.
RUN_GROUPS = [("1mm_NoLoad3", 1.0), ("2.5mm_NoLoad3", 2.50), ("5.0mm_NoLoad3", 5.0)]


def collect_runs(data_dir=DATA_DIR, baseline_file=BASELINE_FILE):
    """Collect the third test (NoLoad3) for each amplitude."""
    results = []
    for prefix, amplitude in RUN_GROUPS:
        files = sorted(Path(data_dir).glob(f"{prefix}_*_ch1_gages.tsv"))
        if not files:
            raise FileNotFoundError(f"No runs found for {prefix} in {data_dir}")
        if len(files) != 1:
            raise ValueError(f"Expected one third-test recording for {prefix}; found {len(files)}")
        for source_file in files:
            results.append(compute_1D_shape(
                source_file, baseline_file, imposed_amplitude_mm=amplitude,
            ))
    return results


def collect_repeats(data_dir=DATA_DIR, baseline_file=BASELINE_FILE):
    """Collect recordings 1, 2, and 3 for each case using a common baseline."""
    repeat_results = {}
    for prefix, amplitude in RUN_GROUPS:
        base_prefix = prefix.split("_NoLoad")[0] + "_NoLoad"
        case_results = []
        for suffix in ("", "2", "3"):
            files = sorted(Path(data_dir).glob(f"{base_prefix}{suffix}_*_ch1_gages.tsv"))
            if len(files) != 1:
                raise ValueError(f"Expected one recording for {base_prefix}{suffix}; found {len(files)}")
            case_results.append(compute_1D_shape(
                files[0], baseline_file, imposed_amplitude_mm=amplitude,
            ))
        repeat_results[base_prefix] = case_results
    return repeat_results


def plot_repeats(repeat_results):
    """Overlay baseline-relative mean strain for the three recordings per case."""
    fig, axes = plt.subplots(
        len(repeat_results), 1, figsize=(10, 9), sharex=True,
        squeeze=False, constrained_layout=True,
    )
    for ax, case_results in zip(axes[:, 0], repeat_results.values()):
        for number, result in enumerate(case_results, start=1):
            ax.plot(
                result["x_strain_mm"], result["mean_strain"] * 1e6,
                marker=".", markersize=4, label=f"Recording {number}",
            )
        ax.set_title(f"{case_results[0]['imposed_amplitude_mm']:g} mm case")
        ax.set_ylabel("Mean strain (µε)")
        ax.grid(True, alpha=0.3)
        ax.legend()
    axes[-1, 0].set_xlabel("Position from ROI start (mm)")
    fig.suptitle("First, second, and third recordings — common baseline")
    return fig, axes[:, 0]


def inspect_runs(results):
    """Print fit and missing-data summaries without opening figures."""
    for result in results:
        strain = result["strain_measured"]
        print(result["source_file"].name)
        print(f"  Imposed amplitude: {result['imposed_amplitude_mm']:g} mm")
        print(f"  Fitted amplitudes (mm): {result['modal_amplitudes']}")
        print(f"  Samples / ROI gages: {strain.shape}")
        print(f"  ROI NaNs: {np.isnan(strain).sum()}; "
              f"all-missing gages: {np.isnan(strain).all(axis=0).sum()}")
        print(f"  Fit rank: {result['rank']}; residuals: {result['residuals']}")


def plot_case(result):
    """Plot one case in physical units using the original two-subplot layout."""
    fig, (ax_shape, ax_strain) = plt.subplots(
        2, 1, figsize=(9, 7), sharex=True, constrained_layout=True,
    )
    amplitude = result["imposed_amplitude_mm"]
    fig.suptitle(f"{amplitude:g} mm case")
    ax_shape.plot(
        result["x_shape_mm"], result["displacement_mm"],
        color="tab:blue", linewidth=2, label="reconstructed shape",
    )
    ax_shape.plot(
        result["x_shape_mm"], amplitude * result["Phi"][:, 0],
        color="tab:gray", linewidth=2, label="imposed shape",
    )
    ax_shape.axhline(0, color="gray", linewidth=0.8)
    ax_shape.set_ylabel("Displacement (mm)")
    ax_shape.set_title("Shape reconstructed vs shape imposed")
    ax_strain.plot(
        result["x_strain_mm"], result["mean_strain"] * 1e6,
        ".", markersize=4, color="tab:gray", label="Measured time average",
    )
    ax_strain.plot(
        result["x_strain_mm"], result["fitted_strain"] * 1e6,
        color="tab:orange", linewidth=2, label="Modal fit",
    )
    # The imposed shape is the first sine mode; Psi maps its amplitude to strain.
    ideal_bending_strain = amplitude * result["Psi"][:, 0]
    ax_strain.plot(
        result["x_strain_mm"], ideal_bending_strain * 1e6,
        color="tab:blue", linestyle="--", linewidth=2,
        label="Ideal imposed bending strain",
    )
    ax_strain.set_xlabel("Position from ROI start (mm)")
    ax_strain.set_ylabel("Strain (µε)")
    for ax in (ax_shape, ax_strain):
        ax.legend()
        ax.grid(True, alpha=0.3)
    return fig, (ax_shape, ax_strain)


def plot_raw_shift(results):
    """Plot exported optical shift, before our baseline correction, over each ROI."""
    fig, axes = plt.subplots(
        len(results), 1, figsize=(10, 3 * len(results)),
        squeeze=False, constrained_layout=True,
    )
    for ax, result in zip(axes[:, 0], results):
        recording = result["recording"]
        roi_mask = result["roi_mask"]
        mean_shift = np.nanmean(
            recording["spectral_shift_ghz"][:, roi_mask], axis=0,
        )
        ax.plot(
            recording["position_m"][roi_mask], mean_shift,
            ".-", markersize=4, label="Exported shift: time average",
        )
        ax.set_title(result["source_file"].name)
        ax.set_xlabel("Distance along fiber (m)")
        ax.set_ylabel("Optical shift (GHz)")
        ax.grid(True, alpha=0.3)
        ax.legend()
    fig.suptitle("Raw exported optical shift over the ROI")
    return fig, axes[:, 0]


def plot_normalized(results):
    """Compare displacement and measured strain per imposed amplitude.

    Single-mode reconstructed shapes share their shape by construction;
    measured strain provides an independent view of spatial agreement.
    """
    for result in results:
        amplitude = result["imposed_amplitude_mm"]
        if not np.isfinite(amplitude) or amplitude == 0:
            raise ValueError("Normalization requires a finite, nonzero imposed amplitude.")

    fig, (ax_shape, ax_strain) = plt.subplots(
        2, 1, figsize=(10, 8), sharex=True, constrained_layout=True,
    )
    colors = {}
    repeats = {}
    styles = ("-", "--", ":", "-.")
    for result in results:
        amplitude = result["imposed_amplitude_mm"]
        if amplitude not in colors:
            colors[amplitude] = f"C{len(colors) % 10}"
        repeat = repeats.get(amplitude, 0)
        repeats[amplitude] = repeat + 1
        style = styles[repeat % len(styles)]
        label = f"{amplitude:g} mm — {result['source_file'].name.split('_2026')[0]}"
        ax_shape.plot(
            result["x_shape_mm"], result["displacement_mm"] / amplitude,
            color=colors[amplitude], linestyle=style, linewidth=2, label=label,
        )
        ax_strain.plot(
            result["x_strain_mm"], result["mean_strain"] * 1e6 / amplitude,
            color=colors[amplitude], linestyle=style, marker=".", markersize=4,
        )

    ax_shape.set_title("Response normalized by imposed amplitude")
    ax_shape.set_ylabel("Displacement / imposed amplitude")
    ax_shape.legend(fontsize="small", ncol=2)
    ax_strain.set_ylabel("Mean measured strain / amplitude (µε/mm)")
    ax_strain.set_xlabel("Position from ROI start (mm)")
    for ax in (ax_shape, ax_strain):
        ax.axhline(0, color="gray", linewidth=0.8)
        ax.grid(True, alpha=0.3)
    return fig, (ax_shape, ax_strain)


if __name__ == "__main__":
    results = collect_runs()
    results_by_name = {r["source_file"].stem: r for r in results}
    inspect_runs(results)
    fig, axes = plot_normalized(results)
    case_plots = [plot_case(result) for result in results]
    raw_fig, raw_axes = plot_raw_shift(results)
    repeat_results = collect_repeats()
    repeat_fig, repeat_axes = plot_repeats(repeat_results)

    # Save all figures beside the source data before opening the plot windows.
    output_dir = results[0]["source_file"].parent / "outputs"
    output_dir.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_dir / "normalized_comparison.png", dpi=300, bbox_inches="tight")
    raw_fig.savefig(output_dir / "raw_optical_shift.png", dpi=300, bbox_inches="tight")
    repeat_fig.savefig(output_dir / "recording_comparison.png", dpi=300, bbox_inches="tight")
    for result, (case_fig, _) in zip(results, case_plots):
        case_fig.savefig(
            output_dir / f"{result['source_file'].stem}_shape_strain.png",
            dpi=300, bbox_inches="tight",
        )
    print(f"Saved {3 + len(case_plots)} PNG figures to {output_dir}")
    plt.show()
