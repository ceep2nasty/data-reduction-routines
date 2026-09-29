function run_pcb_campaign(interval, onlyCase)
%RUN_PCB_CAMPAIGN Save the eight named January/February cases under pcb_outputs.
% MAT files live at case root; figures are grouped by product.
if nargin < 1, interval = "quasiSteady"; end
if nargin < 2, onlyCase = ""; end
here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(here, 'functions'));
root = "C:/Users/coled/Notre Dame/heatedCone_F26";
files = [dir(fullfile(root, 'AFOSR_Heated_Cone_Jan2026', 'PCB_Data', '*', '*.txt')); ...
    dir(fullfile(root, 'AFOSR_Heated_Cone_Feb2026', '*', '*.pnrf'))];
oldVisibility = get(groot, 'defaultFigureVisible');
cleanup = onCleanup(@() set(groot, 'defaultFigureVisible', oldVisibility));
set(groot, 'defaultFigureVisible', 'off');
for k = 1:numel(files)
    source = fullfile(files(k).folder, files(k).name);
    [~, caseName] = fileparts(files(k).folder);
    january = contains(source, 'Jan2026');
    if january, prefix = "jan_"; else, prefix = "feb_"; end
    name = prefix + caseName;
    if onlyCase ~= "" && name ~= onlyCase, continue; end
    out = fullfile(root, 'pcb_outputs', name);
    if ~isfolder(out), mkdir(out); end
    diary(fullfile(out, 'run.log'));
    try
        cfg = createPcbConfig();
        cfg.output.rootFolder = out;
        cfg.output.convertedDataFolder = out;
        cfg.output.tracePlotFolder = fullfile(out, 'figures', 'traces');
        cfg.output.spectrogramFolder = fullfile(out, 'figures', 'spectrograms');
        cfg.output.windowedPsdFolder = fullfile(out, 'figures', 'psd');
        cfg.output.resultsFile = fullfile(out, 'results.mat');
        cache = fullfile(out, 'pcbData.mat');
        if isfile(cache)
            s = load(cache, 'pcbData'); pcbData = s.pcbData; clear s
        elseif january
            cfg.input.source = "txt"; cfg.input.file = source;
            cfg.channels.driverSamplingRate = 2e6;
            cfg.channels.triggerSamplingRate = 2e6;
            pcbData = loadPcbData(cfg);
            save(cache, 'pcbData', '-v7.3');
        else
            cfg.input.rawFolder = string(files(k).folder);
            cfg.input.rawFileName = string(files(k).name);
            cfg.conversion.mode = "memory";
            pcbData = convertPnrfData(cfg);
            save(cache, 'pcbData', '-v7.3');
        end
        cfg.input.source = "mat"; cfg.input.file = cache;
        if january
            cfg.channels.data = ["D01", "D02", "C01", "D05", "D08", "D07", "D06"];
            cfg.channels.sensorNumbers = 2:8; cfg.channels.order = 2:8;
            cfg.channels.driverSamplingRate = 2e6;
            cfg.channels.triggerSamplingRate = 2e6;
            cfg.timing.pcbAnalysisChannel = "D05";
        else
            channels = string(pcbData.channels);
            cfg.channels.data = channels(startsWith(channels, "C") | startsWith(channels, "D"));
            cfg.timing.pcbAnalysisChannel = "C02";
        end
        clear pcbData
        cfg.analysis.interval = string(interval);
        cfg.analysis.manualTimeRange = [0.75 0.85];
        cfg.run.quasiSteadyTracePlots = interval == "quasiSteady";
        cfg.run.steadySpectrogram = interval == "quasiSteady";
        cfg.run.saveResults = true;
        cfg.output.saveWindowedPsdPlots = true;
        % Spectrogram arrays are already included in results.mat at case root.
        cfg.output.saveSpectrogramData = false;
        cfg.psd.windowDuration = 0.1; cfg.psd.windowStep = 0.1;
        cfg.psd.welchSegmentDuration = cfg.psd.windowDuration / 40;
        cfg.psd.previewWindowIndices = "all";
        cfg.psd.plotFrequencyBand = [0 800e3];
        cfg.secondMode.channelsExcluded = strings(0,1);
        save(fullfile(out, 'cfg.mat'), 'cfg', 'source');
        results = run_pcb_main(cfg);
        fprintf('COMPLETED %s: %d channels, %d PSD windows\n', name, ...
            numel(results.dataData.channels), numel(results.windowedPsd.windowCenterTime));
        clear results
    catch exception
        fprintf(2, 'FAILED %s: %s\n', name, getReport(exception, 'extended'));
    end
    close all; diary off
end
end
