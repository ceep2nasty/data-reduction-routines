function [steadyWindow, diagnostics] = ...
    determineQuasiSteadyWindow(cfg, driverData, triggerData, dataData)
%DETERMINEQUASISTEADYWINDOW Estimate the useful quasi-steady flow interval.

    timing = cfg.timing;

    steadyWindow = struct( ...
        'time', [NaN NaN], ...
        'startTime', NaN, ...
        'endTime', NaN);

    diagnostics = struct( ...
        'triggerTime', NaN, ...
        'firstDataResponseTime', NaN, ...
        'driverSteadyStart', NaN, ...
        'driverSteadyEnd', NaN, ...
        'unstartTime', NaN);

    triggerTime = detectTriggerTime( ...
        triggerData, ...
        timing);

    diagnostics.triggerTime = triggerTime;

    dataResponseTimes = detectDataResponseTimes( ...
        dataData, ...
        timing);

    validResponseTimes = dataResponseTimes(isfinite(dataResponseTimes));

    if isempty(validResponseTimes)
        firstDataResponseTime = NaN;
    else
        firstDataResponseTime = min(validResponseTimes);
    end

    diagnostics.firstDataResponseTime = firstDataResponseTime;

    [driverSteadyStart, driverSteadyEnd] = ...
        detectDriverPlateau(driverData, timing);

    diagnostics.driverSteadyStart = driverSteadyStart;
    diagnostics.driverSteadyEnd = driverSteadyEnd;

    candidateStartTimes = [ ...
        triggerTime + timing.settlingDelay, ...
        firstDataResponseTime + timing.settlingDelay, ...
        driverSteadyStart];

    candidateStartTimes = ...
        candidateStartTimes(isfinite(candidateStartTimes));

    if isempty(candidateStartTimes)
        warning('determineQuasiSteadyWindow:NoStartTime', ...
            'Could not determine a quasi-steady start time.');
        return
    end

    steadyStart = max(candidateStartTimes);

    unstartTime = detectUnstartTime( ...
        dataData, ...
        steadyStart, ...
        timing);

    diagnostics.unstartTime = unstartTime;

    candidateEndTimes = [ ...
        unstartTime, ...
        driverSteadyEnd];

    candidateEndTimes = ...
        candidateEndTimes(isfinite(candidateEndTimes));

    if isempty(candidateEndTimes)
        warning('determineQuasiSteadyWindow:NoEndTime', ...
            'Could not determine a quasi-steady end time.');
        return
    end

    steadyEnd = min(candidateEndTimes);

    if steadyEnd <= steadyStart
        warning('determineQuasiSteadyWindow:InvalidWindow', ...
            'Detected quasi-steady interval has non-positive duration.');
        return
    end

    steadyWindow.time = [steadyStart steadyEnd];
    steadyWindow.startTime = steadyStart;
    steadyWindow.endTime = steadyEnd;
end

function triggerTime = detectTriggerTime(triggerData, timing)

    triggerTime = NaN;

    if isempty(triggerData.channels) || ...
            isempty(triggerData.signal)
        return
    end

    signal = triggerData.signal{1};
    time = triggerData.time{1};

    if isempty(signal) || isempty(time)
        return
    end

    signal = signal(:);
    time = time(:);

    baselineCount = max(10, ...
        floor(timing.baselineFraction * numel(signal)));

    baselineCount = min(baselineCount, numel(signal));

    signalDerivative = abs(gradient(signal, time));

    baselineDerivative = ...
        signalDerivative(1:baselineCount);

    derivativeCenter = median( ...
        baselineDerivative, ...
        'omitnan');

    derivativeSpread = mad( ...
        baselineDerivative, ...
        1);

    derivativeThreshold = derivativeCenter + ...
        timing.eventThresholdMultiplier * ...
        max(derivativeSpread, eps);

    eventMask = signalDerivative > derivativeThreshold;

    eventIndex = firstPersistentTrue( ...
        eventMask, ...
        timing.persistenceTime, ...
        time);

    if isfinite(eventIndex)
        triggerTime = time(eventIndex);
    end
end

function responseTimes = detectDataResponseTimes(dataData, timing)

    numberOfChannels = numel(dataData.channels);
    responseTimes = nan(numberOfChannels, 1);

    for channelIndex = 1:numberOfChannels

        signal = dataData.signal{channelIndex};
        time = dataData.time{channelIndex};

        if isempty(signal) || isempty(time)
            continue
        end

        signal = signal(:);
        time = time(:);

        baselineCount = max(10, ...
            floor(timing.baselineFraction * numel(signal)));

        baselineCount = min(baselineCount, numel(signal));

        signalDerivative = abs(gradient(signal, time));

        baselineDerivative = ...
            signalDerivative(1:baselineCount);

        derivativeCenter = median( ...
            baselineDerivative, ...
            'omitnan');

        derivativeSpread = mad( ...
            baselineDerivative, ...
            1);

        derivativeThreshold = derivativeCenter + ...
            timing.eventThresholdMultiplier * ...
            max(derivativeSpread, eps);

        eventMask = signalDerivative > derivativeThreshold;

        eventIndex = firstPersistentTrue( ...
            eventMask, ...
            timing.persistenceTime, ...
            time);

        if isfinite(eventIndex)
            responseTimes(channelIndex) = ...
                time(eventIndex);
        end
    end
