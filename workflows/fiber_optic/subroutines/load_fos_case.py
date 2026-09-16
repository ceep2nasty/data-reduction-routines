## Load fiber optic experiment in

from pathlib import Path
from datetime import datetime, timezone
import csv
import matplotlib.pyplot as plt

import numpy as np

def numeric_values(row, columns, *, context):
    """Read selected numeric cells, preserving missing values as NaN"""
    values = []

    for column in columns:
        text = row[column].strip()

        if text.lower() in {"", "nan"}:
            values.append(np.nan)
        else:
            try:
                values.append(float(text))
            except ValueError as exc:
                raise ValueError(
                    f"{context}: invalid number {text!r} "
                    f"in column {column + 1}"
                ) from exc
    return np.asarray(values, dtype=float)

def read_fos_tsv(path):
    """Load one Luna TSV export, preserving the raw measurements."""

    path = Path(path).expanduser().resolve()

    if not path.is_file():
        raise FileNotFoundError(f"Measurement file does not exist: {path}")

    with path.open("r", encoding="utf-8-sig", newline="") as file:
        rows = list(csv.reader(file, delimiter="\t"))

    def find_row(label):
        matches = [
            index
            for index, row in enumerate(rows)
            if row and row[0].strip() == label
        ]

        if len(matches) != 1:
            raise ValueError(
                f"{path.name}: expected one {label!r} row; "
                f"found {len(matches)}"
            )

        return matches[0]

    names_index = find_row("Gage/Segment Name")
    position_index = find_row("x-axis")
    tare_index = find_row("Tare")

    # Most metadata lines are "Key:\tValue".
    # A few place both the key and value in the first cell.
    metadata = {}

    for row in rows[:names_index]:
        if not row:
            continue

        key, separator, inline_value = row[0].partition(":")

        if separator:
            value = "\t".join(row[1:]).strip() if len(row) > 1 else inline_value.strip()
            metadata[key.strip()] = value

    names = [name.strip() for name in rows[names_index]]
    expected_width = len(names)

    gage_columns = [
        index
        for index, name in enumerate(names)
        if name.startswith("All Gages[")
    ]

    marker_columns = [
        index
        for index, name in enumerate(names)
        if index >= 3 and name and index not in gage_columns
    ]

    if not gage_columns:
        raise ValueError(f"{path.name}: no All Gages columns found")

    def check_width(row_index):
        actual_width = len(rows[row_index])

        if actual_width != expected_width:
            raise ValueError(
                f"{path.name}, line {row_index + 1}: "
                f"expected {expected_width} columns, found {actual_width}"
            )

    check_width(position_index)
    check_width(tare_index)

    measurement_indices = [
        index
        for index, row in enumerate(rows)
        if len(row) >= 3 and row[1].strip() == "measurement"
    ]

    if not measurement_indices:
        raise ValueError(f"{path.name}: no measurement rows found")

    for index in measurement_indices:
        check_width(index)

        if rows[index][2].strip() != "xcorr shift":
            raise ValueError(
                f"{path.name}, line {index + 1}: "
                f"unexpected measurement type {rows[index][2]!r}"
            )

    # These example files explicitly declare UTC+0.
    # Reject other declarations until their interpretation is implemented.
    if metadata.get("Timezone") != "UTC+0":
        raise ValueError(
            f"{path.name}: unsupported timezone {metadata.get('Timezone')!r}"
        )

    timestamps = [
        datetime.fromisoformat(rows[index][0].strip()).replace(
            tzinfo=timezone.utc
        )
        for index in measurement_indices
    ]

    time_s = np.asarray([
        (timestamp - timestamps[0]).total_seconds()
        for timestamp in timestamps
    ])

    position_m = numeric_values(
        rows[position_index], gage_columns, context=f"{path.name}: positions"
    )

    spectral_shift_ghz = np.vstack([
        numeric_values(
            rows[index],
            gage_columns,
            context=f"{path.name}, line {index + 1}",
        )
        for index in measurement_indices
    ])

    tare_shift_ghz = numeric_values(
        rows[tare_index], gage_columns, context=f"{path.name}: tare"
    )

    # Marker columns are kept separately from the full fiber profile.
    marker_positions = numeric_values(
        rows[position_index], marker_columns, context=f"{path.name}: markers"
    )

    marker_shifts = np.asarray([
        numeric_values(
            rows[index], marker_columns, context=f"{path.name}: marker shifts"
        )
        for index in measurement_indices
    ])

    marker_tare = numeric_values(
        rows[tare_index], marker_columns, context=f"{path.name}: marker tare"
    )

    markers = {
        names[column]: {
            "position_m": marker_positions[j],
            "spectral_shift_ghz": marker_shifts[:, j],
            "tare_shift_ghz": marker_tare[j],
        }
        for j, column in enumerate(marker_columns)
    }

    if metadata.get("Units") != "spectral shift (GHz)":
        raise ValueError(f"{path.name}: unexpected measurement units")

    if metadata.get("X-Axis Units") != "m":
        raise ValueError(f"{path.name}: unexpected position units")

    if not np.all(np.isfinite(position_m)):
        raise ValueError(f"{path.name}: positions contain missing values")

    if np.any(np.diff(position_m) <= 0):
        raise ValueError(f"{path.name}: positions must strictly increase")

    if np.any(np.diff(time_s) <= 0):
        raise ValueError(f"{path.name}: timestamps must strictly increase")

    if np.any(np.isinf(spectral_shift_ghz)):
        raise ValueError(f"{path.name}: measurements contain infinite values")

    return {
        "source_file": path,
        "metadata": metadata,
        "gage_names": [names[index] for index in gage_columns],
        "position_m": position_m,
        "timestamps": timestamps,
        "time_s": time_s,
        "spectral_shift_ghz": spectral_shift_ghz,
        "tare_shift_ghz": tare_shift_ghz,
        "markers": markers,
    }

