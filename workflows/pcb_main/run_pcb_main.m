function results = run_pcb_main(cfgInput)
%RUN_PCB_MAIN Run the packaged PCB analysis workflow.
%
%   results = run_pcb_main(cfg)
%   results = run_pcb_main("case_cfg.mat")

if nargin < 1
    error('run_pcb_main:MissingConfiguration', ...
        'Pass a configuration struct or a MAT-file containing cfg.');
end

[cfg, configurationFile] = loadConfiguration(cfgInput);

scriptDir = fileparts(mfilename('fullpath'));
repoDir = fileparts(fileparts(scriptDir));
functionDir = fullfile(scriptDir, 'functions');
reportingDir = fullfile(scriptDir, 'reporting');
globalDir = fullfile(repoDir, 'matlab', 'global');

assert(isfolder(functionDir), ...
    'PCB functions folder does not exist: %s', functionDir);
assert(isfolder(reportingDir), ...
    'PCB reporting folder does not exist: %s', reportingDir);
assert(isfolder(globalDir), ...
    'Global MATLAB folder does not exist: %s', globalDir);

addpath(functionDir);
addpath(reportingDir);
addpath(genpath(globalDir));

validatePcbConfig(cfg);

additionalFolders = string(cfg.paths.additionalFolders(:));
additionalFolders(additionalFolders == "") = [];
for folder = additionalFolders.'
    addpath(genpath(folder));
end

if cfg.run.closeFiguresAtStart
    close all;
end

stages = resolveStages(cfg);
results = initializeResults(cfg, configurationFile, stages);

fprintf('PCB analysis workflow started\n');

%% Load or convert the source data

switch string(cfg.input.source)
    case "pnrf"
        fprintf('\n--- Converting PNRF data ---\n');
        pcbData = convertPnrfData(cfg);
    case "mat"
        fprintf('\n--- Loading MAT data ---\n');
        pcbData = loadPcbData(cfg);
end
results.pcbData = pcbData;
results.stageStatus.inputLoaded = true;

%% Extract required channels

fprintf('\n--- Extracting configured channels ---\n');
[driverData, triggerData, dataData] = ...
    extractPcbChannels(cfg, pcbData);
results.driverData = driverData;
results.triggerData = triggerData;
results.dataData = dataData;
results.stageStatus.channelsExtracted = true;

%% Full-record trace plots

if cfg.run.fullTracePlots
    fprintf('\n--- Plotting full-record traces ---\n');
    results.figures.fullTraces = plotPcbTraces( ...
        cfg, dataData, triggerData, driverData);
    results.stageStatus.fullTracePlots = true;
end

%% Quasi-steady timing detection and data selection

steadyWindow = emptySteadyWindow();
timingDiagnostics = struct();
steadyDataData = dataData;

if stages.needsQuasiSteadyWindow
    fprintf('\n--- Detecting quasi-steady interval ---\n');
    [steadyWindow, timingDiagnostics] = determineQuasiSteadyWindow( ...
        cfg, driverData, triggerData, dataData);
    results.stageStatus.quasiSteadyDetection = true;

    if all(isfinite(steadyWindow.time))
        steadyDataData = cropChannelData(dataData, steadyWindow.time);
        printTimingSummary(steadyWindow, timingDiagnostics);
    elseif string(cfg.analysis.onInvalidQuasiSteadyWindow) == "error"
        error('run_pcb_main:NoQuasiSteadyWindow', ...
            'No valid quasi-steady interval was detected.');
    else
        warning('run_pcb_main:NoQuasiSteadyWindow', ...
            ['No valid quasi-steady interval was detected; ', ...
            'the full record will be used where a fallback is possible.']);
    end
end

results.steadyWindow = steadyWindow;
results.timingDiagnostics = timingDiagnostics;
results.steadyDataData = steadyDataData;

