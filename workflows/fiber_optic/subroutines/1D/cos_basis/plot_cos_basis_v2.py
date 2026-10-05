"""Display time-averaged COS basis V2 spectral shifts and select pass ROIs."""

import sys
from pathlib import Path

# Shared readers remain in the parent subroutines directory.
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import argparse
import json
from pathlib import Path
import re

import matplotlib.pyplot as plt
from cos_plot_labels import format_figure
from matplotlib.widgets import SpanSelector
import numpy as np

from load_fos_case import read_fos_tsv


DATA_DIR = Path(r"C:\Users\coled\Notre Dame\FTSI F26\lunaData\1D COS BASIS V2")
CONDITIONS = ("unconstrained", "constrained")
ROI_FILE = Path(__file__).with_name("cos_basis_v2_rois.json")


def load_spectra(data_dir=DATA_DIR):
    """Return spectra[condition][case_id], preserving reader data and metadata."""
    spectra = {condition: {} for condition in CONDITIONS}
    files = sorted(Path(data_dir).glob("*_gages.tsv"))
    if not files:
        raise FileNotFoundError(f"No *_gages.tsv files in {data_dir}")

    for path in files:
        match = re.fullmatch(
            r"(.+)_(unconstrained|constrained)_gage_[^_]+_gages", path.stem
        )
        if match is None:
            raise ValueError(f"Cannot identify case and condition: {path.name}")
        case_id, condition = match.groups()
        if case_id in spectra[condition]:
            raise ValueError(f"Duplicate recording for {case_id}, {condition}")
        spectra[condition][case_id] = read_fos_tsv(path)

    return spectra


def mean_profile(recording):
    """Average available time samples at every fiber position."""
    positions = recording["position_m"]
    shifts = recording["spectral_shift_ghz"]
    count = np.sum(~np.isnan(shifts), axis=0)
    mean = np.divide(
        np.nansum(shifts, axis=0), count,
        out=np.full(positions.shape, np.nan), where=count > 0,
    )
    return positions, mean


def select_rois(ax, recording):
    """Drag passes in order; right-click undoes the last selection."""
    rois = recording.setdefault("rois", [])
    artists = []

    def select(start, end):
        positions = recording["position_m"]
        start, end = sorted((start, end))
        indices = np.flatnonzero((positions >= start) & (positions <= end))
        if len(indices) < 2:
            return
        start, end = positions[indices[[0, -1]]]
        pass_id = len(rois) + 1
        rois.append({
            "pass_id": pass_id,
            "surface": "top" if pass_id == 1 else None,
            "expected_loading": "compression" if pass_id == 1 else None,
            "bounds_m": [float(start), float(end)],
            "direction": None,
        })
        shade = ax.axvspan(start, end, color="tab:orange", alpha=0.2)
        label = ax.text((start + end) / 2, 0.95, f"Pass {pass_id}",
                        transform=ax.get_xaxis_transform(), ha="center", va="top")
        artists.append((shade, label))
        print(f"{recording['source_file'].name}: {rois[-1]}")
        ax.figure.canvas.draw_idle()

    def undo(event):
        if event.inaxes == ax and event.button == 3 and artists:
            rois.pop()
            for artist in artists.pop():
                artist.remove()
            ax.figure.canvas.draw_idle()

    selector = SpanSelector(ax, select, "horizontal", button=1,
                            props={"facecolor": "tab:orange", "alpha": 0.2})
    ax.figure.canvas.mpl_connect("button_press_event", undo)
    # Matplotlib selectors need a live reference throughout the interaction.
    ax._roi_selector = selector
    return selector


def plot_spectra(spectra):
    """Create one comparison figure per case using full time averages."""
    case_ids = sorted({case for recordings in spectra.values() for case in recordings})
    for case_id in case_ids:
        fig, axes = plt.subplots(
            1, 2, figsize=(12, 4), sharex=True, sharey=True,
            constrained_layout=True,
        )
        fig.suptitle(case_id)
        for ax, condition in zip(axes, CONDITIONS):
            recording = spectra[condition].get(case_id)
            ax.set_title(condition)
            ax.set_xlabel("Fiber position (m)")
            ax.grid(alpha=0.25)
            if recording is None:
                ax.text(0.5, 0.5, "No recording", transform=ax.transAxes, ha="center")
                continue
            shifts = recording["spectral_shift_ghz"]
            positions, mean_shift = mean_profile(recording)
            ax.plot(
                positions, mean_shift, color="tab:blue", linewidth=1,
            )
            ax.set_title(f"{condition} ({shifts.shape[0]} samples)")
            select_rois(ax, recording)
        axes[0].set_ylabel("Time-averaged spectral shift (GHz)")
        fig.supxlabel("Drag to select passes in order; right-click to undo (disable pan/zoom)")


