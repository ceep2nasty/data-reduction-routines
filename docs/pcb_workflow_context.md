# PCB Workflow Context

This document is the durable handoff for the modular PCB workflow on branch
`feature/modular-pcb-workflow`. Read it before continuing work on PCB spectral
analysis or cone alignment.

## User Goal

Build a MATLAB workflow that tracks second-mode instability on selected PCB
channels and determines whether a cone is aligned. Alignment should use three
specified channels, each tagged with a physical cone location such as `top`,
`bottom`, `north`, or `south`.

The initial alignment definition is:

1. Each selected channel has a valid second-mode frequency in the configured
   frequency range.
2. The selected channel frequencies agree within a configured tolerance.

A later diagnostic should suggest a cone movement. For example, the current
hypothesis is that a higher second-mode frequency on the top PCB relative to
the bottom PCB should suggest decreasing angle of attack. This sign convention
must be experimentally confirmed before being treated as an automatic rule.

## Current Session Scope

The work has been in teaching/design mode unless implementation is explicitly
requested. The immediate implementation topic is `trackSecondMode`.

The tracker should do more than return the strongest frequency peak. It should
also determine when the second mode becomes apparent and when it disappears as
the spectrum transitions toward turbulence:

- Appearance: a local maximum inside the configured band becomes sufficiently
  distinct from its spectral background and remains distinct for a required
  number of spectrogram windows.
- Disappearance: the distinct peak remains below the visibility criterion for
  a required number of windows.

Use peak contrast rather than total spectral flatness as the primary visibility
metric. The current `Spectrogram` helper returns linear magnitude (`abs(S)`),
so an initial contrast metric can be `peakAmplitude / backgroundLevel`.

## Current Checkpoint

The modular runner is:

`workflows/pcb_main/run_pcb_main.m`

Current analysis channels and physical locations are configured as:

```matlab
cfg.analysis.dataChannels = ["C01", "C02", "D01"];
cfg.analysis.dataLocations = ["top", "bottom", "north"];
```

The location array must match the channel array by index.

Current second-mode configuration is:

```matlab
cfg.secondMode.frequencyBand = [50e3 300e3];
cfg.secondMode.peakFraction = 0.1;
cfg.secondMode.minValidFraction = 0.5;
```

These fields are currently present in the runner, but the tracker is not yet
connected to the workflow.

`workflows/pcb_main/functions/trackSecondMode.m` exists but is incomplete. Its
current partial output design includes:

- `channels`
- `locations`
- `frequencyTrace`
- `frequencyMedian`
- `frequencyMean`
- `frequencyStd`
- `validFraction`

The next implementation should add time-dependent visibility and transition
outputs, such as `peakAmplitude`, `backgroundLevel`, `peakContrast`,
`isVisible`, `appearanceTime`, and `disappearanceTime`.

## Processing Flow

```text
convertPnrfData or loadPcbData
        -> extractPcbChannels
        -> computePcbSpectrogram
        -> trackSecondMode
        -> evaluate alignment (future)
        -> suggest cone movement (future)
```

Keep these responsibilities separate. `trackSecondMode` measures spectral
behavior; a future alignment function compares channel summaries; a future
recommendation function interprets spatial differences.

## Modular PCB Functions

### `run_pcb_main.m`

Script-level orchestrator. It creates `cfg`, loads or converts data, extracts
channels, plots traces, computes spectrograms, and plots spectrograms.

Inputs: configuration edited inside the script and local input files.

Outputs: `pcbData`, extracted channel structs, `spectrogramResults`, and
figures in the workspace when the corresponding stages run.

### `convertPnrfData(cfg)`

Converts a Perception `.pNRF` recording into the repository's normalized PCB
struct. Supports `memory` and `disk` modes.

Input: `cfg.input.rawFolder`, `cfg.input.rawFileName`, recorder labels,
`cfg.channels.maxPerRecorder`, and conversion/output settings.

Output: `pcbData` with `channels` and `signalData`, where each signal entry has
`time` and `signal`. In disk mode it also saves a MAT file.

### `loadPcbData(cfg)`