if cfg.run.quasiSteadyTracePlots && all(isfinite(steadyWindow.time))
    fprintf('\n--- Plotting quasi-steady traces ---\n');
    results.figures.quasiSteadyTraces = ...
        plotQuasiSteadyPcbTraces( ...
            cfg, dataData, triggerData, driverData, steadyWindow);
    results.stageStatus.quasiSteadyTracePlots = true;
end

if stages.needsWindowedPsd
    analysisData = selectAnalysisData( ...
        cfg, dataData, steadyDataData, steadyWindow);
else
    analysisData = dataData;
end
results.analysisData = analysisData;

%% Spectrogram calculation and plotting

if cfg.run.steadySpectrogram
    fprintf('\n--- Computing quasi-steady spectrograms ---\n');
    results.spectrogram.steady = computePcbSpectrogram( ...
        cfg, steadyDataData);
    results.stageStatus.steadySpectrogram = true;

    if cfg.output.saveSpectrogramData
        saveSpectrogramData(cfg, results.spectrogram.steady, "steady");
    end
    if cfg.run.spectrogramPlots
        results.figures.steadySpectrogram = plotPcbSpectrogram( ...
            cfg, results.spectrogram.steady, "steady");
    end
end

if cfg.run.fullSpectrogram
    fprintf('\n--- Computing full-record spectrograms ---\n');
    results.spectrogram.full = computePcbSpectrogram( ...
        cfg, dataData);
    results.stageStatus.fullSpectrogram = true;

    if cfg.output.saveSpectrogramData
        saveSpectrogramData(cfg, results.spectrogram.full, "full");
    end
    if cfg.run.spectrogramPlots
        results.figures.fullSpectrogram = plotPcbSpectrogram( ...
            cfg, results.spectrogram.full, "full");
    end
end

%% Windowed PSD calculation and preview

if stages.needsWindowedPsd
    fprintf('\n--- Computing windowed PCB PSDs ---\n');
    results.windowedPsd = computeWindowedPcbPsd(cfg, analysisData);
    results.stageStatus.windowedPsd = true;
    fprintf('Computed %d PSD windows for %d channels\n', ...
        numel(results.windowedPsd.windowCenterTime), ...
        numel(results.windowedPsd.channels));
end

if cfg.run.windowedPsdPreview
    fprintf('\n--- Plotting windowed PSD preview ---\n');
    results.figures.windowedPsd = ...
        plotWindowedPcbPsd(cfg, results.windowedPsd);
    results.stageStatus.windowedPsdPreview = true;
end

%% Second-mode analysis

if cfg.run.secondModeAnalysis
    fprintf('\n--- Detecting second-mode peaks ---\n');
    results.secondMode = analyzeSecondModeWindows( ...
        cfg, results.windowedPsd);
    reportSecondModeWindows(results.secondMode);
    results.stageStatus.secondModeAnalysis = true;
end

%% Save packaged results

results.metadata.completedAt = datetime('now');

if cfg.run.saveResults
    results.files.results = string(cfg.output.resultsFile);
    results.stageStatus.resultsSaved = true;
    saveResultsFile(cfg, results);
end

fprintf('\nPCB analysis workflow completed\n');
end

function [cfg, configurationFile] = loadConfiguration(cfgInput)
configurationFile = "";
if isstruct(cfgInput)
    if ~isscalar(cfgInput)
        error('run_pcb_main:InvalidConfiguration', ...
            'The configuration must be a scalar struct.');
    end
    cfg = cfgInput;
    return
end

configurationFile = string(cfgInput);
if ~isscalar(configurationFile) || ~isfile(configurationFile)
    error('run_pcb_main:ConfigurationFileNotFound', ...
        'Configuration MAT-file not found: %s', configurationFile);
end
loaded = load(configurationFile, 'cfg');
if ~isfield(loaded, 'cfg') || ~isstruct(loaded.cfg)
    error('run_pcb_main:MissingCfgVariable', ...
        'Configuration MAT-file must contain a struct named cfg.');
end
cfg = loaded.cfg;
end

