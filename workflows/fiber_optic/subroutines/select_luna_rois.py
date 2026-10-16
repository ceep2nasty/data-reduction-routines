"""Load a Luna recording, select spatial passes, and save the recording as JSON.

Call select_luna_rois() from your experiment script. Drag each pass in order;
right-click to undo. Save requires exactly PASS_COUNT windows. Closing the
figure without clicking Save does not write anything. INPUT_FILE can also be
a previously saved JSON. Save retains all time samples only at selected
positions, then closes the selector and plots the saved ROI profiles.
JSON has six fields; position_m and spectral_shift_ghz are grouped by pass.
"""

import csv
import json
from datetime import datetime
from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.widgets import Button, Slider, SpanSelector
import numpy as np

from load_fos_case import read_fos_tsv


def load_recording(path):
    """Read named-gage/full-profile TSV, or reload this script's JSON output."""
    path = Path(path).expanduser().resolve()
    if path.suffix.lower() == ".json":
        data = json.loads(path.read_text(encoding="utf-8"))
        if "recording" not in data:
            # Rebuild an in-memory recording from the saved, cropped passes.
            names = list(data["position_m"])
            positions = np.concatenate([data["position_m"][name] for name in names])
            shifts = np.concatenate([np.asarray(data["spectral_shift_ghz"][name], dtype=float)
                                     for name in names], axis=1)
            positions, indices = np.unique(positions, return_index=True)
            return dict(recording=dict(position_m=positions, spectral_shift_ghz=shifts[:, indices],
                                       time_s=np.asarray(data["time_s"], dtype=float)),
                        metadata={key: data[key] for key in ("test_name", "gage_pitch_mm", "sampling_rate_hz")},
                        rois=[dict(pass_id=i + 1, bounds_m=[data["position_m"][name][0],
                                                           data["position_m"][name][-1]])
                              for i, name in enumerate(names)], selection_sample_index=0)
        recording = data["recording"]
        for key in ("position_m", "time_s", "spectral_shift_ghz"):
            recording[key] = np.asarray(recording[key], dtype=float)
        return data

    with path.open(encoding="utf-8-sig", newline="") as file:
        rows = list(csv.reader(file, delimiter="\t"))
    if any(row and row[0].strip() == "Gage/Segment Name" for row in rows):
        recording = read_fos_tsv(path)
    else:
        metadata = {}
        positions = None
        shifts, timestamps = [], []
        for row in rows:
            if not row:
                continue
            key, separator, value = row[0].partition(":")
            if separator and (row[0].strip().endswith(":") or len(row) == 1):
                metadata[key.strip()] = "\t".join(row[1:]).strip() if len(row) > 1 else value.strip()
            if row[0].strip() == "x-axis":
                positions = np.asarray(row[3:], dtype=float)
            elif len(row) >= 3 and row[1].strip() == "measurement":
                if row[2].strip() != "xcorr shift":
                    raise ValueError("Expected xcorr shift measurements")
                timestamps.append(datetime.fromisoformat(row[0].strip()))
                shifts.append([float(v) if v.strip() else np.nan for v in row[3:]])
        if metadata.get("Units") != "spectral shift (GHz)" or metadata.get("X-Axis Units") != "m":
            raise ValueError("Expected spectral shift (GHz) and positions in m")
        if positions is None or not shifts:
            raise ValueError("Missing positions or measurements")
        recording = dict(source_file=path, metadata=metadata, position_m=positions,
                         timestamps=timestamps,
                         time_s=np.asarray([(t - timestamps[0]).total_seconds() for t in timestamps]),
                         spectral_shift_ghz=np.asarray(shifts, dtype=float))
    return dict(recording=recording, metadata={}, rois=[], selection_sample_index=0)


def json_ready(value):
    """Convert reader values to strict JSON, with missing measurements as null."""
    if isinstance(value, dict):
        return {key: json_ready(item) for key, item in value.items()}
    if isinstance(value, (list, tuple, np.ndarray)):
        return [json_ready(item) for item in value]
    if isinstance(value, (Path, datetime)):
        return str(value) if isinstance(value, Path) else value.isoformat()
    if isinstance(value, np.generic):
        return json_ready(value.item())
    if isinstance(value, float) and not np.isfinite(value):
        return None
    return value


