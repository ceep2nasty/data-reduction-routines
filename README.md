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
