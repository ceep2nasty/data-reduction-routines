%% PCB analysis workflow
clear; close all; clc

%% Setup

repoDir = "C:\Users\coled\Notre Dame\Github\data-reduction-routines"; % path to repository you should be working in
scriptDir = fullfile(repoDir, "workflows", "pcb_main");
functionDir = fullfile(scriptDir, "functions");

assert(isfolder(scriptDir), ...
    "PCB workflow folder does not exist: " + scriptDir);

assert(isfolder(functionDir), ...
    "PCB functions folder does not exist: " + functionDir);

addpath(scriptDir);
addpath(functionDir);

fprintf("PCB analysis workflow started\n");

%% Configuration

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


fprintf("Configuration loaded\n");
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
cfg.execution.extractChannels = false; % Set to true to extract channels from the PCB data
cfg.execution.computePsd = false; % Set to true to compute the power spectral density of the PCB data