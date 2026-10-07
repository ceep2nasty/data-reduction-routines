"""Estimate sample-to-sample noise for static, fixed-free, "ideal" bending
using imposed cosine deformation shapes"""

import importlib
import sys
from pathlib import Path

import matplotlib.pyplot as plt

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "subroutines"))
from select_luna_rois import select_luna_rois

# The existing module name starts with a digit, so use importlib to import it.
center_rois = importlib.import_module("1D_find_center").center_rois


INPUT_FILE = Path(r"C:\Users\coled_agkeohi\Notre Dame\FTSI F26\NOISE_CHARACTERIZATION\1mm\0-65\1MM_BOTTOM_0-65_2026-10-07_01-38-25_ch1_gages.tsv")
OUTPUT_DIR = Path(r"C:\Users\coled_agkeohi\Notre Dame\FTSI F26\NOISE_CHARACTERIZATION\outputs\1mm")
SAVE_NAME = "1mm_bottom_0-65_rois"
PASS_COUNT = 1
METADATA = {"gage_pitch": 0.65}  # mm; test name and sampling rate come from TSV.
ACTIVE_LENGTH_M = 0.050
SMOOTHING_POINTS = 5
USE_EXISTING_ROIS = True  # True skips selection and centers the saved ROIs below.
ROI_JSON = OUTPUT_DIR / f"{SAVE_NAME}.json"


def prepare_noise_data(input_file, output_dir, save_name, pass_count,
                       active_length_m, smoothing_points=5, metadata=None,
                       *, existing_roi_json=None):
    """Open selection; Save writes ROI and centered JSONs and shows both plots.

    Closing the selector without saving stops the workflow. Noise statistics
    can be added later using the returned state's centered_data and centers.
    Supply existing_roi_json to skip selection and center saved ROI data.
    Use the uncentered ROI JSON so the full active window is still available.
    """
    output_dir = Path(output_dir)
    state = {}

    def process_selection(saved):
        trimmed, centers = center_rois(
            saved, output_dir / f"{save_name}_centered.json",
            active_length_m, smoothing_points,
        )
        state.update(centered_data=trimmed, centers=centers)

    if existing_roi_json is not None:
        process_selection(Path(existing_roi_json))
        return state, None

    _, fig = select_luna_rois(
        input_file, output_dir / f"{save_name}.json", pass_count,
        metadata, on_saved=process_selection,
    )
    return state, fig


def main():
    state, _ = prepare_noise_data(
        INPUT_FILE, OUTPUT_DIR, SAVE_NAME, PASS_COUNT,
        ACTIVE_LENGTH_M, SMOOTHING_POINTS, METADATA,
        existing_roi_json=ROI_JSON if USE_EXISTING_ROIS else None,
    )
    plt.show()
    return state


if __name__ == "__main__":
    results = main()
