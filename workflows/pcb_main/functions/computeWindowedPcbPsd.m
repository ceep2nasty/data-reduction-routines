function psdResults = computeWindowedPcbPsd(cfg, dataData)
%COMPUTEWINDOWEDPCBPSD Compute one Welch PSD per time window and channel.
%
% Required configuration:
%   cfg.psd.windowDuration        outer analysis-window duration [s]
%   cfg.psd.windowStep            time between analysis windows [s]
%   cfg.psd.welchSegmentDuration  Welch segment duration [s]
%   cfg.psd.welchOverlap          Welch segment overlap [0, 1)
%   cfg.psd.detrend               "linear", "constant", or "none"
%
% Output layout:
%   powerSpectralDensity(frequency, window, channel)

% This function only estimates spectra. Peak detection and plotting belong
% in separate functions so they cannot change the PSD calculation.

validateInputs(cfg, dataData);

samplingRate = dataData.samplingRate;
windowDuration = cfg.psd.windowDuration;
windowStep = cfg.psd.windowStep;
segmentSamples = round( ...
    cfg.psd.welchSegmentDuration * samplingRate);
overlapSamples = round(cfg.psd.welchOverlap * segmentSamples);
if overlapSamples >= segmentSamples
    error('computeWindowedPcbPsd:InvalidWelchOverlap', ...
        'Welch overlap must leave at least one new sample per segment.');
end

channelCount = numel(dataData.channels);
channelStartTimes = nan(channelCount, 1);
channelEndTimes = nan(channelCount, 1);

for channelIndex = 1:channelCount
    channelTime = dataData.time{channelIndex}(:);
    channelStartTimes(channelIndex) = channelTime(1);
    sampleInterval = median(diff(channelTime));
    channelEndTimes(channelIndex) = channelTime(end) + sampleInterval;
end

% Only construct windows covered by every selected channel.
commonStartTime = max(channelStartTimes);
commonEndTime = min(channelEndTimes);
availableDuration = commonEndTime - commonStartTime;

if availableDuration < windowDuration
    error('computeWindowedPcbPsd:RecordTooShort', ...
        ['The common channel record is %.6g s long, shorter than the ', ...
        'configured %.6g s PSD window.'], ...
        availableDuration, windowDuration);
end

windowRatio = (availableDuration - windowDuration) / windowStep;
roundoffTolerance = 100 * eps(max(1, abs(windowRatio)));
windowCount = floor(windowRatio + roundoffTolerance) + 1;
windowStartTime = commonStartTime + ...
    (0:windowCount - 1).' * windowStep;
windowEndTime = windowStartTime + windowDuration;
windowCenterTime = (windowStartTime + windowEndTime) / 2;

frequency = [];
powerSpectralDensity = [];
welchWindow = hamming(segmentSamples, 'periodic');

for channelIndex = 1:channelCount
    channelTime = dataData.time{channelIndex}(:);
    channelSignal = dataData.signal{channelIndex}(:);

    for windowIndex = 1:windowCount
        % A half-open interval prevents a boundary sample from appearing in
        % two adjacent, non-overlapping windows.
        sampleMask = channelTime >= windowStartTime(windowIndex) & ...
            channelTime < windowEndTime(windowIndex);
        windowSignal = channelSignal(sampleMask);

        if numel(windowSignal) < segmentSamples
            error('computeWindowedPcbPsd:WindowTooShort', ...
                ['Window %d on channel %s contains %d samples; the ', ...
                'Welch segment requires %d.'], ...
                windowIndex, dataData.channels(channelIndex), ...
                numel(windowSignal), segmentSamples);
        end

        windowSignal = detrendWindow( ...
            windowSignal, cfg.psd.detrend);
        [windowPsd, windowFrequency] = pwelch( ...
            windowSignal, welchWindow, overlapSamples, ...
            segmentSamples, samplingRate, 'onesided');

        if isempty(frequency)
            frequency = windowFrequency;
            powerSpectralDensity = nan( ...
                numel(frequency), windowCount, channelCount);
        elseif ~isequal(windowFrequency, frequency)
            error('computeWindowedPcbPsd:FrequencyGridChanged', ...
                'Welch returned inconsistent frequency grids.');
        end

        powerSpectralDensity(:, windowIndex, channelIndex) = windowPsd; %#ok<AGROW>
    end
