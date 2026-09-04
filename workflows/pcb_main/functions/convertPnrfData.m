function pcbData = convertPnrfData(cfg)
%CONVERTPNRFDATA Convert Perception PNRF recordings to MAT-files.
% Author: Cole Peters
% Date created: 09/03/2026
% Modified from earlier version created by Ben Bemis
%  The Perception pNRF reader toolkit and MATLAB ActiveX support are required
% on Windows. The output format is compatible with loadPcbData.

if ~isfield(cfg, 'conversion') || ~isfield(cfg.conversion, 'mode')
    error('convertPnrfData:MissingConversionMode', ...
        'Configuration must define cfg.conversion.mode.');
end

conversionMode = string(cfg.conversion.mode);

if ~isscalar(conversionMode) || ...
        ~ismember(conversionMode, ["memory", "disk"])
    error('convertPnrfData:InvalidMode', ...
        'cfg.conversion.mode must be "memory", "disk"');
end

saveConvertedData = ismember(conversionMode, "disk");


if ~isfield(cfg, 'input') || ~isfield(cfg.input, 'rawFolder')
    error('convertPnrfData:MissingRawFolder', ...
        'Configuration must define cfg.input.rawFolder.');
end
if ~isfield(cfg, 'channels') || ~isfield(cfg.channels, 'labels') || ...
        isempty(cfg.channels.labels)
    error('convertPnrfData:MissingRecorderLabels', ...
        'Configuration must define cfg.channels.labels.');
end
if ~isfield(cfg.channels, 'maxPerRecorder') || ...
        ~isscalar(cfg.channels.maxPerRecorder) || ...
        cfg.channels.maxPerRecorder < 1 || ...
        cfg.channels.maxPerRecorder ~= fix(cfg.channels.maxPerRecorder)
    error('convertPnrfData:InvalidChannelsPerRecorder', ...
        'cfg.channels.maxPerRecorder must be a positive integer.');
end
if ~isfield(cfg.input, 'rawFileName') || isempty(cfg.input.rawFileName)
    error('convertPnrfData:MissingRawFileName', ...
        'Configuration must define cfg.input.rawFileName.');
end
if saveConvertedData && ...
        (~isfield(cfg, 'output') || ~isfield(cfg.output, 'dataFolder'))
    error('convertPnrfData:MissingDataFolder', ...
        'Configuration must define cfg.output.dataFolder if cfg.conversion.mode is "disk".');
end

rawFolder = char(cfg.input.rawFolder);
rawFileName = char(cfg.input.rawFileName);
recorderLabels = string(cfg.channels.labels(:));
maxRecorders = numel(recorderLabels);
maxChannels = cfg.channels.maxPerRecorder;

if numel(unique(recorderLabels)) ~= maxRecorders
    error('convertPnrfData:DuplicateRecorderLabels', ...
        'cfg.channels.labels must contain unique recorder labels.');
end

if ~isfolder(rawFolder)
    error('convertPnrfData:RawFolderNotFound', ...
        'PNRF input folder not found: %s', rawFolder);
end

if saveConvertedData && ~isfolder(cfg.output.dataFolder)
    mkdir(cfg.output.dataFolder);
end

filePath = fullfile(rawFolder, rawFileName);
if ~isfile(filePath)
    error('convertPnrfData:RawFileNotFound', ...
        'PNRF file not found: %s', filePath);
end

signalCount = maxRecorders * maxChannels;
emptySignalData = struct('time', [], 'signal', []);
pcbData = struct( ...
    'channels', strings(signalCount, 1), ...
    'signalData', repmat(emptySignalData, signalCount, 1));
recordedSignalCount = 0;

reader = actxserver('Perception.Loaders.pNRF');
cleanupReader = onCleanup(@() delete(reader));

fprintf('Converting PNRF file: %s\n', rawFileName);
data = reader.LoadRecording(filePath);
for recorderIndex = 1:maxRecorders
    for channelIndex = 1:maxChannels
        recorder = data.Recorders.Item(recorderIndex);
        if isempty(recorder)
            continue
        end

        channels = recorder.Channels;
        channel = channels.Item(channelIndex);
        if isempty(channel)
            continue
        end

        interfaceData = channel.DataSource(3);
        sweeps = interfaceData.Sweeps;
        segments = interfaceData.Data(sweeps.StartTime, sweeps.EndTime);
        segment = segments.Item(1);
        numberOfSamples = segment.NumberOfSamples;
        waveformData = segment.Waveform(5, 1, numberOfSamples, 1)';
        if ~any(waveformData)
            continue
        end

        endTime = segment.StartTime + ...
            (numberOfSamples - 1) * segment.SampleInterval;
        time = segment.StartTime:segment.SampleInterval:endTime;
        recordedSignalCount = recordedSignalCount + 1;
        pcbData.channels(recordedSignalCount) = recorderLabels(recorderIndex) + ...
            compose('%02d', channelIndex);
        pcbData.signalData(recordedSignalCount).time = time;
        pcbData.signalData(recordedSignalCount).signal = waveformData;
    end
end

pcbData.channels = pcbData.channels(1:recordedSignalCount);
pcbData.signalData = pcbData.signalData(1:recordedSignalCount);

if saveConvertedData
    [~, baseName] = fileparts(rawFileName);
    outputPath = fullfile(cfg.output.dataFolder, [baseName '.mat']);
    save(outputPath, 'pcbData', '-v7.3');
    fprintf('Saved converted data to: %s\n', outputPath);
end

clear cleanupReader reader