def save_recording(data, output_path, *, roi_only=True):
    """Write cropped passes by default and return exactly the saved payload."""
    output_path = Path(output_path).expanduser()
    payload = json_ready(compact_recording(data) if roi_only else data)
    contents = json.dumps(payload, indent=2, allow_nan=False)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(contents, encoding="utf-8")
    return payload


def compact_recording(data):
    """Export six fields, with only selected positions, grouped by pass.

    Each spectral_shift_ghz[pass] is a time-by-position matrix corresponding
    exactly to position_m[pass]. No mask or unselected positions are saved.
    """
    recording = data["recording"]
    metadata = dict(data.get("metadata", {}))
    header = recording.get("metadata", {})
    rate_text = header.get("Measurement Rate per Channel", metadata.get("sampling_rate_hz", ""))
    try:
        rate = float(str(rate_text).split()[0])
    except (ValueError, IndexError):
        rate = np.nan
    if not (np.isfinite(rate) and rate > 0):
        intervals = np.diff(np.asarray(recording["time_s"], dtype=float))
        if len(intervals) and np.all(np.isfinite(intervals)) and np.all(intervals > 0):
            rate = float(1 / np.median(intervals))
        else:
            rate = None
    x = np.asarray(recording["position_m"], dtype=float)
    shifts = np.asarray(recording["spectral_shift_ghz"], dtype=float)
    positions, spectra = {}, {}
    if not data["rois"]:
        raise ValueError("Select at least one ROI before saving")
    for i, roi in enumerate(data["rois"], start=1):
        left, right = roi["bounds_m"]
        mask = (x >= left) & (x <= right)
        if np.count_nonzero(mask) < 2:
            raise ValueError(f"Pass {i} contains fewer than two positions")
        positions[f"pass_{i}"] = x[mask]
        spectra[f"pass_{i}"] = shifts[:, mask]
    pitch = metadata.get("gage_pitch", metadata.get("gage_pitch_mm", header.get("Gage Pitch (mm)")))
    return dict(gage_pitch_mm=float(pitch) if pitch is not None else float(np.median(np.diff(x)) * 1000),
                test_name=metadata.get("test_name", header.get("Test Name", Path(recording.get("source_file", "recording")).stem)),
                sampling_rate_hz=rate, position_m=positions, time_s=recording["time_s"],
                spectral_shift_ghz=spectra)


def plot_saved_rois(saved, samples):
    """Plot each saved pass at the sample used to select it."""
    fig, axes = plt.subplots(len(saved["position_m"]), 1, squeeze=False,
                             figsize=(9, 3 * len(saved["position_m"])), constrained_layout=True)
    for ax, (name, positions), sample in zip(axes[:, 0], saved["position_m"].items(), samples):
        ax.plot(positions, np.asarray(saved["spectral_shift_ghz"][name], dtype=float)[sample])
        ax.set(xlabel="Fiber position (m)", ylabel="Spectral shift (GHz)",
               title=f"{name}: {positions[0]:g} to {positions[-1]:g} m | sample {sample} | {saved['time_s'][sample]:g} s")
        ax.grid(alpha=0.25)
    fig.suptitle(saved["test_name"])
    return fig


