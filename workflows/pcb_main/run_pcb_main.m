%% PCB analysis workflow
clear; close all; clc

%% Setup


repoDir = "C:\Users\coled\Notre Dame\Github\data-reduction-routines"; % path to repository you should be working in
scriptDir = fullfile(repoDir, "workflows", "pcb_main");
functionDir = fullfile(scriptDir, "functions");
globalDir = fullfile(repoDir, "matlab", "global");

assert(isfolder(scriptDir), ...
    "PCB workflow folder does not exist: " + scriptDir);

assert(isfolder(functionDir), ...
    "PCB functions folder does not exist: " + functionDir);

addpath(scriptDir);
addpath(functionDir);
addpath(genpath(globalDir));

fprintf("PCB analysis workflow started\n");

%% Configuration for converting or loading PCB data

cfg = struct();

% Determine if input source is .pnrf, or converted .mat

cfg.input.source = "mat"; % Set to "pnrf" for raw .pnrf files, or "mat" for converted .mat files

% Input configuration for raw .pnrf files
cfg.input.rawFolder = "C:\Users\coled\Notre Dame\test_pcb_workflow\raw_pnrf_files"; % Add path to folder containing raw .pnrf files
cfg.input.rawFileName = 'alignment_60psi_feb2026.pNRF'; % Add the exact raw .pnrf filename

% Input naming rules for recorder channels on DAQ

cfg.channels.labels = ["A", "B", "C", "D"]; % Add recorder labels in Perception recorder order
cfg.channels.maxPerRecorder = 8; % Add the maximum number of channels per recorder

cfg.output.dataFolder = "C:\Users\coled\Notre Dame\test_pcb_workflow\matlab_exports"; % Add path to folder where converted .mat files will be saved. This folder will be created if it does not exist.
cfg.conversion.mode = "disk" ; % Choose "memory" or "disk" for conversion mode. "memory" will return the converted data in memory, while "disk" will save the converted data to disk and return the file path.

% Input configuration for saved .mat files
cfg.input.file = fullfile(cfg.output.dataFolder, ...
    "alignment_60psi_feb2026.mat"); % Specify the converted MAT file.

fprintf("Conversion configuration loaded\n");
%% Convert or load PCB data
switch string(cfg.input.source)

    case "pnrf"
        fprintf("\n--- Converting PNRF data ---\n");
        pcbData = convertPnrfData(cfg);
        fprintf("PNRF data converted\n");
    case "mat"
        fprintf("\n--- Loading previous MAT data ---\n");
        pcbData = loadPcbData(cfg);
        
    otherwise
        error('run_pcb_main:InvalidInputSource', ...
            'cfg.input.source must be "pnrf" or "mat".');
end

%% Configuration for PCB channel extraction

% Extraction channel selection
cfg.analysis.driverChannel = "A01"; % Channel measuring driver tube pressure
cfg.analysis.triggerChannels = "B01"; % Add the channels used as trigger
cfg.analysis.dataChannels = ["C01", "C02", "D01"]; % Add the channels used for analysis

% Sampling Rates
cfg.analysis.driverSamplingRate = 250e3; % Sampling rate of the driver channel in Hz
cfg.analysis.triggerSamplingRate = 250e3; % Add the sampling rate of the trigger channels in Hz
cfg.analysis.dataSamplingRate = 2e6; % Add the sampling rate of the data

% Extraction outputs
cfg.analysis.extractChannels = true; % Set to true to label and extract the specified channels from the PCB data

fprintf("Channel extraction configuration loaded\n");
%% Run extraction on PCB data

if cfg.analysis.extractChannels
    fprintf("\n--- Extracting channels from PCB data ---\n");
    [driverData, triggerData, dataData] = extractPcbChannels(cfg, pcbData);
    fprintf("Channel extraction completed\n");
end

%% Configuration for PCB trace plotting

% Plotting preferences
cfg.plotting.fontSize = 25;
cfg.plotting.timeMarker = 0.72;
cfg.plotting.smoothData = true;
cfg.plotting.figurePosition = [10 10 1000 625];

% Trace plot outputs
cfg.analysis.runTracePlots = true; % Set to true to generate trace plots for the selected channels

% Choose whether to save the generated plots and specify the folder to save them
cfg.plotting.savePlots = false; % Set to true to save the generated plots
cfg.plotting.saveFolder = "C:\Users\coled\Notre Dame\test_pcb_workflow\trace_plots"; % Specify the folder to save the generated plots

%% Run trace plotting on extracted PCB data
if cfg.analysis.runTracePlots
    fprintf("\n--- Generating trace plots for extracted PCB data ---\n");
    figures = plotPcbTraces(cfg, dataData, triggerData, driverData);
    fprintf("Trace plotting completed\n");
end

%% Configuration for PCB spectrogram plotting

cfg.analysis.runSpectrogram = true;
cfg.analysis.plotSpectrogram = true;

cfg.analysis.saveSpectrogramFolder = "C:\Users\coled\Notre Dame\test_pcb_workflow\spectrogram_plots"; % Specify the folder to save the generated spectrogram plots
cfg.analysis.saveSpectrogram = true;

cfg.spectrogram.windowLength = 1000;
cfg.spectrogram.overlap = 0.75;
cfg.spectrogram.frequencyBand = [50e3 300e3];
cfg.spectrogram.colormap = "turbo";

%% Compute spectrogram on extracted PCB data
if cfg.analysis.runSpectrogram
    fprintf("\n--- Generating spectrograms for extracted PCB data ---\n");
    spectrogramResults = computePcbSpectrogram(cfg, dataData);
    fprintf("Spectrogram computation completed\n");
end

%% Plot spectrograms for extracted PCB data
if cfg.analysis.plotSpectrogram
    fprintf("\n--- Plotting spectrograms for extracted PCB data ---\n");
    spectrogramFig =plotPcbSpectrogram(cfg, spectrogramResults);
    fprintf("Spectrogram plotting completed\n");
end