Loads an existing converted MAT file.

Input: `cfg.input.file`; optionally `cfg.input.variable`.

Output: loaded data struct. It accepts files containing `pcbData`, `blockData`,
or the configured raw variable name, which defaults to `Perception_Raw`.

### `extractPcbChannels(cfg, pcbData)`

Selects driver, trigger, and analysis channels by label.

Inputs: `cfg.analysis.driverChannel`, `triggerChannels`, `dataChannels`, and
their sampling rates; normalized `pcbData`.

Outputs: `driverData`, `triggerData`, and `dataData`. Each contains `channels`,
cell arrays of `time` and `signal`, and `samplingRate`.

### `computePcbSpectrogram(cfg, dataData)`

Computes one spectrogram for each analysis channel using the shared
`Spectrogram` helper.

Inputs: `cfg.spectrogram.windowLength`, `overlap`, `frequencyBand`, `colormap`,
and `dataData`.

Output: `spectrogramResults` with `channels`, `time`, `frequency`, and
`magnitude` cell arrays. It can save `spectrogramResults.mat`.

### `plotPcbTraces(cfg, dataData, triggerData, driverData)`

Plots driver pressure, PCB data traces, and trigger traces. It uses plotting
copies and does not modify the extracted input structs.

Inputs: plotting settings and the three extracted data structs.

Output: `figures` struct with `driver`, `data`, and `trigger` figure handles.

### `plotQuasiSteadyPcbTraces(cfg, dataData, triggerData, driverData, steadyWindow)`

Creates separate driver, PCB, and trigger trace figures cropped to the detected
quasi-steady interval. It preserves absolute time so the plots can be compared
directly with the full-record trace figures.

Inputs: plotting configuration, the original extracted data structs, and a
`steadyWindow` containing valid `startTime` and `endTime` fields.

Output: `figures` struct with `driver`, `data`, and `trigger` figure handles.
The function crops copies and does not modify the original extracted data.

### `plotPcbSpectrogram(cfg, spectrogramResults)`

Plots each channel's spectrogram and optionally saves PNG files.

Inputs: plotting/spectrogram configuration and `spectrogramResults`.

Output: `spectrogramFig`. Note that the current loop overwrites this variable,
so the final returned handle is the last created figure.

### `trackSecondMode(cfg, spectrogramResults)`

Planned tracker. It should search the configured second-mode band for each
channel, track/refine a candidate frequency per spectrogram time slice, reject
weak or ambiguous candidates, summarize valid frequencies, and detect mode
appearance/disappearance transitions.

Inputs: `cfg.secondMode` and `spectrogramResults`.

Planned output: `secondModeResults` containing channel/location identity,
frequency traces and summaries, visibility metrics, and transition times.

Recommended fields:

```text
channels, locations, time, frequencyTrace
frequencyMedian, frequencyMean, frequencyStd, validFraction
peakAmplitude, backgroundLevel, peakContrast, isVisible
appearanceTime, disappearanceTime
```

Use `NaN` for a transition time that does not occur in the analyzed record.

## Shared Spectral Helpers

### `Spectrogram(sig, fsamp, nseg, pct_overlap, cmap, fband)`

Computes a spectrogram with a Hamming window and optional frequency-band
restriction.

Inputs: signal, sample rate, segment length, overlap fraction, colormap (not
used in the calculation), and optional `[fmin fmax]` in Hz.

Outputs: `T`, `F`, and `SpectroLog`. Despite its name, `SpectroLog` is currently
`abs(S)`, a linear magnitude matrix, not a logarithmic quantity.

### `spectrogram_peak_track(T, F, SpectroLog, prange, peak_dec)`

Tracks a refined maximum for every time slice in a frequency range using a
fraction-of-peak crossing estimate.

Inputs: time, frequency, magnitude matrix, `[fmin fmax]`, and peak fraction.

Output: `f_peak_time` frequency trace.

Important caveat: its current conversion logic assumes values above one are dB,
which conflicts with `Spectrogram` returning linear magnitude. This should be
resolved before relying on it for quantitative visibility or alignment.

