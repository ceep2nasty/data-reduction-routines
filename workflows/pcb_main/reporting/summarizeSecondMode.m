function summary = summarizeSecondMode(secondMode, reportCfg)
%SUMMARIZESECONDMODE Build one lifecycle summary per PCB channel.
%
% Times are based on finite PSD windows. A one-window missed detection can
% optionally be bridged when surrounded by valid detections.

requiredFields = [ ...
    "channels", ...
    "found", ...
    "frequency", ...
    "prominenceDb", ...
    "width", ...
    "fitRSquared", ...
    "windowStartTime", ...
    "windowEndTime", ...
    "windowCenterTime"];

for fieldName = requiredFields
    if ~isfield(secondMode, fieldName)
        error('summarizeSecondMode:MissingField', ...
            'secondMode.%s is required.', fieldName);
    end
end

minimumAppearance = reportCfg.minimumAppearanceWindows;
minimumDisappearance = reportCfg.minimumDisappearanceWindows;
maximumBridge = reportCfg.bridgeMissingWindows;

channelCount = numel(secondMode.channels);

emptySummary = struct( ...
    'channel', "", ...
    'status', "not detected", ...
    'detectedWindowCount', 0, ...
    'totalWindowCount', 0, ...
    'coverage', 0, ...
    'appearanceTime', NaN, ...
    'disappearanceTime', NaN, ...
    'medianFrequency', NaN, ...
    'frequencyIqr', NaN, ...
    'minimumFrequency', NaN, ...
    'maximumFrequency', NaN, ...
    'frequencyDrift', NaN, ...
    'medianProminenceDb', NaN, ...
    'medianWidth', NaN, ...
    'medianFitRSquared', NaN, ...
    'episodeCount', 0, ...
    'rawFound', [], ...
    'classifiedFound', []);

summary = repmat(emptySummary, channelCount, 1);

windowStart = secondMode.windowStartTime(:);
windowEnd = secondMode.windowEndTime(:);
windowCenter = secondMode.windowCenterTime(:);

for channelIndex = 1:channelCount
    rawFound = logical(secondMode.found(:, channelIndex));
    rawFound = rawFound & ...
        isfinite(secondMode.frequency(:, channelIndex));

    classifiedFound = bridgeShortGaps( ...
        rawFound, maximumBridge);

    classifiedFound = retainPersistentRuns( ...
        classifiedFound, minimumAppearance);

    [runStarts, runEnds] = findRuns(classifiedFound);

    detectedFrequency = ...
        secondMode.frequency(classifiedFound, channelIndex);

    detectedProminence = ...
        secondMode.prominenceDb(classifiedFound, channelIndex);

    detectedWidth = ...
        secondMode.width(classifiedFound, channelIndex);

    detectedFitQuality = ...
        secondMode.fitRSquared(classifiedFound, channelIndex);

    summary(channelIndex).channel = ...
        string(secondMode.channels(channelIndex));

    summary(channelIndex).detectedWindowCount = ...
        nnz(classifiedFound);

    summary(channelIndex).totalWindowCount = ...
        numel(classifiedFound);

    summary(channelIndex).coverage = ...
        nnz(classifiedFound) / numel(classifiedFound);

    summary(channelIndex).episodeCount = ...
        numel(runStarts);

    summary(channelIndex).rawFound = rawFound;
    summary(channelIndex).classifiedFound = classifiedFound;

    if isempty(runStarts)
        summary(channelIndex).status = "not detected";
        continue
    end

    summary(channelIndex).appearanceTime = ...
        windowCenter(runStarts(1));

    lastDetectedIndex = runEnds(end);
    windowsAfterDetection = ...
        numel(classifiedFound) - lastDetectedIndex;

    permanentlyAbsentAfter = ...
        windowsAfterDetection >= minimumDisappearance && ...
        ~any(classifiedFound(lastDetectedIndex + 1:end));

    if permanentlyAbsentAfter
        % The transition can only be localized to the boundary following
        % the final detected PSD window.
        summary(channelIndex).disappearanceTime = ...
            windowEnd(lastDetectedIndex);
    end

    if numel(runStarts) > 1
        summary(channelIndex).status = "intermittent";
    elseif permanentlyAbsentAfter
        summary(channelIndex).status = "appeared then disappeared";
    else
        summary(channelIndex).status = "present through analysis end";
    end

    summary(channelIndex).medianFrequency = ...
        median(detectedFrequency, 'omitnan');

    summary(channelIndex).frequencyIqr = ...
        iqr(detectedFrequency);

    summary(channelIndex).minimumFrequency = ...
        min(detectedFrequency, [], 'omitnan');

    summary(channelIndex).maximumFrequency = ...
        max(detectedFrequency, [], 'omitnan');

    summary(channelIndex).medianProminenceDb = ...
        median(detectedProminence, 'omitnan');

    summary(channelIndex).medianWidth = ...
        median(detectedWidth, 'omitnan');

    summary(channelIndex).medianFitRSquared = ...
        median(detectedFitQuality, 'omitnan');

    detectedTime = windowCenter(classifiedFound);

    if numel(detectedTime) >= 2 && ...
            range(detectedTime) > 0
        robustFit = polyfit( ...
            detectedTime - detectedTime(1), ...
            detectedFrequency, ...
            1);

        summary(channelIndex).frequencyDrift = ...
            robustFit(1);
    end
end
end

function bridged = bridgeShortGaps(found, maximumGap)
bridged = found(:);

if maximumGap <= 0
    return
end

missing = ~bridged;
[gapStarts, gapEnds] = findRuns(missing);

for gapIndex = 1:numel(gapStarts)
    gapStart = gapStarts(gapIndex);
    gapEnd = gapEnds(gapIndex);
    gapLength = gapEnd - gapStart + 1;

    boundedByDetections = ...
        gapStart > 1 && ...
        gapEnd < numel(bridged) && ...
        bridged(gapStart - 1) && ...
        bridged(gapEnd + 1);

    if boundedByDetections && gapLength <= maximumGap
        bridged(gapStart:gapEnd) = true;
    end
end
end

function retained = retainPersistentRuns(found, minimumLength)
retained = false(size(found));
[runStarts, runEnds] = findRuns(found);

for runIndex = 1:numel(runStarts)
    runLength = runEnds(runIndex) - runStarts(runIndex) + 1;

    if runLength >= minimumLength
        retained(runStarts(runIndex):runEnds(runIndex)) = true;
    end
end
end

function [runStarts, runEnds] = findRuns(mask)
mask = logical(mask(:));
changes = diff([false; mask; false]);

runStarts = find(changes == 1);
runEnds = find(changes == -1) - 1;
end