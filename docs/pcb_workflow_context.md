# Packaged PCB workflow

The PCB workflow has two entry points:

- `workflows/pcb_main/createPcbConfig.m` constructs the complete configuration
  with the current campaign values as defaults. Passing a filename saves a MAT
  file containing the variable `cfg`.
- `workflows/pcb_main/run_pcb_main.m` runs the analysis from either a `cfg`
  struct or a saved `*_cfg.mat` file and returns one `results` struct.

For routine use, copy and edit `workflows/pcb_main/run_pcb_case.m`. That caller
puts paths, channel selection, run switches, timing controls, spectral settings,
and second-mode settings into separate sections. The constructor remains the
authoritative list of supported settings and their default values.

## Typical use

```matlab
cfg = createPcbConfig();
cfg.input.source = "mat";
cfg.input.file = "D:\\test_data\\run_012.mat";
cfg.output.rootFolder = "D:\\test_data\\run_012_results";
results = run_pcb_main(cfg);
```

A saved case is run with:

```matlab
cfg = createPcbConfig();
save("run_012_cfg.mat", "cfg");
results = run_pcb_main("run_012_cfg.mat");
```

## Execution rules

Input loading and channel extraction always run because every product needs
them. Product switches in `cfg.run` request final products; the runner resolves
their prerequisites automatically:

- `windowedPsdPreview` computes the windowed PSD first.
- `secondModeAnalysis` computes the windowed PSD first.
- A windowed PSD using `analysis.interval = "quasiSteady"` runs timing detection
  first.
- `quasiSteadyTracePlots` and `steadySpectrogram` run timing detection first.
- Spectrogram data saving is independent of spectrogram plot saving.

If quasi-steady detection fails, `cfg.analysis.onInvalidQuasiSteadyWindow`
chooses between using the full record and raising an error. A manual interval is
applied only to the windowed PSD and second-mode branch.

## Data flow

```text
PNRF conversion or MAT loading
        -> normalized pcbData
        -> driver, trigger, and PCB channel extraction
        -> optional trace products
        -> optional quasi-steady detection
        -> optional spectrogram products
        -> windowed Welch PSD when requested or required
        -> per-window second-mode peak detection
        -> results struct and optional MAT save
```

Normalized `pcbData` contains `channels` and `signalData`. Each `signalData`
entry contains matching `time` and `signal` vectors. `loadPcbData` also converts
supported legacy `Perception_Raw` or `blockData` recorder structs to this form.
All extracted channels share one experiment-relative time origin.

## Windowed second-mode analysis

`computeWindowedPcbPsd` calculates one Welch PSD for each configured time window
and channel. `analyzeSecondModeWindows` removes only the channels listed in
`cfg.secondMode.channelsExcluded`, then calls `detectSecondModePeak` for every
remaining channel and window.

The detector searches `cfg.secondMode.frequencyBand`, uses peak prominence and
width to reject noise features, and fits a local parabola in PSD dB. A detection
is accepted when the fitted parabola opens downward and its vertex lies inside
the fit region. Results retain the frequency, amplitude, prominence, width,
curvature, and fit quality for every window and channel.

## Results contract

`run_pcb_main` always returns the same top-level fields, even when a product is
disabled. Key fields are:

- `cfg`, `configurationFile`, `metadata`, `stages`, and `stageStatus`
- `pcbData`, `driverData`, `triggerData`, `dataData`, and `analysisData`
- `steadyWindow`, `timingDiagnostics`, and `steadyDataData`
- `spectrogram.steady`, `spectrogram.full`, and `windowedPsd`
- `secondMode`, `figures`, and `files`

When `cfg.run.saveResults` is true, the runner saves this structure to
`cfg.output.resultsFile`. Figure handles are removed from the saved copy. Raw
`pcbData` is also omitted unless `cfg.output.saveRawPcbDataInResults` is true.

## Future PDF report

The stable `results` structure is the input boundary for a report generator.
The report can be added without changing detection code. A first report should
include run metadata and configuration, full and quasi-steady traces, timing
diagnostics, representative PSDs, channel-by-channel second-mode detection
coverage and frequency trends, and a concise status table. MATLAB Report
Generator can be used when available; a figure-and-table export path should
remain possible for installations without that toolbox.