end

psdResults = struct();
psdResults.channels = dataData.channels;
psdResults.samplingRate = samplingRate;
psdResults.windowStartTime = windowStartTime;
psdResults.windowEndTime = windowEndTime;
psdResults.windowCenterTime = windowCenterTime;
psdResults.frequency = frequency;
psdResults.powerSpectralDensity = powerSpectralDensity;
psdResults.welchSegmentSamples = segmentSamples;
psdResults.welchOverlapSamples = overlapSamples;
end

function signal = detrendWindow(signal, detrendMethod)
switch lower(string(detrendMethod))
    case "linear"
        signal = detrend(signal, 1);
    case "constant"
        signal = detrend(signal, 0);
    case "none"
        % Preserve the signal as supplied.
    otherwise
        error('computeWindowedPcbPsd:InvalidDetrend', ...
            'cfg.psd.detrend must be "linear", "constant", or "none".');
end
end

function validateInputs(cfg, dataData)
requiredDataFields = ["channels", "time", "signal", "samplingRate"];
for fieldName = requiredDataFields
    if ~isfield(dataData, fieldName)
        error('computeWindowedPcbPsd:MissingDataField', ...
            'dataData.%s is required.', fieldName);
    end
end

if isempty(dataData.channels) || ...
        numel(dataData.time) ~= numel(dataData.channels) || ...
        numel(dataData.signal) ~= numel(dataData.channels)
    error('computeWindowedPcbPsd:InvalidChannelData', ...
        'Each channel must have one time vector and one signal vector.');
end

for channelIndex = 1:numel(dataData.channels)
    time = dataData.time{channelIndex};
    signal = dataData.signal{channelIndex};
    if isempty(time) || isempty(signal) || numel(time) ~= numel(signal)
        error('computeWindowedPcbPsd:InvalidChannelData', ...
            'Channel %s has empty or mismatched time and signal data.', ...
            dataData.channels(channelIndex));
    end
    if any(diff(time) <= 0)
        error('computeWindowedPcbPsd:InvalidTime', ...
            'Channel %s time values must increase strictly.', ...
            dataData.channels(channelIndex));
    end
end

if ~isfield(cfg, 'psd')
    error('computeWindowedPcbPsd:MissingConfiguration', ...
        'cfg.psd is required.');
end

requiredConfigFields = ["windowDuration", "windowStep", ...
    "welchSegmentDuration", "welchOverlap", "detrend"];
for fieldName = requiredConfigFields
    if ~isfield(cfg.psd, fieldName)
        error('computeWindowedPcbPsd:MissingConfiguration', ...
            'cfg.psd.%s is required.', fieldName);
    end
end

if ~isscalar(dataData.samplingRate) || dataData.samplingRate <= 0
    error('computeWindowedPcbPsd:InvalidSamplingRate', ...
        'dataData.samplingRate must be positive.');
end
if ~isscalar(cfg.psd.windowDuration) || cfg.psd.windowDuration <= 0 || ...
        ~isscalar(cfg.psd.windowStep) || cfg.psd.windowStep <= 0
    error('computeWindowedPcbPsd:InvalidWindowTiming', ...
        'PSD window duration and step must be positive.');
end
if ~isscalar(cfg.psd.welchSegmentDuration) || ...
        cfg.psd.welchSegmentDuration <= 0 || ...
        cfg.psd.welchSegmentDuration > cfg.psd.windowDuration
    error('computeWindowedPcbPsd:InvalidWelchSegment', ...
        ['Welch segment duration must be positive and no longer than ', ...
        'the PSD window duration.']);
end
if ~isscalar(cfg.psd.welchOverlap) || cfg.psd.welchOverlap < 0 || ...
        cfg.psd.welchOverlap >= 1
    error('computeWindowedPcbPsd:InvalidWelchOverlap', ...
        'cfg.psd.welchOverlap must satisfy 0 <= overlap < 1.');
end
end
