## Load fiber optic experiment in

from pathlib import Path
import numpy as np


run = {
    # Experimental metadata
    "run_id": "run_001",
    "mode_x": 1,
    "mode_y": 0,
    "amplitude": 2.0, # mm

    # Baseline measurement
    "baseline_postion": None,
    "baseline_shift": None,
    # Loaded-state measurement
    "position": None, # m
    "spectral_shift": None, # GHz

    # File data
    "folder": "C:/Users/coled_agkeohi/Notre Dame/fos-data/test-data-01",
    "source_file": None,
    "notes" : None,
}

folder = Path(run["folder"])
if not folder.is_dir():
    raise FileNotFoundError(f"Data folder does not exist: {folder}")
else : 
    print(f"Loading data from {folder}")

tsv_files = sorted(folder.glob("*.tsv"))

print(f"Found {len(tsv_files)} TSV file(s):")

for path in tsv_files:
    print(f"  {path.name}")