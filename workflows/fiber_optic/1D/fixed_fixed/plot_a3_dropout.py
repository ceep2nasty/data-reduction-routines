"""Plot top and bottom raw spectral shifts separately for A3 = 1 mm."""

import argparse
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "subroutines"))

import matplotlib.pyplot as plt

from load_fos_case import read_fos_tsv


plt.rcParams.update({
    "font.size": 20,
    "font.family": "serif",
    "font.serif": ["Times New Roman"],
})

DATA_DIR = Path(r"Z:\Cole\FTSI\Luna_Data\fixed_fixed_v2\fixed-fixed\roi extended")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, default=DATA_DIR)
    parser.add_argument("--output-dir", type=Path,
                        default=Path(__file__).parent / "outputs" / "dropout")
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    for side in ("top", "bottom"):
        source = args.data_dir / f"spec2/{side}/k3/k3a1_spec2_{side}_roi_extended.tsv"
        recording = read_fos_tsv(source, segment="Pass")
        position = recording["position_m"]
        shifts = recording["spectral_shift_ghz"]
        fig, ax = plt.subplots(figsize=(9, 4), constrained_layout=True)
        ax.plot(position, shifts.T, color="tab:blue", alpha=0.12, linewidth=1)
        ax.set_title(rf"Fiber on {side}, $A_3 = 1\,\mathrm{{mm}}$")
        ax.set_xlabel("Fiber position (m)")
        ax.set_ylabel("Spectral shift (GHz)")
        ax.grid(alpha=0.25)
        for extension in ("png", "pdf"):
            output = args.output_dir / f"a3_1mm_{side}_raw_spectral_shift.{extension}"
            fig.savefig(output, dpi=300, bbox_inches="tight")
            print(f"Saved {output.resolve()}")
        plt.close(fig)


if __name__ == "__main__":
    main()
