function cfg = createPcbConfig(outputFile)
%CREATEPCBCONFIG Create the complete default PCB workflow configuration.
%
%   cfg = createPcbConfig()
%   cfg = createPcbConfig(outputFile)
%
% With an output filename, the function saves a MAT-file containing cfg.

if nargin < 1
    outputFile = "";
end

cfg = struct();
cfg.version = 1;

%% Input data

% "pnrf" converts a Perception recording; "mat" loads converted data.
cfg.input.source = "pnrf";
cfg.input.rawFolder = ...
    "C:\Users\coled_agkeohi\Notre Dame\PCB_test_workflow_data\raw_pnrf_files";
cfg.input.rawFileName = "alignment_60psi_feb2026.pNRF";
cfg.input.file = ...
    "C:\Users\coled_agkeohi\Notre Dame\PCB_test_workflow_data\matlab_exports\alignment_60psi_feb2026.mat";

% Legacy MAT files may store this variable instead of pcbData.
cfg.input.variable = "Perception_Raw";

% The PNRF reader requires Windows and the Perception ActiveX toolkit.
% "disk" also saves normalized pcbData; "memory" only returns it.
cfg.conversion.mode = "disk";

%% MATLAB paths

% Repository paths are discovered automatically. Add only external helper
% directories required for a particular installation or campaign.
cfg.paths.additionalFolders = strings(0, 1);

%% Recorder layout and analysis channels

% Recorder labels must match Perception recorder order.
cfg.channels.recorderLabels = ["A", "B", "C", "D"];
cfg.channels.maxPerRecorder = 8;

cfg.channels.driver = "A01";
cfg.channels.trigger = "B01";
cfg.channels.data = ["C01", "C02", "D01"];

% Sampling rates are in Hz.
cfg.channels.driverSamplingRate = 250e3;
cfg.channels.triggerSamplingRate = 250e3;
cfg.channels.dataSamplingRate = 2e6;

%% Products to generate

% Foundational stages such as loading and channel extraction run
% automatically. Requested products automatically enable prerequisites.
cfg.run.fullTracePlots = true;        % Plot the complete time histories.
cfg.run.quasiSteadyTracePlots = true; % Detect and plot the steady interval.
cfg.run.steadySpectrogram = true;     % Compute the steady-interval STFT.
cfg.run.fullSpectrogram = true;       % Compute the full-record STFT.
cfg.run.spectrogramPlots = true;      % Plot each requested STFT result.
cfg.run.windowedPsd = true;           % Return the windowed Welch PSD array.
cfg.run.windowedPsdPreview = true;    % Plot selected PSD windows.
cfg.run.secondModeAnalysis = true;    % Detect one peak per window/channel.
cfg.run.saveResults = false;          % Save the returned results structure.
cfg.run.closeFiguresAtStart = true;   % Close existing figures before running.

%% Analysis interval

% "quasiSteady" uses automatic timing detection, "full" uses the complete
% record, and "manual" uses cfg.analysis.manualTimeRange.
cfg.analysis.interval = "quasiSteady";
cfg.analysis.manualTimeRange = [0 1];

% Choose "useFullRecord" or "error" when automatic detection fails.
cfg.analysis.onInvalidQuasiSteadyWindow = "useFullRecord";

%% Quasi-steady timing detection

% Trigger voltage detection.
cfg.timing.triggerThreshold = 2.5; % Voltage that starts a trigger candidate.
cfg.timing.triggerHysteresis = 2.3; % Voltage required during the hold period.
cfg.timing.triggerHoldTime = 0.002; % Required trigger duration [s].

% Driver flatness detection. Durations are seconds; slope and noise
% thresholds use the calibrated driver signal units used by the detector.
cfg.timing.driverFlatWindow = 0.050; % Local line-fit duration [s].
cfg.timing.driverFlatHoldTime = 0.050; % Required flat duration [s].
cfg.timing.driverFlatEvaluationInterval = 0.001; % Detector update spacing [s].
cfg.timing.driverFlatSlopeThreshold = 0.10; % Largest flat absolute slope.
cfg.timing.driverFlatNoiseThreshold = 0.010; % Largest flat fit residual std.
cfg.timing.driverDescendingSlopeThreshold = 0.10; % Falling-state slope size.

