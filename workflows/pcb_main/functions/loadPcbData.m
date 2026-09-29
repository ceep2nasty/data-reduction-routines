function pcbData = loadPcbData(cfg)
%LOADPCBDATA Load a converted MAT-file or Perception text export.

filePath = string(cfg.input.file);
if isfield(cfg.input, 'source') && string(cfg.input.source) == "txt"
    pcbData = readTextExport(filePath);
    rates = [cfg.channels.driverSamplingRate, ...
        cfg.channels.triggerSamplingRate, cfg.channels.dataSamplingRate];
    % NaN is the sharing exporter's request to infer the rate from time.
    rates = rates(~isnan(rates));
    assert(all(abs(rates / pcbData.exportSamplingRate - 1) < 1e-3), ...
        'loadPcbData:SamplingRateMismatch', ...
        'Configured rates must match the text export grid (%.9g Hz).', ...
        pcbData.exportSamplingRate);
else
    pcbData = readMatFile(filePath, cfg);
end

validateNormalizedData(pcbData, filePath);
pcbData.channels = string(pcbData.channels(:));
pcbData.signalData = pcbData.signalData(:);
fprintf('Loaded PCB data: %s\n', filePath);
end

function pcbData = readMatFile(filePath, cfg)
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

end

function pcbData = readTextExport(filePath)
fid = fopen(filePath, 'rt');
assert(fid >= 0, 'loadPcbData:OpenFailed', 'Cannot open %s.', filePath);
cleanup = onCleanup(@() fclose(fid));
header = "";
while ~feof(fid)
    line = string(fgetl(fid));
    if startsWith(line, "Time" + char(9))
        header = line;
        break
    end
end
assert(header ~= "", 'loadPcbData:MissingHeader', 'No Time/channel header found.');
names = split(strtrim(header), char(9));
columns = find(startsWith(names, "Ch "));
channels = extractAfter(names(columns), "Ch ");
assert(~isempty(channels) && numel(unique(channels)) == numel(channels), ...
    'loadPcbData:InvalidTextChannels', 'Expected unique analog channel names.');
fgetl(fid); % Units row.
formats = repmat("%*f", size(names));
formats([1; columns]) = "%f";
values = textscan(fid, char(join(formats, "")), ...
    'Delimiter', '\t', 'ReturnOnError', false);
time = values{1};
dt = median(diff(time));
assert(numel(time) > 1 && all(isfinite(time)) && dt > 0 && ...
    all(abs(diff(time) - dt) < dt * 1e-3), ...
    'loadPcbData:InvalidTextTime', 'Expected finite, uniformly increasing time.');
signalData = repmat(struct('time', time, 'signal', []), numel(channels), 1);
for k = 1:numel(channels)
    signal = values{k+1};
    assert(numel(signal) == numel(time) && all(isfinite(signal)), ...
        'loadPcbData:InvalidTextSignal', 'Incomplete or nonfinite channel %s.', channels(k));
    signalData(k).signal = signal;
end
% Preserve all analog inputs; low-amplitude noise does not prove disconnection.
pcbData = struct('channels', channels, 'signalData', signalData, ...
    'exportSamplingRate', 1/dt);
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