def label_rois(spectra):
    """Label selections in the terminal after closing the selection figures."""
    for condition, cases in spectra.items():
        for case_id, recording in cases.items():
            for roi in recording.get("rois", []):
                print(f"\n{case_id}, {condition}, pass {roi['pass_id']}: {roi['bounds_m']} m")
                default = roi.get("surface") or "bottom"
                while True:
                    surface = input(f"Surface top/bottom [{default}]: ").strip().lower() or default
                    if surface in {"top", "bottom"}:
                        break
                while True:
                    direction = input("Direction forward/reverse [forward]: ").strip().lower() or "forward"
                    if direction in {"forward", "reverse"}:
                        break
                roi.update(surface=surface, direction=1 if direction == "forward" else -1)


def save_rois(spectra, path):
    selections = {
        condition: {
            case_id: {"source_file": str(recording["source_file"]),
                      "rois": recording.get("rois", [])}
            for case_id, recording in cases.items()
        }
        for condition, cases in spectra.items()
    }
    Path(path).write_text(json.dumps(selections, indent=2), encoding="utf-8")


def load_rois(spectra, path):
    selections = json.loads(Path(path).read_text(encoding="utf-8"))
    for condition, cases in spectra.items():
        for case_id, recording in cases.items():
            saved = selections.get(condition, {}).get(case_id)
            if saved and Path(saved["source_file"]) == recording["source_file"]:
                recording["rois"] = saved["rois"]


def plot_rois(spectra):
    """Compare selected passes using distance in the specimen travel direction."""
    case_ids = sorted({case for cases in spectra.values() for case in cases})
    for case_id in case_ids:
        recordings = [spectra[c].get(case_id) for c in CONDITIONS]
        pass_ids = sorted({roi["pass_id"] for r in recordings if r
                           for roi in r.get("rois", [])})
        if not pass_ids:
            continue
        fig, axes = plt.subplots(len(pass_ids), 2, squeeze=False,
                                 figsize=(12, 3 * len(pass_ids)), constrained_layout=True)
        fig.suptitle(case_id)
        for row, pass_id in enumerate(pass_ids):
            for col, (condition, recording) in enumerate(zip(CONDITIONS, recordings)):
                ax = axes[row, col]
                roi = next((r for r in recording.get("rois", [])
                            if r["pass_id"] == pass_id), None) if recording else None
                if roi is None:
                    ax.set_title(f"{condition}: pass {pass_id} missing")
                    continue
                x, y = mean_profile(recording)
                start, end = roi["bounds_m"]
                keep = (x >= start) & (x <= end)
                x, y = x[keep], y[keep]
                if not x.size:
                    continue
                if roi["direction"] == -1:
                    x, y = x[-1] - x[::-1], y[::-1]
                else:
                    x = x - x[0]
                ax.plot(x, y)
                ax.set_title(f"{condition}: pass {pass_id} — {roi['surface']}")
                ax.set_xlabel("Distance along pass (m)")
                ax.set_ylabel("Mean spectral shift (GHz)")
                ax.grid(alpha=0.25)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_dir", nargs="?", type=Path, default=DATA_DIR)
    parser.add_argument("--roi-file", type=Path, default=ROI_FILE)
    parser.add_argument("--reselect", action="store_true", help="Replace saved selections")
    args = parser.parse_args()
    spectra = load_spectra(args.data_dir)
    if args.roi_file.exists() and not args.reselect:
        load_rois(spectra, args.roi_file)
    else:
        print("Drag to select passes, then close all selection figures to label and save.")
        plot_spectra(spectra)
        for number in plt.get_fignums():
            format_figure(plt.figure(number))
        plt.show()
        label_rois(spectra)
        save_rois(spectra, args.roi_file)
        print(f"Saved selections to {args.roi_file}")
    plot_rois(spectra)
    for number in plt.get_fignums():
        format_figure(plt.figure(number))
    plt.show()
    return spectra


if __name__ == "__main__":
    spectra = main()
