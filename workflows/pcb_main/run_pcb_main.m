%% PCB analysis workflow
clear; close all; clc

%% Setup
scriptDir = fileparts(mfilename("fullpath"));
functionDir = fullfile(scriptDir, "functions");
addpath(functionDir);


%% Configuration

cfg = struct();

% Determine if input source is .pnrf, or converted .mat

cfg.input.source = "pnrf"; % Set to "pnrf" for raw .pnrf files, or "mat" for converted .mat files

% Input configuration for raw .pnrf files
cfg.input.rawFolder = 'C:\Users\coled_agkeohi\Notre Dame\PCB_test_workflow_data\raw_pnrf_files'; % Add path to folder containing raw .pnrf files
cfg.input.blocks = { 'alignment_60psi_feb2026'}; % Add cell array of block names corresponding to the raw .pnrf files
cfg.output.dataFolder = 'C:\Users\coled_agkeohi\Notre Dame\PCB_test_workflow_data\matlab_exports'; % Add path to folder where converted .mat files will be saved. This folder will be created if it does not exist.
cfg.conversion.mode = "both" ; % Choose "memory", "disk", or "both"

% Input configuration for the exported .mat files
cfg.input.variable = "Perception_Raw"; % Specify the variable name in the .mat file containing the raw perception data


%% Convert or load PCB data
switch string(cfg.input.source)

    case "pnrf"
        fprintf("\n--- Converting PNRF data ---\n");
        conversion = convertPnrfData(cfg);

        if ismember(string(cfg.conversion.mode), ["disk", "both"])
            cfg.input.file = conversion(1).outputFile;
            pcbData = loadPcbData(cfg);
        else
            pcbData = struct();
            pcbData.raw = conversion(1).raw;
            pcbData.sourceFile = "memory";
            pcbData.sourceVariable = cfg.input.variable;
        end

    case "mat"
        fprintf("\n--- Loading previous MAT data ---\n");
        pcbData = loadPcbData(cfg);
        
    otherwise
        error('run_pcb_main:InvalidInputSource', ...
            'cfg.input.source must be "pnrf" or "mat".');
end
cfg.execution.extractChannels = false; % Set to true to extract channels from the PCB data
cfg.execution.computePsd = false; % Set to true to compute the power spectral density of the PCB data