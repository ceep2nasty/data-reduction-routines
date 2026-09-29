%% Configure and run one PCB case
% This is the file to edit for a new recording. Every supported setting and
% its full explanation lives in createPcbConfig.m.

callerDir = fileparts(mfilename('fullpath'));
addpath(callerDir);

cfg = createPcbConfig();

%% Case root and input files -- usually change these
% Available settings:
%   cfg.input.source      "pnrf", "mat", or "txt"
%   cfg.input.rawFolder   folder containing a raw PNRF recording
%   cfg.input.rawFileName exact PNRF filename
%   cfg.input.file        converted MAT-file or Perception text export

dataRoot = ...
    "C:\Users\coled\Notre Dame\heatedCone_F26\AFOSR_Heated_Cone_Jan2026";
cfg.input.source = "txt";
cfg.input.rawFolder = fullfile(dataRoot, "raw_pnrf_files");
cfg.input.rawFileName = ""; % Unused for text input.
cfg.input.file = fullfile( ...
    dataRoot, "PCB_Data", "Iso_90psi", "Iso_90psi_001.txt");

%% Channels -- change when the recorder layout changes
% recorderLabels follows Perception recorder order. driver, trigger, and
% data identify the channels used by the analysis. Sampling rates are Hz.

cfg.channels.recorderLabels = ["A", "B", "C", "D"];
cfg.channels.maxPerRecorder = 8;
cfg.channels.driver = "A01";
cfg.channels.trigger = "B01";
% January mapping established by the reference spectra and legacy selection.
cfg.channels.data = ["D01", "D02", "C01", "D05", "D08", "D07", "D06"];
cfg.channels.sensorNumbers = [2 3 4 5 6 7 8];
cfg.channels.order = [2 3 4 5 6 7 8]; % Select/reorder physical sensor numbers.
% Export grid rates, not necessarily the original recorder acquisition rates.
cfg.channels.driverSamplingRate = 2e6;
cfg.channels.triggerSamplingRate = 2e6;
cfg.channels.dataSamplingRate = 2e6;

%% External MATLAB folders -- normally leave empty
% Repository-local PCB and global functions are added automatically.
% Add a folder here only when this case calls helpers outside the repo;
% every listed folder and its subfolders are added with genpath.

cfg.paths.additionalFolders = strings(0, 1);

%% Outputs -- usually change the root folder
% The individual output folders may also be replaced independently. Save
% switches write only products enabled in cfg.run. saveRawPcbDataInResults
% controls whether the often-large normalized input is embedded in results.

cfg.output.rootFolder = fullfile(callerDir, "outputs", "january", "Iso_90psi");
cfg.output.convertedDataFolder = fullfile( ...
    cfg.output.rootFolder, "matlab_exports");
cfg.output.tracePlotFolder = fullfile( ...
    cfg.output.rootFolder, "saved_pcb_figs");
cfg.output.spectrogramFolder = fullfile( ...
    cfg.output.rootFolder, "spectral_analysis", "spectrogram_plots");
cfg.output.windowedPsdFolder = fullfile( ...
    cfg.output.rootFolder, "spectral_analysis", "PSD_plots");
cfg.output.resultsFile = fullfile( ...
    cfg.output.rootFolder, "pcb_analysis_results.mat");
cfg.output.saveTracePlots = false;
cfg.output.saveSpectrogramData = false;
cfg.output.saveSpectrogramPlots = false;
cfg.output.saveWindowedPsdPlots = false;
cfg.output.saveRawPcbDataInResults = false;

%% Products -- choose what this run should generate
% Required upstream calculations run automatically. For example,
% secondModeAnalysis computes windowed PSD data even when windowedPsd=false.

cfg.run.fullTracePlots = false;
cfg.run.quasiSteadyTracePlots = false;
cfg.run.steadySpectrogram = false;
cfg.run.fullSpectrogram = false;
cfg.run.spectrogramPlots = false;
cfg.run.windowedPsd = true;
cfg.run.windowedPsdPreview = true;
cfg.run.secondModeAnalysis = false;
cfg.run.saveResults = false;
cfg.run.closeFiguresAtStart = false;

%% Common analysis choices
% interval: "quasiSteady", "full", or "manual". For manual analysis, set
% manualTimeRange=[start end] in seconds. channelsExcluded affects only
% second-mode calculations; excluded channels remain visible in plots.

cfg.analysis.interval = "manual";
cfg.analysis.manualTimeRange = [0.75 0.85];
cfg.analysis.onInvalidQuasiSteadyWindow = "useFullRecord";

%% Quasi-steady timing -- tune only when detection needs adjustment
% Trigger settings control the voltage threshold and required hold time.
% Driver settings control flat-pressure detection. PCB settings compare
% local signal fluctuations with a pre-run reference interval. All timing
% defaults, including slope/noise limits and persistence durations, are in
% createPcbConfig.m and can be overridden here in exactly the same way.

cfg.timing.triggerThreshold = 2.5;
cfg.timing.triggerHysteresis = 2.3;
cfg.timing.triggerHoldTime = 0.002;
cfg.timing.driverFlatEvaluationInterval = 0.001;
cfg.timing.pcbAnalysisChannel = "D05";

%% Spectral settings -- tune when time/frequency resolution changes
% Spectrogram windowLength is samples. PSD durations are seconds. A smaller
% PSD windowStep creates overlapping reported measurements. plotFrequencyBand
% affects only previews; secondMode.frequencyBand controls detection.

cfg.spectrogram.windowLength = 1000;
cfg.spectrogram.overlap = 0.75;
cfg.spectrogram.frequencyBand = [50e3 800e3];
cfg.psd.windowDuration = 0.100;
cfg.psd.windowStep = 0.100;
cfg.psd.welchSegmentDuration = cfg.psd.windowDuration / 40;
cfg.psd.welchOverlap = 0.50;
cfg.psd.detrend = "linear";
cfg.psd.plotFrequencyBand = [0 800e3];
cfg.psd.previewWindowIndices = 1;

%% Second-mode settings
% Excluded channels remain in plots. frequencyBand limits the search;
% prominence rejects weak peaks; minimumWidth rejects narrow spikes;
% fitHalfWidth sets the local parabolic-fit region.

cfg.secondMode.channelsExcluded = strings(0, 1);
cfg.secondMode.frequencyBand = [100e3 180e3];
cfg.secondMode.minimumProminenceDb = 4;
cfg.secondMode.minimumWidth = 10e3;
cfg.secondMode.fitHalfWidth = 20e3;

%% Run in memory without saving configuration, results, or figures

results = run_pcb_main(cfg);
