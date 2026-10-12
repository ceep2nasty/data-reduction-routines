"""Export noise results using the 1 mm basis matching each side and gage pitch."""

import csv
import json
import shutil
from pathlib import Path

from batch_estimate_noise import DATA_ROOT, discover_full_cases, process_batch, plot_noise_vs_amplitude


OUTPUT_DIR = Path("/mnt/lab_storage/Cole/FTSI/Reports/12OCT26")


def save_summary(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main():
    sources = discover_full_cases(DATA_ROOT / "collected data")
    cases = []
    for source in sources:
        if source["imposed_amplitude_mm"] == 0:
            continue  # Existing noise outputs cover the imposed cosine cases.
        side, amplitude = source["side"], source["amplitude_folder"]
        pitch = float(source["pitch_name"].replace("-", "."))
        pitch_key = f"{pitch:g}".replace(".", "-")
        name = f"{amplitude}_{side}_{pitch_key}_full"
        original = DATA_ROOT / "outputs" / amplitude / pitch_key / side
        folder = OUTPUT_DIR / side / f"gage_pitch_{pitch:.2f}mm" / amplitude
        cases.append(dict(name=name, side=side, gage_pitch_mm=pitch,
                          original=original / f"{name}_rois_centered.json",
                          input_file=str(source["input_file"]), output_dir=folder,
                          centered_json=folder / f"{name}_rois_centered.json",
                          imposed_amplitude_mm=source["imposed_amplitude_mm"],
                          imposed_direction=source["imposed_direction"],
                          calibration_direction=source["imposed_direction"],
                          calibration_path=OUTPUT_DIR / side / "calibration" /
                          f"1mm_{side}_mode1_{pitch_key}_full.npz"))
    # Higher-amplitude cases use the matching 1 mm calibration.
    for case in cases:
        if not case["original"].is_file():
            raise FileNotFoundError(case["original"])
    for side in ("top", "bottom"):
        folder = OUTPUT_DIR / side / "calibration"
        folder.mkdir(parents=True, exist_ok=True)
        for pitch_key in ("0-65", "2-6"):
            name = f"1mm_{side}_mode1_{pitch_key}_full"
            for extension in ("npz", "json", "png"):
                shutil.copy2(DATA_ROOT / "optical_basis_cal/1mm" / f"{name}.{extension}", folder)
    for case in cases:
        case["output_dir"].mkdir(parents=True, exist_ok=True)
        shutil.copy2(case["original"], case["centered_json"])
    rows = process_batch(cases, None, calibration_direction=1,
                         output_dir=OUTPUT_DIR, save_plots=True)
    for row, case in zip(rows, cases):
        row.update(side=case["side"], gage_pitch_mm=case["gage_pitch_mm"],
                   input_file=case["input_file"], calibration_amplitude_mm=1.0,
                   calibration_gage_pitch_mm=case["gage_pitch_mm"])
        save_summary(case["output_dir"] / "summary.csv", [row])
    save_summary(OUTPUT_DIR / "summary.csv", rows)
    for side in ("top", "bottom"):
        selected = [row for row in rows if row["side"] == side]
        save_summary(OUTPUT_DIR / side / "summary.csv", selected)
        for pitch in (0.65, 2.6):
            save_summary(OUTPUT_DIR / side / f"gage_pitch_{pitch:.2f}mm" / "summary.csv",
                         [row for row in selected if row["gage_pitch_mm"] == pitch])
    paths = plot_noise_vs_amplitude(rows, OUTPUT_DIR)
    for path in paths:
        path.replace(OUTPUT_DIR / path.name.split("_")[0] / path.name)
    manifest = dict(
        method="Linear per-frame amplitude and baseline fit; fixed existing centered ROIs; no arc or finite-slope correction",
        calibration="1 mm linear basis matched to target side and gage pitch (0.65 or 2.60 mm); tare retained",
        uncertainty="Temporal sample standard deviation (ddof=1); 95% bands are 1.96 times std, not uncertainty of the mean; calibration uncertainty excluded",
        coverage="Top 1-4 mm and bottom 1-5 mm, both pitches. No top 5 mm recording available. FLAT recordings excluded from this existing cosine-case report.",
        calibration_provenance="Copied calibration JSONs retain their original Windows source paths; current source paths are recorded in summary.csv.",
        cases=len(rows),
    )
    (OUTPUT_DIR / "report_settings.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Saved {len(rows)} cases to {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