# Returned case structure (nested dictionaries):
# case
#   run_id                  Experiment identifier supplied by the caller
#   amplitude_mm            Applied geometry amplitude in millimeters
#   mode_x, mode_y          Caller-supplied mode numbers; None if unspecified
#   notes                   Caller-supplied experimental notes
#   recording
#     source_file           Absolute Path to the input TSV
#     metadata              Header fields as strings (units, sensor, tare name, etc.)
#     gage_names            List of G names, such as "All Gages[0]"
#     position_m            Array (G,): distance along the fiber in meters
#     timestamps            List of T UTC datetime objects, one per measurement
#     time_s                Array (T,): seconds since the first measurement
#     spectral_shift_ghz    Array (T, G): rows = times, columns = fiber gages
#     tare_shift_ghz        Array (G,): exported instrument tare, stored only
#     markers               Dictionary keyed by "Start", "End", "Pass 1 Start", etc.
#       <marker name>
#         position_m        One distance along the fiber in meters
#         spectral_shift_ghz  Array (T,): this marker's measurements over time
#         tare_shift_ghz    One exported instrument tare value
# T = number of temporal samples; G = number of fiber gages.
# Missing measurements remain NaN; spectral shifts are not converted to strain.
# Example: case["recording"]["markers"]["Pass 1 Start"]["position_m"]
# Example: case["recording"]["spectral_shift_ghz"][0, :] = first spatial snapshot.
def load_fos_case(
    source_file,
    *,
    run_id,
    amplitude_mm,
    mode_x=None,
    mode_y=None,
    notes="",
):
    """Load one recording and attach experimental metadata."""
    recording = read_fos_tsv(source_file)

    return {
        "run_id": run_id,
        "amplitude_mm": amplitude_mm,
        "mode_x": mode_x,
        "mode_y": mode_y,
        "notes": notes,
        "recording": recording,
    }


def plot_case(case):
    fig, ax = plt.subplots(
        figsize=(10, 5),
        constrained_layout=True,
    )

    recording = case["recording"]
    positions = recording["position_m"]
    shifts = recording["spectral_shift_ghz"]

    ax.plot(
        positions,
        shifts.T,
        color="tab:blue",
        alpha=0.15,
        linewidth=0.7,
    )

    ax.set_title(f"{case['run_id']}: {shifts.shape[0]} samples")
    ax.set_ylabel("Spectral shift (GHz)")
    ax.set_xlabel("Distance along fiber (m)")
    ax.grid(True, alpha=0.3)

    plt.show()


def main():
    folder = Path(
        r"C:\Users\coled\Notre Dame\FTSI F26\lunaData\test_16SEP"
    )

    source_file = folder / (
        "CPT_amplitude_0.1016mm_2026-07-16_23-21-12_ch1_gages.tsv"
    )

    case = load_fos_case(
        source_file,
        run_id="run_001",
        amplitude_mm=0.1016,
        mode_x=None,
        mode_y=None,
    )
    filename = case["recording"]["source_file"].name
    print(f"Successfully loaded {filename}")

    plot_case(case)

    return case


if __name__ == "__main__":
    case = main()