% PCB fluctuation detection. pcbAnalysisChannel must be one of the selected
% cfg.channels.data channels.
cfg.timing.pcbAnalysisChannel = "C02"; % Trusted channel used for timing.
cfg.timing.pcbFluctuationWindow = 0.002; % Local fluctuation RMS window [s].
cfg.timing.pcbReferenceDuration = 0.050; % Baseline duration [s].
cfg.timing.pcbReferenceGap = 0.010; % Gap before trigger for baseline [s].
cfg.timing.pcbMinimumStartDuration = 0.050; % Required started duration [s].
cfg.timing.pcbUnstartHoldTime = 0.020; % Required high-fluctuation time [s].
cfg.timing.pcbModerateLowerRatio = 1.5; % Baseline ratio marking started flow.
cfg.timing.pcbUnstartRatio = 4.0; % Baseline ratio marking an unstart.

%% Trace and general plotting

cfg.plotting.fontSize = 25; % Text size for trace plots.
cfg.plotting.smoothData = true; % Smooth copies used only for trace display.
cfg.plotting.figurePosition = [10 10 1000 625]; % Figure pixel rectangle.

%% Spectrogram calculation

% windowLength is samples. overlap is a fraction from 0 through less than 1.
cfg.spectrogram.windowLength = 1000; % STFT samples per segment.
cfg.spectrogram.overlap = 0.75; % Fractional overlap between segments.
cfg.spectrogram.frequencyBand = [50e3 800e3]; % Calculated/plotted band [Hz].
cfg.spectrogram.colormap = "turbo"; % Spectrogram display colors.

%% Windowed Welch PSD calculation

% One spectrum is reported for every windowStep seconds. Each spectrum uses
% overlapping Welch segments of welchSegmentDuration seconds.
cfg.psd.windowDuration = 0.050; % Time represented by one reported PSD [s].
cfg.psd.windowStep = 0.050; % Time between reported PSD starts [s].
cfg.psd.welchSegmentDuration = cfg.psd.windowDuration / 40; % Segment [s].
cfg.psd.welchOverlap = 0.50; % Fractional Welch segment overlap.
cfg.psd.detrend = "linear"; % "linear", "constant", or "none".

% Preview controls do not affect numerical PSD results.
cfg.psd.plotFrequencyBand = [50e3 300e3]; % Preview x-axis limits [Hz].
cfg.psd.previewWindowIndices = 4:5; % Positive indices or "all".

%% Second-mode peak detection

% Excluded channels remain in trace and PSD plots.
cfg.secondMode.channelsExcluded = "C01"; % Skip noisy channels in detection.
cfg.secondMode.frequencyBand = [100e3 180e3]; % Peak search band [Hz].
cfg.secondMode.minimumProminenceDb = 4; % Minimum local separation [dB].
cfg.secondMode.minimumWidth = 10e3; % Minimum findpeaks width [Hz].
cfg.secondMode.fitHalfWidth = 20e3; % Parabola region around peak [Hz].


%% PDF report

cfg.report.title = "PCB Test Report";
cfg.report.author = "Cole Peters";

% A second-mode detection must persist this many PSD windows before it is
% treated as a real appearance or disappearance.
cfg.report.minimumAppearanceWindows = 2;
cfg.report.minimumDisappearanceWindows = 2;

% Bridge isolated missed detections surrounded by valid detections.
cfg.report.bridgeMissingWindows = 1;

% Frequency limits for the representative PSD plot.
cfg.report.psdFrequencyBand = cfg.psd.plotFrequencyBand;

% Keep report figures open after generating the PDF.
cfg.report.keepFiguresOpen = false;


%% Output files

cfg.output.rootFolder = ...
    "C:\Users\coled_agkeohi\Notre Dame\PCB_test_workflow_data";
    cfg.output.reportFile = fullfile( ...
    cfg.output.rootFolder, ...
    "pcb_test_report.pdf");
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

cfg.output.saveTracePlots = true; % Save enabled full/steady trace figures.
cfg.output.saveSpectrogramData = true; % Save numerical STFT MAT files.
cfg.output.saveSpectrogramPlots = true; % Save enabled STFT figures.
cfg.output.saveWindowedPsdPlots = false; % Save requested PSD previews.

% Raw pcbData can be large. It remains in the returned results but is
% omitted from a saved results file unless this is true.
cfg.output.saveRawPcbDataInResults = false;

%% Optionally save the configuration

if strlength(string(outputFile)) > 0
    outputFile = string(outputFile);
    if ~endsWith(outputFile, ".mat", 'IgnoreCase', true)
        outputFile = outputFile + ".mat";
    end

    outputFolder = fileparts(outputFile);
    if strlength(outputFolder) > 0 && ~isfolder(outputFolder)
        mkdir(outputFolder);
    end

    save(outputFile, 'cfg');
    fprintf('PCB configuration saved to %s\n', outputFile);
end
end