function stages = resolveStages(cfg)
stages = struct();
stages.needsWindowedPsd = cfg.run.windowedPsd || ...
    cfg.run.windowedPsdPreview || cfg.run.secondModeAnalysis;
stages.needsQuasiSteadyWindow = ...
    cfg.run.quasiSteadyTracePlots || cfg.run.steadySpectrogram || ...
    (stages.needsWindowedPsd && ...
    string(cfg.analysis.interval) == "quasiSteady");
end

function results = initializeResults(cfg, configurationFile, stages)
results = struct();
results.cfg = cfg;
results.configurationFile = configurationFile;
results.metadata = struct( ...
    'startedAt', datetime('now'), ...
    'matlabVersion', string(version));
results.stages = stages;
results.stageStatus = struct( ...
    'inputLoaded', false, ...
    'channelsExtracted', false, ...
    'fullTracePlots', false, ...
    'quasiSteadyDetection', false, ...
    'quasiSteadyTracePlots', false, ...
    'steadySpectrogram', false, ...
    'fullSpectrogram', false, ...
    'windowedPsd', false, ...
    'windowedPsdPreview', false, ...
    'secondModeAnalysis', false, ...
    'resultsSaved', false);
results.pcbData = [];
results.driverData = [];
results.triggerData = [];
results.dataData = [];
results.steadyDataData = [];
results.analysisData = [];
results.steadyWindow = [];
results.timingDiagnostics = [];
results.spectrogram = struct('steady', [], 'full', []);
results.windowedPsd = [];
results.secondMode = [];
results.figures = struct();
results.files = struct();
end

function steadyWindow = emptySteadyWindow()
steadyWindow = struct('time', [NaN NaN], ...
    'startTime', NaN, 'endTime', NaN);
end

function selectedData = selectAnalysisData( ...
    cfg, fullData, steadyData, steadyWindow)
switch string(cfg.analysis.interval)
    case "full"
        selectedData = fullData;
    case "manual"
        selectedData = cropChannelData( ...
            fullData, cfg.analysis.manualTimeRange);
    case "quasiSteady"
        if all(isfinite(steadyWindow.time))
            selectedData = steadyData;
        else
            selectedData = fullData;
        end
end
end

function croppedData = cropChannelData(data, timeRange)
croppedData = data;
for channelIndex = 1:numel(data.channels)
    time = data.time{channelIndex};
    signal = data.signal{channelIndex};
    mask = time >= timeRange(1) & time <= timeRange(2);
    if ~any(mask)
        error('run_pcb_main:EmptyAnalysisInterval', ...
            'Time range does not overlap channel %s.', ...
            data.channels(channelIndex));
    end
    croppedData.time{channelIndex} = time(mask);
    croppedData.signal{channelIndex} = signal(mask);
end
end

function printTimingSummary(steadyWindow, diagnostics)
fprintf('Estimated quasi-steady interval: %.6f to %.6f s\n', ...
    steadyWindow.startTime, steadyWindow.endTime);
fprintf('Estimated duration: %.6f s\n', ...
    steadyWindow.endTime - steadyWindow.startTime);
fprintf('Trigger threshold time: %.6f s\n', diagnostics.triggerTime);
fprintf('PCB analysis channel: %s\n', diagnostics.pcbChannel);
end

function saveSpectrogramData(cfg, spectrogramResults, label)
folder = cfg.output.spectrogramFolder;
if ~isfolder(folder)
    mkdir(folder);
end
fileName = fullfile(folder, label + "SpectrogramResults.mat");
save(fileName, 'spectrogramResults');
fprintf('Spectrogram results saved to %s\n', fileName);
end

function saveResultsFile(cfg, results)
fileName = string(cfg.output.resultsFile);
folder = fileparts(fileName);
if strlength(folder) > 0 && ~isfolder(folder)
    mkdir(folder);
end
results.figures = struct();
if ~cfg.output.saveRawPcbDataInResults
    results.pcbData = [];
end
save(fileName, 'results', '-v7.3');
fprintf('PCB analysis results saved to %s\n', fileName);
end
