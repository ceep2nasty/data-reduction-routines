function pcbData = loadPcbData(cfg)
%LOADPCBDATA Load and normalize a converted PCB MAT-file.

filePath = string(cfg.input.file);
loadedData = load(filePath);

if isfield(loadedData, 'pcbData')
    pcbData = loadedData.pcbData;
elseif isfield(loadedData, 'blockData')
    pcbData = loadedData.blockData;
elseif isfield(loadedData, char(cfg.input.variable))
    legacyData = loadedData.(char(cfg.input.variable));
    pcbData = normalizeLegacyPerceptionData(legacyData, cfg);
else
    error('loadPcbData:MissingVariable', ...
        'Expected pcbData, blockData, or %s in %s.', ...
        cfg.input.variable, filePath);
end

if isstruct(pcbData) && ~isfield(pcbData, 'channels') && ...
        all(isfield(pcbData, {'time', 'channel'}))
    pcbData = normalizeLegacyPerceptionData(pcbData, cfg);
end

validateNormalizedData(pcbData, filePath);
pcbData.channels = string(pcbData.channels(:));
pcbData.signalData = pcbData.signalData(:);
fprintf('Loaded PCB data: %s\n', filePath);
end

function pcbData = normalizeLegacyPerceptionData(legacyData, cfg)
% Legacy Perception_Raw files contain one struct per recorder with a time
% vector and a channel matrix. Convert that layout to channels/signalData.

if ~isstruct(legacyData) || ...
        ~all(isfield(legacyData, {'time', 'channel'}))
    error('loadPcbData:UnsupportedLegacyLayout', ...
        ['The configured legacy variable does not contain recorder ', ...
        'structs with time and channel fields.']);
end

recorderLabels = string(cfg.channels.recorderLabels(:));
if numel(legacyData) > numel(recorderLabels)
    error('loadPcbData:RecorderLabelMismatch', ...
        ['The legacy file contains %d recorders but only %d recorder ', ...
        'labels are configured.'], numel(legacyData), numel(recorderLabels));
end

channelCount = sum(arrayfun( ...
    @(recorder) size(recorder.channel, 2), legacyData));
channels = strings(channelCount, 1);
signalData = repmat(struct('time', [], 'signal', []), channelCount, 1);
outputIndex = 0;

for recorderIndex = 1:numel(legacyData)
    channelMatrix = legacyData(recorderIndex).channel;
    recorderTime = legacyData(recorderIndex).time;
    if isempty(channelMatrix)
        continue
    end

    sampleCount = size(channelMatrix, 1);
    if isvector(recorderTime)
        recorderTime = recorderTime(:);
        if numel(recorderTime) ~= sampleCount
            error('loadPcbData:LegacyTimeMismatch', ...
                'Recorder %d time and channel lengths differ.', ...
                recorderIndex);
        end
    elseif size(recorderTime, 1) ~= sampleCount
        error('loadPcbData:LegacyTimeMismatch', ...
            'Recorder %d time and channel lengths differ.', recorderIndex);
    end

    for channelIndex = 1:size(channelMatrix, 2)
        outputIndex = outputIndex + 1;
        channels(outputIndex) = recorderLabels(recorderIndex) + ...
            compose('%02d', channelIndex);
        if isvector(recorderTime) || size(recorderTime, 2) == 1
            channelTime = recorderTime;
        elseif channelIndex <= size(recorderTime, 2)
            channelTime = recorderTime(:, channelIndex);
        else
            error('loadPcbData:LegacyTimeMismatch', ...
                'Recorder %d has no time column for channel %d.', ...
                recorderIndex, channelIndex);
        end
        signalData(outputIndex).time = channelTime;
        signalData(outputIndex).signal = channelMatrix(:, channelIndex);
    end
end

pcbData = struct('channels', channels, 'signalData', signalData);
end

function validateNormalizedData(pcbData, filePath)
if ~isstruct(pcbData) || ~isfield(pcbData, 'channels') || ...
        ~isfield(pcbData, 'signalData') || ...
        numel(pcbData.channels) ~= numel(pcbData.signalData)
    error('loadPcbData:InvalidNormalizedData', ...
        'Unsupported PCB data layout in %s.', filePath);
end
end
