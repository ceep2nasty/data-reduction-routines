function [driverData, triggerData, dataData] = ...
    extractPcbChannels(cfg, pcbData)
%EXTRACTPCBCHANNELS Extract channels using relative or original source time.

availableChannels = string(pcbData.channels(:));
requestedChannels = [string(cfg.channels.driver); ...
    string(cfg.channels.trigger(:)); string(cfg.channels.data(:))];
missingChannels = setdiff(requestedChannels, availableChannels);
if ~isempty(missingChannels)
    error('extractPcbChannels:MissingChannels', ...
        'Requested channel(s) not found: %s', ...
        strjoin(missingChannels, ', '));
end

driverData = extractGroup( ...
    string(cfg.channels.driver), cfg.channels.driverSamplingRate, ...
    pcbData);
triggerData = extractGroup( ...
    string(cfg.channels.trigger(:)), cfg.channels.triggerSamplingRate, ...
    pcbData);
dataData = extractGroup( ...
    string(cfg.channels.data(:)), cfg.channels.dataSamplingRate, ...
    pcbData);

timeOrigin = min([firstTimes(driverData), ...
    firstTimes(triggerData), firstTimes(dataData)]);
if isfield(cfg, 'analysis') && isfield(cfg.analysis, 'timeReference') && ...
        string(cfg.analysis.timeReference) == "absolute"
    timeOrigin = 0;
end
driverData.time = shiftTimes(driverData.time, timeOrigin);
triggerData.time = shiftTimes(triggerData.time, timeOrigin);
dataData.time = shiftTimes(dataData.time, timeOrigin);
end

function group = extractGroup(channels, samplingRate, pcbData)
group = struct();
group.channels = channels;
group.time = cell(size(channels));
group.signal = cell(size(channels));
group.samplingRate = samplingRate;
group.units = "V";

availableChannels = string(pcbData.channels(:));
for channelIndex = 1:numel(channels)
    sourceIndex = find(availableChannels == channels(channelIndex), 1);
    if isfield(pcbData.signalData, 'units')
        units = string(pcbData.signalData(sourceIndex).units);
        if channelIndex > 1
            assert(units == group.units, 'extractPcbChannels:MixedUnits', ...
                'Selected channels must share signal units.');
        end
        group.units = units;
    end
    group.time{channelIndex} = ...
        pcbData.signalData(sourceIndex).time(:);
    group.signal{channelIndex} = ...
        pcbData.signalData(sourceIndex).signal(:);
    if numel(group.time{channelIndex}) ~= numel(group.signal{channelIndex})
        error('extractPcbChannels:TimeSignalMismatch', ...
            'Channel %s has different time and signal lengths.', ...
            channels(channelIndex));
    end
end
end

function values = firstTimes(data)
values = nan(1, numel(data.time));
for index = 1:numel(data.time)
    values(index) = data.time{index}(1);
end
end

function shiftedTimes = shiftTimes(times, timeOrigin)
shiftedTimes = times;
for index = 1:numel(times)
    shiftedTimes{index} = times{index} - timeOrigin;
end
end
