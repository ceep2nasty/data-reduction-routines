function secondModeResults = trackSecondMode(cfg, spectrogramResults)

    channels = spectrogramResults.channels;
    numberOfChannels = numel(channels);

    if ~isfield(cfg.analysis, 'dataLocations')
        error('trackSecondMode:MissingLocations', ...
            'cfg.analysis.dataLocations is required.');
    end

    locations = cfg.analysis.dataLocations;

    if numel(locations) ~= numberOfChannels
        error('trackSecondMode:LocationCountMismatch', ...
            'Each analysis channel must have one physical location.');
    end

    frequencyBand = cfg.secondMode.frequencyBand;

    if numel(frequencyBand) ~= 2 || ...
            frequencyBand(1) >= frequencyBand(2)
        error('trackSecondMode:InvalidFrequencyBand', ...
            'frequencyBand must be [lowerFrequency upperFrequency].');
    end

    secondModeResults = struct();

    secondModeResults.channels = channels;
    secondModeResults.locations = locations;

    secondModeResults.time = cell(size(channels));
    secondModeResults.frequencyTrace = cell(size(channels));

    secondModeResults.peakAmplitude = cell(size(channels));
    secondModeResults.backgroundLevel = cell(size(channels));
    secondModeResults.peakContrast = cell(size(channels));
    secondModeResults.isVisible = cell(size(channels));

    secondModeResults.frequencyMedian = nan(size(channels));
    secondModeResults.frequencyMean = nan(size(channels));
    secondModeResults.frequencyStd = nan(size(channels));
    secondModeResults.validFraction = nan(size(channels));

    secondModeResults.appearanceTime = nan(size(channels));
    secondModeResults.disappearanceTime = nan(size(channels));

    for channelIndex = 1:numberOfChannels

        time = spectrogramResults.time{channelIndex};
        frequency = spectrogramResults.frequency{channelIndex};
        magnitude = spectrogramResults.magnitude{channelIndex};

        frequency = frequency(:);
        time = time(:);

        if size(magnitude, 1) ~= numel(frequency)
            error('trackSecondMode:FrequencyMagnitudeMismatch', ...
                'Frequency and magnitude dimensions do not match.');
        end

        if size(magnitude, 2) ~= numel(time)
            error('trackSecondMode:TimeMagnitudeMismatch', ...
                'Time and magnitude dimensions do not match.');
        end

        bandMask = frequency >= frequencyBand(1) & frequency <= frequencyBand(2);

        if ~any(bandMask)
            warning('trackSecondMode:NoFrequenciesInBand', ...
                'No frequencies found in the specified frequency band for channel %s.', ...
                channels(channelIndex));
            continue;
        end

        bandFrequency = frequency(bandMask);
        bandMagnitude = magnitude(bandMask, :);

        numberOfTimeWindows = size(bandMagnitude, 2);

        candidateFrequency = nan(1, numberOfTimeWindows);
        peakAmplitude = nan(1, numberOfTimeWindows);
        backgroundLevel = nan(1, numberOfTimeWindows);
        peakContrast = nan(1, numberOfTimeWindows);

        for timeIndex = 1:numberOfTimeWindows

            spectrumSlice = double(bandMagnitude(:, timeIndex));
            finiteValues = isfinite(spectrumSlice);

            if ~any(finiteValues)
                continue
            end

            spectrumSlice(~finiteValues) = -Inf;

            [candidateAmplitude, peakIndex] = max(spectrumSlice);

            if ~isfinite(candidateAmplitude)
                continue
            end

            candidateFrequency(timeIndex) = bandFrequency(peakIndex);
            peakAmplitude(timeIndex) = candidateAmplitude;

            finiteSpectrum = spectrumSlice(isfinite(spectrumSlice));
            backgroundLevel(timeIndex) = median(finiteSpectrum);

            denominator = max(backgroundLevel(timeIndex), eps);
            peakContrast(timeIndex) = ...
                peakAmplitude(timeIndex) / denominator;
        end

            smoothedContrast = peakContrast;

        smoothingWindows = ...
            cfg.secondMode.contrastSmoothingWindows;

        if smoothingWindows > 1
            smoothedContrast = movmedian( ...
                peakContrast, ...
                smoothingWindows, ...
                'omitnan');
        end

        edgeBuffer = cfg.secondMode.edgeBufferBins;

        awayFromLowerEdge = ...
            candidateFrequency >= bandFrequency(1 + edgeBuffer);

        awayFromUpperEdge = ...
            candidateFrequency <= ...
            bandFrequency(end - edgeBuffer);

        isVisible = ...
            smoothedContrast >= cfg.secondMode.minimumContrast & ...
            peakAmplitude >= cfg.secondMode.minimumAmplitude & ...
            awayFromLowerEdge & ...
            awayFromUpperEdge;

        isVisible = isVisible & ...
            isfinite(candidateFrequency);

        frequencyTrace = candidateFrequency;
        frequencyTrace(~isVisible) = NaN;

        validValues = isfinite(frequencyTrace);

        secondModeResults.time{channelIndex} = time;
        secondModeResults.frequencyTrace{channelIndex} = frequencyTrace;

        secondModeResults.peakAmplitude{channelIndex} = peakAmplitude;
        secondModeResults.backgroundLevel{channelIndex} = backgroundLevel;
        secondModeResults.peakContrast{channelIndex} = peakContrast;
        secondModeResults.isVisible{channelIndex} = isVisible;

        secondModeResults.validFraction(channelIndex) = ...
            mean(validValues);

        if any(validValues)

            secondModeResults.frequencyMedian(channelIndex) = ...
                median(frequencyTrace(validValues));

            secondModeResults.frequencyMean(channelIndex) = ...
                mean(frequencyTrace(validValues));

            secondModeResults.frequencyStd(channelIndex) = ...
                std(frequencyTrace(validValues));
        end

        appearanceIndex = firstConsecutiveRun( ...
            isVisible, ...
            cfg.secondMode.minimumVisibleWindows, ...
            1);

        if isnan(appearanceIndex)
            disappearanceIndex = NaN;
        else
            disappearanceIndex = firstConsecutiveRun( ...
                ~isVisible, ...
                cfg.secondMode.minimumInvisibleWindows, ...
                appearanceIndex + ...
                cfg.secondMode.minimumVisibleWindows);
        end

        if ~isnan(appearanceIndex)
            secondModeResults.appearanceTime(channelIndex) = ...
                time(appearanceIndex);
        end

        if ~isnan(disappearanceIndex)
            secondModeResults.disappearanceTime(channelIndex) = ...
                time(disappearanceIndex);
        end

    end

end

function firstIndex = firstConsecutiveRun(logicalValues, runLength, startIndex)

    firstIndex = NaN;

    if isempty(logicalValues)
        return
    end

    startIndex = max(1, startIndex);
    lastStart = numel(logicalValues) - runLength + 1;

    if lastStart < startIndex
        return
    end

    for index = startIndex:lastStart

        candidateRun = logicalValues(index:index + runLength - 1);

        if all(candidateRun)
            firstIndex = index;
            return
        end
    end
end