def select_luna_rois(input_file, output_path, pass_count, metadata=None, *, on_saved=None):
    """Return the editable data and figure; call plt.show() to interact.

    ROI bounds are inclusive fiber positions in meters. Each ROI records the
    sample used to select it in memory. Saving crops positions to each ROI.
    An existing output file is replaced when the Save button is clicked.
    Optional on_saved(saved_data) runs after a successful save, allowing the
    calling script to run the next processing step. Closing without Save
    does not invoke it.
    """
    if not isinstance(pass_count, int) or pass_count < 1:
        raise ValueError("pass_count must be a positive integer")
    data = load_recording(input_file)
    if metadata is not None:
        data["metadata"].update(metadata)
    recording = data["recording"]
    x, times, shifts = (recording[k] for k in ("position_m", "time_s", "spectral_shift_ghz"))
    if x.ndim != 1 or len(x) < 2 or not np.all(np.isfinite(x)) or np.any(np.diff(x) <= 0):
        raise ValueError("Expected at least two finite, increasing positions")
    if times.ndim != 1 or not len(times) or not np.all(np.isfinite(times)) or np.any(np.diff(times) <= 0):
        raise ValueError("Expected finite, increasing sample times")
    if shifts.shape != (len(times), len(x)) or np.any(np.isinf(shifts)):
        raise ValueError("Invalid measurement array")
    rois = data["rois"]
    sample = int(data["selection_sample_index"])
    if not 0 <= sample < len(times):
        raise ValueError("Saved selection sample is out of range")
    fig, ax = plt.subplots(figsize=(10, 5))
    fig.subplots_adjust(bottom=0.28)
    line, = ax.plot(x, shifts[sample], linewidth=1)
    ax.set(xlabel="Fiber position (m)", ylabel="Spectral shift (GHz)", xlim=(x[0], x[-1]))
    ax.grid(alpha=0.25)
    status = fig.text(0.1, 0.03, "")
    artists = []

    def redraw():
        for artist in artists:
            artist.remove()
        artists.clear()
        for roi in rois:
            left, right = roi["bounds_m"]
            artists.append(ax.axvspan(left, right, color="tab:orange", alpha=0.2))
            artists.append(ax.text((left + right) / 2, 0.95, str(roi["pass_id"]),
                                   transform=ax.get_xaxis_transform(), ha="center"))
        ax.set_title(f"Sample {sample} | {times[sample]:g} s | {len(rois)}/{pass_count} passes")
        status.set_text("Drag passes in order; right-click to undo. Save when finished.")
        fig.canvas.draw_idle()

    def change_sample(value):
        nonlocal sample
        sample = int(value)
        data["selection_sample_index"] = sample
        line.set_ydata(shifts[sample])
        ax.relim()
        ax.autoscale_view(scalex=False)
        redraw()

    def select(left, right):
        if len(rois) >= pass_count or ax.get_navigate_mode() is not None:
            return
        left, right = sorted((left, right))
        indices = np.flatnonzero((x >= left) & (x <= right))
        if len(indices) < 2:
            return
        rois.append(dict(pass_id=len(rois) + 1, bounds_m=x[indices[[0, -1]]].tolist(),
                         selection_sample_index=sample))
        redraw()

    def undo(event):
        if event.inaxes == ax and event.button == 3 and rois and ax.get_navigate_mode() is None:
            rois.pop()
            redraw()

    def save(event):
        if len(rois) != pass_count:
            status.set_text(f"Select exactly {pass_count} passes before saving.")
        else:
            try:
                saved = save_recording(data, output_path)
                print(f"Saved: {Path(output_path).expanduser()}")
            except (OSError, ValueError) as exc:
                status.set_text(f"Save failed: {exc}")
            else:
                plot_saved_rois(saved, [roi.get("selection_sample_index", sample) for roi in rois])
                plt.close(fig)
                if on_saved is not None:
                    on_saved(saved)
                plt.show(block=False)
                return
        fig.canvas.draw_idle()

    selector = SpanSelector(ax, select, "horizontal", button=1,
                            props=dict(facecolor="tab:orange", alpha=0.2))
    slider = None
    if len(times) > 1:
        slider = Slider(fig.add_axes([0.15, 0.15, 0.65, 0.04]), "Sample", 0,
                        len(times) - 1, valinit=sample, valstep=1, valfmt="%d")
        slider.on_changed(change_sample)
    button = Button(fig.add_axes([0.82, 0.08, 0.1, 0.06]), "Save")
    button.on_clicked(save)
    fig.canvas.mpl_connect("button_press_event", undo)
    fig._roi_controls = (selector, slider, button)  # Keep widgets alive.
    redraw()
    return data, fig
