%% Configure and run one PCB case
% This is the file to edit for a new recording. Every supported setting and
% its full explanation lives in createPcbConfig.m.

%% Establish repository paths

% Set this to the pcb_main folder in your local repository.
pcbWorkflowDir = ...
    "C:\Users\coled\Notre Dame\Github\data-reduction-routines\workflows\pcb_main";

pcbFunctionDir = fullfile( ...
    pcbWorkflowDir, ...
    "functions");

repositoryDir = fileparts( ...
    fileparts(pcbWorkflowDir));

globalFunctionDir = fullfile( ...
    repositoryDir, ...
    "matlab", ...
    "global");

assert(isfolder(pcbWorkflowDir), ...
    'PCB workflow folder does not exist: %s', pcbWorkflowDir);

assert(isfolder(pcbFunctionDir), ...
    'PCB functions folder does not exist: %s', pcbFunctionDir);

assert(isfolder(globalFunctionDir), ...
    'Global MATLAB folder does not exist: %s', globalFunctionDir);

addpath(pcbWorkflowDir);
addpath(pcbFunctionDir);
addpath(genpath(globalFunctionDir));

fprintf("PCB workflow paths added for this MATLAB session.\n");

%% Start from the complete default configuration

cfg = createPcbConfig();

%% Case root and input files -- usually change these
% Available settings:
%   cfg.input.source      "pnrf" or "mat"
%   cfg.input.rawFolder   folder containing a raw PNRF recording
%   cfg.input.rawFileName exact PNRF filename
%   cfg.input.file        normalized or supported legacy MAT-file

dataRoot = ...
    "C:\Users\coled\Notre Dame\final_test_pcb_workflow";
cfg.input.source = "mat";
cfg.input.rawFolder = fullfile(dataRoot, "raw_pnrf_files");
cfg.input.rawFileName = "HCHC_90psi_feb2026.pnrf";
cfg.input.file = fullfile( ...
    dataRoot, "matlab_exports", "HCHC_90psi_feb2026.mat");

%% Channels -- change when the recorder layout changes
% recorderLabels follows Perception recorder order. driver, trigger, and
% data identify the channels used by the analysis. Sampling rates are Hz.

cfg.channels.recorderLabels = ["A", "B", "C", "D"];
cfg.channels.maxPerRecorder = 8;
cfg.channels.driver = "A01";
cfg.channels.trigger = "B01";
cfg.channels.data = ["C01", "C02", "C03", "C04", "D01", "D02", "D03", "D04"];
cfg.channels.driverSamplingRate = 250e3;
cfg.channels.triggerSamplingRate = 250e3;
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

cfg.output.rootFolder = dataRoot;
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
cfg.output.saveTracePlots = true;
cfg.output.saveSpectrogramData = true;
cfg.output.saveSpectrogramPlots = true;
cfg.output.saveWindowedPsdPlots = true;
cfg.output.saveRawPcbDataInResults = true;

%% Products -- choose what this run should generate
% Required upstream calculations run automatically. For example,
% secondModeAnalysis computes windowed PSD data even when windowedPsd=false.

cfg.run.fullTracePlots = true;
cfg.run.quasiSteadyTracePlots = true;
cfg.run.steadySpectrogram = true;
cfg.run.fullSpectrogram = true;
cfg.run.spectrogramPlots = true;
cfg.run.windowedPsd = true;
cfg.run.windowedPsdPreview = true;
cfg.run.secondModeAnalysis = true;
cfg.run.saveResults = true;
cfg.run.closeFiguresAtStart = true;

%% Common analysis choices
% interval: "quasiSteady", "full", or "manual". For manual analysis, set
% manualTimeRange=[start end] in seconds. channelsExcluded affects only
% second-mode calculations; excluded channels remain visible in plots.

cfg.analysis.interval = "full";
cfg.analysis.manualTimeRange = [0 1];
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
cfg.timing.pcbAnalysisChannel = "D02"; % this is important - choose a trustworthy PCB

%% Spectral settings -- tune when time/frequency resolution changes
% Spectrogram windowLength is samples. PSD durations are seconds. A smaller
% PSD windowStep creates overlapping reported measurements. plotFrequencyBand
% affects only previews; secondMode.frequencyBand controls detection.

cfg.spectrogram.windowLength = 1000;
cfg.spectrogram.overlap = 0.75;
cfg.spectrogram.frequencyBand = [50e3 800e3];
cfg.psd.windowDuration = 0.050;
cfg.psd.windowStep = 0.050;
cfg.psd.welchSegmentDuration = cfg.psd.windowDuration / 40;
cfg.psd.welchOverlap = 0.50;
cfg.psd.detrend = "linear";
cfg.psd.plotFrequencyBand = [50e3 800e3];
cfg.psd.previewWindowIndices = 10:12;

%% Second-mode settings
% Excluded channels remain in plots. frequencyBand limits the search;
% prominence rejects weak peaks; minimumWidth rejects narrow spikes;
% fitHalfWidth sets the local parabolic-fit region.

cfg.secondMode.channelsExcluded = "C01";
cfg.secondMode.frequencyBand = [100e3 180e3];
cfg.secondMode.minimumProminenceDb = 4;
cfg.secondMode.minimumWidth = 10e3;
cfg.secondMode.fitHalfWidth = 20e3;

%% Report settings

cfg.report.title = "Alignment Test — 60 psi";
cfg.report.author = "Cole Peters";

cfg.report.minimumAppearanceWindows = 2;
cfg.report.minimumDisappearanceWindows = 2;
cfg.report.bridgeMissingWindows = 1;

cfg.output.reportFile = fullfile( ...
    cfg.output.rootFolder, ...
    "alignment_60psi_report.pdf");

%% Save this exact configuration and run it

if ~isfolder(cfg.output.rootFolder)
    mkdir(cfg.output.rootFolder);
end

cfgFile = fullfile( ...
    cfg.output.rootFolder, "HCHC_90psi_cfg.mat");
save(cfgFile, 'cfg');

results = run_pcb_main(cfgFile);
