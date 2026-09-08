function results = analyzeSecondModeWindows(cfg, windowedPsdResults)
%ANALYZESECONDMODEWINDOWS Detect second-mode peaks across PSD windows.
%
% This function:
%   1. Removes channels listed in cfg.secondMode.channelsExcluded.
%   2. Calls detectSecondModePeak for every remaining channel and window.
%   3. Collects the scalar results into window-by-channel matrices.
%
% The original PSD data are not modified.

%% Determine which channels to analyze

allChannels = string(windowedPsdResults.channels(:));

if isfield(cfg.secondMode, 'channelsExcluded')
    excludedChannels = string( ...
        cfg.secondMode.channelsExcluded(:));
else
    excludedChannels = strings(0, 1);
end

% Let "" mean that no channels are excluded.
excludedChannels(excludedChannels == "") = [];

unknownExcludedChannels = setdiff( ...
    excludedChannels, ...
    allChannels);

if ~isempty(unknownExcludedChannels)
    error( ...
        'analyzeSecondModeWindows:UnknownExcludedChannel', ...
        'Excluded channel(s) not found: %s', ...
        strjoin(unknownExcludedChannels, ", "));
end

includedChannelMask = ~ismember( ...
    allChannels, ...
    excludedChannels);

includedChannelIndices = find(includedChannelMask);
includedChannels = allChannels(includedChannelMask);

if isempty(includedChannels)
    error( ...
        'analyzeSecondModeWindows:NoIncludedChannels', ...
        'Every PCB channel is excluded from second-mode analysis.');
end

%% Determine output dimensions

numberOfWindows = numel( ...
    windowedPsdResults.windowCenterTime);

numberOfChannels = numel(includedChannels);

%% Initialize output

results = struct();

results.channels = includedChannels;

% This maps each analyzed channel back to the channel dimension of the
% original PSD array.
results.sourceChannelIndices = includedChannelIndices;

results.windowStartTime = ...
    windowedPsdResults.windowStartTime;

results.windowEndTime = ...
    windowedPsdResults.windowEndTime;

results.windowCenterTime = ...
    windowedPsdResults.windowCenterTime;

% Each matrix is organized as:
%
%   result(windowIndex, analyzedChannelIndex)

results.found = false( ...
    numberOfWindows, numberOfChannels);

results.coarseFrequency = nan( ...
    numberOfWindows, numberOfChannels);

results.frequency = nan( ...
    numberOfWindows, numberOfChannels);

results.amplitudeDb = nan( ...
    numberOfWindows, numberOfChannels);

results.prominenceDb = nan( ...
    numberOfWindows, numberOfChannels);

results.width = nan( ...
    numberOfWindows, numberOfChannels);

results.curvature = nan( ...
    numberOfWindows, numberOfChannels);

results.fitRSquared = nan( ...
    numberOfWindows, numberOfChannels);

%% Analyze every included channel and time window

for analyzedChannelIndex = 1:numberOfChannels

    sourceChannelIndex = ...
        includedChannelIndices(analyzedChannelIndex);

    for windowIndex = 1:numberOfWindows

        windowPsd = reshape( ...
            windowedPsdResults.powerSpectralDensity( ...
                :, windowIndex, sourceChannelIndex), ...
            [], 1);

        peak = detectSecondModePeak( ...
            cfg, ...
            windowedPsdResults.frequency, ...
            windowPsd);

        results.found( ...
            windowIndex, analyzedChannelIndex) = ...
            peak.found;

        results.coarseFrequency( ...
            windowIndex, analyzedChannelIndex) = ...
            peak.coarseFrequency;

        results.frequency( ...
            windowIndex, analyzedChannelIndex) = ...
            peak.frequency;

        results.amplitudeDb( ...
            windowIndex, analyzedChannelIndex) = ...
            peak.amplitudeDb;

        results.prominenceDb( ...
            windowIndex, analyzedChannelIndex) = ...
            peak.prominenceDb;

        results.width( ...
            windowIndex, analyzedChannelIndex) = ...
            peak.width;

        results.curvature( ...
            windowIndex, analyzedChannelIndex) = ...
            peak.curvature;

        results.fitRSquared( ...
            windowIndex, analyzedChannelIndex) = ...
            peak.fitRSquared;
    end
end
end
