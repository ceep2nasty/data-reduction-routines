# PR100 Bonded-Delrin Calibration Plan

## Objective

Use deflectometer measurements as the displacement reference for calibrating the
PR100 fiber bonded to the Delrin specimen. The initial calibration should
estimate the effective optical-shift-to-strain coefficient used by the existing
one-dimensional shape reconstruction and quantify its uncertainty and
repeatability.

The current reconstruction uses a nominal value of `-6.67e-6 strain/GHz` in
`workflows/fiber_optic/subroutines/1D/sine_basis/compute_1D_shape.py`. The calibration should
not replace that default until the result passes the validation checks below.

## Required inputs

### Fiber-optic data

- Luna gage-export TSV for each loaded run.
- A compatible unloaded baseline TSV.
- Run identifier and nominal imposed displacement.
- ROI markers, especially `Beginning ROI` and `End ROI`.
- Acquisition timestamps or another synchronization cue.

### Deflectometer data

- Raw export file and a description of its columns, units, and delimiter.
- Measured displacement for every load step or run.
- Sensor position and sign convention relative to the reconstructed shape.
- Sampling timestamps, if the measurement is time resolved.
- Instrument resolution or stated measurement uncertainty.

### Specimen and installation metadata

- PR100 identifier and bonded active length.
- Delrin thickness at the bonded region.
- Fiber diameter and bond-line/adhesive information.
- Support spacing and boundary conditions.
- Deflectometer contact location along the specimen.
- Temperature during baseline and loaded measurements.

Keep raw measurements outside the repository, consistent with the repository's
data policy. Commit only configuration, processing code, tests, and small
synthetic fixtures.

## Proposed data model

Represent each calibration run with:

- `run_id`
- paths to the Luna run, Luna baseline, and deflectometer export
- nominal load or displacement, when available
- measured reference displacement and its position
- acquisition time interval
- specimen geometry and sensor installation metadata
- notes and exclusion flags

Store campaign-specific paths and values in a configuration file rather than in
the reusable calculation functions.

## Processing workflow

1. **Ingest without calibration**
   - Reuse `read_fos_tsv` for Luna exports.
   - Add a dedicated deflectometer loader after inspecting a representative
     export.
   - Preserve raw values, units, timestamps, and provenance.

2. **Quality-control each instrument**
   - Verify monotonic time and position axes, expected units, missing samples,
     and duplicate records.
   - Plot raw optical shift and raw deflectometer displacement before filtering
     or averaging.
   - Detect stable unloaded and loaded intervals; do not assume the entire file
     is steady.

3. **Align measurements**
   - Align by timestamps when both instruments are time resolved.
   - Otherwise join explicit steady load steps by run identifier.
   - Record any time offset or manually selected interval in the result.

4. **Apply the unloaded reference**
   - Restore the Luna-exported tare and subtract the mean unloaded baseline,
     following the existing shape workflow.
   - Zero the deflectometer using its unloaded reading from the same test
     sequence.
   - Report baseline drift and run-to-run zero offsets.

5. **Compute an unscaled optical response**
   - Refactor the shape calculation so the spectral-shift profile can be fitted
     independently of the assumed strain-per-GHz coefficient.
   - Evaluate reconstructed displacement at the physical deflectometer
     location, rather than comparing only peak amplitudes.

6. **Estimate the calibration**
   - Fit measured deflectometer displacement against the unscaled reconstructed
     response across all accepted load levels.
   - Start with a zero-intercept model only when the zeroed data support it;
     otherwise estimate and report the intercept.
   - Use repeated runs to estimate confidence intervals and separate within-run
     noise from run-to-run variability.
   - Check loading and unloading subsets separately for hysteresis.

7. **Validate out of sample**
   - Hold out at least one repeat at each amplitude, or use grouped
     cross-validation by run when the data set is small.
   - Report displacement error in millimeters and percent of full scale.
   - Inspect residuals versus displacement, position, time, and temperature.

## Calibration outputs

- Effective strain-per-GHz coefficient, units, sign convention, standard error,
  confidence interval, and valid operating range.
- Fitted intercept and evidence for retaining or removing it.
- Per-run reconstructed and deflectometer displacements.
- Bias, RMSE, maximum absolute error, and repeatability.
- Baseline drift and hysteresis summaries.
- Diagnostic plots: raw signals, alignment, calibration curve with uncertainty,
  residuals, and predicted-versus-reference displacement.
- Machine-readable result containing source-file provenance and processing
  settings.

## Acceptance criteria to set before final calibration

Numerical thresholds should be chosen from the experiment's required accuracy
and the deflectometer specification. At minimum, require:

- no unexplained sign or unit mismatch;
- stable unloaded baselines;
- acceptable repeatability at each displacement;
- no material curvature in calibration residuals over the claimed range;
- held-out error below the agreed displacement tolerance; and
- a full-rank, adequately conditioned shape fit.

## Proposed repository changes

1. Add `workflows/fiber_optic/calibration/` for configuration and orchestration.
2. Add a pure deflectometer loader with format-validation tests.
3. Extract baseline correction and unscaled shape response from
   `compute_1D_shape.py` into reusable functions while preserving its current
   public behavior.
4. Add calibration fitting, uncertainty metrics, and diagnostic plotting.
5. Add synthetic fixtures and tests covering units, sign, alignment, missing
   data, regression recovery, and held-out prediction.
6. Add a short run guide after the first real data file establishes the import
   format.

## Open decisions before implementation

1. What file format and columns does the deflectometer export contain?
2. Is the deflectometer signal time resolved or one value per load step?
3. Where is its measurement point relative to `Beginning ROI`?
4. Are loading, unloading, and repeat runs available?
5. Is the desired deliverable a sensor coefficient, a displacement correction,
   or both?
6. What displacement range and maximum acceptable calibration error apply?
7. Were the Luna baseline and loaded data collected at comparable temperature?