end

function [steadyStart, steadyEnd] = ...
    detectDriverPlateau(driverData, timing)

    steadyStart = NaN;
    steadyEnd = NaN;

    if isempty(driverData.signal) || ...
            isempty(driverData.time)
        return
    end

    signal = driverData.signal{1};
    time = driverData.time{1};

    if isempty(signal) || isempty(time)
        return
    end

    signal = signal(:);
    time = time(:);

    baselineCount = max(10, ...
        floor(timing.baselineFraction * numel(signal)));

    baselineCount = min(baselineCount, numel(signal));

    baselineValue = median( ...
        signal(1:baselineCount), ...
        'omitnan');

    signalRange = max(signal) - min(signal);

    levelThreshold = timing.driverLevelFraction * ...
        max(signalRange, eps);

    driverLevelChange = abs(signal - baselineValue);

    signalSlope = abs(gradient(signal, time));

    baselineSlope = signalSlope(1:baselineCount);

    slopeCenter = median( ...
        baselineSlope, ...
        'omitnan');

    slopeSpread = mad( ...
        baselineSlope, ...
        1);

    slopeThreshold = slopeCenter + ...
        timing.driverSlopeMultiplier * ...
        max(slopeSpread, eps);

    plateauMask = ...
        driverLevelChange > levelThreshold & ...
        signalSlope < slopeThreshold;

    plateauStartIndex = firstPersistentTrue( ...
        plateauMask, ...
        timing.persistenceTime, ...
        time);

    if ~isfinite(plateauStartIndex)
        return
    end

    plateauEndIndex = lastPersistentTrue( ...
        plateauMask, ...
        timing.persistenceTime, ...
        time);

    if isfinite(plateauEndIndex)
        steadyStart = time(plateauStartIndex);
        steadyEnd = time(plateauEndIndex);
    end
end

function unstartTime = ...
    detectUnstartTime(dataData, steadyStart, timing)

    unstartTime = NaN;

    if ~isfinite(steadyStart)
        return
    end

    numberOfChannels = numel(dataData.channels);
    channelUnstartTimes = nan(numberOfChannels, 1);

    for channelIndex = 1:numberOfChannels

        signal = dataData.signal{channelIndex};
        time = dataData.time{channelIndex};

        if isempty(signal) || isempty(time)
            continue
        end

        signal = signal(:);
        time = time(:);

        samplingRate = dataData.samplingRate;

        if isempty(samplingRate) || ...
                ~isscalar(samplingRate) || ...
                ~isfinite(samplingRate) || ...
                samplingRate <= 0
            continue
        end

        fluctuationSamples = max( ...
            3, ...
            round(timing.fluctuationWindow * samplingRate));

        fluctuationLevel = movstd( ...
            signal, ...
            fluctuationSamples, ...
            'omitnan');

        referenceStart = steadyStart;
        referenceEnd = steadyStart + ...
            timing.referenceDuration;

        referenceMask = ...
            time >= referenceStart & ...
            time <= referenceEnd;

        referenceValues = ...
            fluctuationLevel(referenceMask);

        referenceLevel = median( ...
            referenceValues, ...
            'omitnan');

        if ~isfinite(referenceLevel) || referenceLevel <= 0
            continue
        end

        unstartMask = ...
            fluctuationLevel > ...
            timing.unstartMultiplier * referenceLevel;

        searchMask = time > referenceEnd;
        unstartMask(~searchMask) = false;

        eventIndex = firstPersistentTrue( ...
            unstartMask, ...
            timing.persistenceTime, ...
            time);

        if isfinite(eventIndex)
            channelUnstartTimes(channelIndex) = ...
                time(eventIndex);
        end
    end

    validTimes = channelUnstartTimes( ...
        isfinite(channelUnstartTimes));

    if ~isempty(validTimes)
        unstartTime = min(validTimes);
    end
end

function index = firstPersistentTrue(mask, persistenceTime, time)

    index = NaN;

    mask = logical(mask(:));
    time = time(:);

    if isempty(mask) || isempty(time)
        return
    end

    for candidateIndex = 1:numel(mask)

        if ~mask(candidateIndex)
            continue
        end

        endIndex = candidateIndex;

        while endIndex < numel(mask) && ...
                time(endIndex) - time(candidateIndex) < persistenceTime

            endIndex = endIndex + 1;
        end

        if all(mask(candidateIndex:endIndex))
            index = candidateIndex;
            return
        end
    end
end

function index = lastPersistentTrue(mask, persistenceTime, time)

    index = NaN;

    mask = logical(mask(:));
    time = time(:);

    if isempty(mask) || isempty(time)
        return
    end

    candidateIndices = find(mask);

    for candidatePosition = numel(candidateIndices):-1:1

        candidateIndex = candidateIndices(candidatePosition);
        endIndex = candidateIndex;

        while endIndex < numel(mask) && ...
                time(endIndex) - time(candidateIndex) < persistenceTime

            endIndex = endIndex + 1;
        end

        if all(mask(candidateIndex:endIndex))
            index = candidateIndex;
            return
        end
    end
end