function model = buildPcbReportModel(results)
%BUILDPCBREPORTMODEL Calculate all values displayed in the PDF report.

if ~isstruct(results) || ~isscalar(results)
    error('buildPcbReportModel:InvalidResults', ...
        'results must be a scalar structure.');
end

requiredFields = [ ...
    "cfg", ...
    "dataData", ...
    "driverData", ...
    "triggerData", ...
    "steadyWindow", ...
    "timingDiagnostics", ...
    "windowedPsd", ...
    "secondMode"];

for fieldName = requiredFields
    if ~isfield(results, fieldName)
        error('buildPcbReportModel:MissingField', ...
            'results.%s is required.', fieldName);
    end
end

cfg = results.cfg;

model = struct();
model.title = string(cfg.report.title);
model.author = string(cfg.report.author);
model.generatedAt = datetime('now');

model.sourceFile = determineSourceFile(cfg);
model.channels = string(results.dataData.channels(:));
model.channelCount = numel(model.channels);
model.dataSamplingRate = results.dataData.samplingRate;
model.driverSamplingRate = results.driverData.samplingRate;
model.triggerSamplingRate = results.triggerData.samplingRate;

[recordStart, recordEnd] = commonTimeExtent(results.dataData);

model.recordStartTime = recordStart;
model.recordEndTime = recordEnd;
model.totalRecordDuration = recordEnd - recordStart;

steadyWindow = results.steadyWindow;

model.hasQuasiSteadyWindow = ...
    isstruct(steadyWindow) && ...
    isfield(steadyWindow, 'startTime') && ...
    isfield(steadyWindow, 'endTime') && ...
    isfinite(steadyWindow.startTime) && ...
    isfinite(steadyWindow.endTime) && ...
    steadyWindow.endTime > steadyWindow.startTime;

if model.hasQuasiSteadyWindow
    model.quasiSteadyStartTime = steadyWindow.startTime;
    model.quasiSteadyEndTime = steadyWindow.endTime;
    model.quasiSteadyDuration = ...
        steadyWindow.endTime - steadyWindow.startTime;
    model.quasiSteadyFraction = ...
        model.quasiSteadyDuration / model.totalRecordDuration;
else
    model.quasiSteadyStartTime = NaN;
    model.quasiSteadyEndTime = NaN;
    model.quasiSteadyDuration = NaN;
    model.quasiSteadyFraction = NaN;
end

model.triggerTime = NaN;

if isstruct(results.timingDiagnostics) && ...
        isfield(results.timingDiagnostics, 'triggerTime')
    model.triggerTime = ...
        results.timingDiagnostics.triggerTime;
end

driverFlatWindows = struct( ...
    'startTime', {}, ...
    'endTime', {});

if isstruct(results.timingDiagnostics) && ...
        isfield(results.timingDiagnostics, 'driverFlatWindows')
    driverFlatWindows = ...
        results.timingDiagnostics.driverFlatWindows;
end

model.driverFlatWindows = driverFlatWindows;

model.representativePsd = selectRepresentativePsdWindow( ...
    results.windowedPsd, ...
    results.steadyWindow, ...
    driverFlatWindows);

model.secondMode = summarizeSecondMode( ...
    results.secondMode, ...
    cfg.report);

model.secondModeChannelCount = numel(model.secondMode);

statuses = string({model.secondMode.status});
model.channelsWithSecondMode = ...
    nnz(statuses ~= "not detected");

model.psdWindowCount = ...
    numel(results.windowedPsd.windowCenterTime);

model.warnings = strings(0, 1);

if ~model.hasQuasiSteadyWindow
    model.warnings(end + 1) = ...
        "No valid quasi-steady interval was detected.";
end

if model.representativePsd.usedFallback
    model.warnings(end + 1) = ...
        "Representative PSD selection required an overlap fallback.";
end

if model.channelsWithSecondMode == 0
    model.warnings(end + 1) = ...
        "No persistent second-mode detections were identified.";
end
end

function sourceFile = determineSourceFile(cfg)
sourceFile = "";

if string(cfg.input.source) == "pnrf"
    sourceFile = fullfile( ...
        string(cfg.input.rawFolder), ...
        string(cfg.input.rawFileName));
elseif isfield(cfg.input, 'file')
    sourceFile = string(cfg.input.file);
end
end

function [commonStart, commonEnd] = commonTimeExtent(data)
channelCount = numel(data.channels);
startTimes = nan(channelCount, 1);
endTimes = nan(channelCount, 1);

for channelIndex = 1:channelCount
    time = data.time{channelIndex}(:);

    if isempty(time)
        error('buildPcbReportModel:EmptyChannel', ...
            'Channel %s has no time samples.', ...
            data.channels(channelIndex));
    end

    startTimes(channelIndex) = time(1);
    endTimes(channelIndex) = time(end);
end

commonStart = max(startTimes);
commonEnd = min(endTimes);

if commonEnd <= commonStart
    error('buildPcbReportModel:NoCommonRecord', ...
        'The PCB channels have no common time interval.');
end
end