### `find_band_peak(freq_kHz, PSD, prange, peak_dec, ShowPeaks)`

Finds and refines the dominant peak in a specified kHz band and optionally plots
the crossing markers.

Inputs: frequency in kHz, PSD-like vector, band in kHz, peak fraction, and plot
flag.

Outputs: `f_peak`, `A_peak`, and integrated `Power_peak`.

### `Power_Spectral_Density(x, fsamp, nseg, pct_overlap, method, numBands, FiltAmount)`

Computes PSD using original block averaging, Welch, or filterbank variants.

Inputs: signal, sample rate, segment count, overlap, method, optional band count,
and optional filter amount.

Outputs: PSD, frequency in kHz, and frequency resolution in Hz.

### `psd_estimate(x, fs, method, nfft, doPlot)`

Computes FilterBank, Welch, or both PSD estimates.

Inputs: signal, sample rate, method, FFT length, and plotting flag.

Outputs: either one cell containing all outputs or multiple frequency/PSD
outputs, depending on `nargout`.

### `removeBroadNoisePeaks(FreqNoise, SxxNoise, Freq, Sxx, Fband)`

Reduces wind-off noise peaks from a wind-on spectrum by detecting noise-band
peaks and applying a smoothed attenuation mask.

Inputs: wind-off frequency/PSD vectors, wind-on frequency/PSD vectors, and
`Fband = [Fmin Fmax]` in the same units as the frequency vectors.

Output: `Sxx_clean`, the attenuated wind-on spectrum.

## `trackSecondMode` Design Decisions

Recommended configuration additions:

```matlab
cfg.secondMode.minimumContrast = 2.0;
cfg.secondMode.minimumAmplitude = 0;
cfg.secondMode.contrastSmoothingWindows = 3;
cfg.secondMode.minimumVisibleWindows = 3;
cfg.secondMode.minimumInvisibleWindows = 5;
cfg.secondMode.edgeBufferBins = 2;
```

The intended algorithm is:

1. Validate channel counts, frequency bands, and matching spectrogram sizes.
2. Restrict each channel to `cfg.secondMode.frequencyBand`.
3. Find the strongest candidate in each time slice.
4. Calculate candidate amplitude and a local/background level.
5. Calculate and optionally smooth peak contrast.
6. Mark a candidate visible only when contrast/amplitude/edge checks pass.
7. Set the frequency trace to `NaN` where the candidate is not visible.
8. Apply persistence logic to find first appearance and sustained disappearance.
9. Calculate median, mean, standard deviation, and valid fraction from visible
   frequency samples.

Use persistence because one weak or strong window should not create a false
transition. Appearance can require fewer consecutive visible windows than
disappearance requires invisible windows.

The spectrogram time spacing limits transition-time accuracy. For the current
`2 MHz`, `1000`-sample, `75%`-overlap configuration, the hop is approximately
`0.125 ms`.

## Alignment and Direction Work Remaining

The future alignment evaluator should compare robust channel summaries rather
than every raw frequency sample:

```text
all channel medians inside the target band
and max(channel median) - min(channel median) <= spread tolerance
```

It should return pass/fail, frequencies, spread, tolerance, and failed
conditions. It should use channel locations for interpretation, not channel
indices alone.

The future movement recommendation should compare location pairs, for example
`top - bottom` for angle of attack and `north - south` for yaw. The sign of the
recommendation must be validated with known perturbations before becoming an
automatic control rule.

## Validation Plan

The cheapest first test is a synthetic spectrogram containing a Gaussian peak
whose known frequency moves with time. The tracker should recover that curve
within the spectrogram frequency resolution.

Visibility tests should include:

1. A persistent visible peak: appearance is detected and disappearance is
   `NaN`.
2. A peak that fades below contrast: disappearance is detected after the
   configured invisible-window persistence.
3. An isolated strong/noisy window: no false transition is reported.
4. Three channel summaries inside the band and within spread tolerance:
   alignment passes.
5. Three channel summaries inside the band but outside spread tolerance:
   alignment fails.

Do not encode the angle-of-attack direction rule until the top/bottom response
has been checked against a known positive and negative perturbation.