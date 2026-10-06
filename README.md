# data-reduction-routines
MATLAB data-reduction and analysis routines for wind tunnel campaigns.

## Python setup

Python workflows require Python 3.11 or newer. Direct dependencies are declared
in `pyproject.toml`: NumPy for numerical calculations, Matplotlib for plotting,
and pandas for tabular analysis and CSV exports. `uv.lock` records resolved
versions, including transitive dependencies.

From the repository root, install the locked environment with:

```powershell
uv sync --locked
```

Select `.venv\Scripts\python.exe` as your editor's Python interpreter, or run
a workflow through `uv run`, for example:

```powershell
uv run workflows/fiber_optic/subroutines/1D/nonlinearity_estimation/nonlinearity_sweep.py
```

The sweep tests every combination of modes 1–4 with independent amplitudes
from 0 to 5 mm in 0.25 mm steps (194,481 cases). It prints and saves only
cases below the yield reference in
`outputs/nonlinearity_estimation/bending_yield_comparison.csv`. Columns `A1`
through `A4` show each mode's amplitude; zero leaves a mode inactive. The
curvature reduction column is calculated from the slope of the summed shape.
Use `--output-dir` to save elsewhere.
The yield comparison uses a default specimen
thickness of 0.18 mm. The default material reference is 301 spring-temper
stainless steel: Young's modulus 193,000 MPa from
[Tokkin](https://www.tokkin.com/search/stainless-steels/austenitic/301/) and
supplier-listed yield strength 160 ksi (about 1,103 MPa) from
[OSH Cut](https://www.oshcut.com/materialdetails/stainless-steel-shim-stock-301-spring-temper).
The listed yield is a reference value, not a guaranteed minimum for this
specimen; use its material certificate to set a firm test limit.

```powershell
uv run workflows/fiber_optic/subroutines/1D/nonlinearity_estimation/nonlinearity_sweep.py
```

Override the thickness with `--thickness-mm` for another specimen, or the
reference values with `--youngs-modulus-mpa` and `--yield-strength-mpa` if
the specimen certificate gives different values. The yield check assumes
elastic, uniaxial pure bending.

To add a Python dependency, use `uv add <package>` and commit both
`pyproject.toml` and `uv.lock`.

## Data

Raw experimental measurements are intentionally excluded from this repository. They should be stored and imported locally to keep GitHub file weight low.

## Structure

## Structure

- `matlab/global/` - reusable analysis and utility routines
- `matlab/ir/` - infrared thermography reduction routines
- `matlab/pcb/` - PCB pressure-transducer reduction routines
- `workflows/` - campaign-specific processing workflows
- `outputs/` - generated analysis products
- `examples/` - small example/reference cases
- `docs/` - documentation

For the current modular PCB workflow state, function interfaces, and planned
second-mode tracking/alignment work, see
[`docs/pcb_workflow_context.md`](docs/pcb_workflow_context.md).
