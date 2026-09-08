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
    frequencySmoothBins = getSecondModeValue( ...
        cfg, 'frequencySmoothBins', 5);
    timeSmoothBins = getSecondModeValue( ...
        cfg, 'timeSmoothBins', 41);
    smallSlopeFitBins = getSecondModeValue( ...
        cfg, 'smallSlopeFitBins', 7);
    mediumSlopeFitBins = getSecondModeValue( ...
        cfg, 'mediumSlopeFitBins', 13);
    broadSlopeFitBins = getSecondModeValue( ...
        cfg, 'broadSlopeFitBins', 25);
    maximumCandidateDrift = getSecondModeValue( ...
        cfg, 'maximumCandidateDrift', 10e3);
    minimumProminenceDb = getSecondModeValue( ...
        cfg, 'minimumProminenceDb', 4);
    minimumQuadraticFitImprovement = getSecondModeValue( ...
        cfg, 'minimumQuadraticFitImprovement', 0.20);
    stateSmoothingBins = getSecondModeValue( ...
        cfg, 'stateSmoothingBins', 401);
    minimumCandidateFraction = getSecondModeValue( ...
        cfg, 'minimumCandidateFraction', 0.20);

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
    secondModeResults.localSlope = cell(size(channels));
    secondModeResults.slopeCandidate = cell(size(channels));
    secondModeResults.mediumCandidate = cell(size(channels));
    secondModeResults.broadCandidate = cell(size(channels));
    secondModeResults.quadraticCurvature = cell(size(channels));
    secondModeResults.quadraticFitImprovement = cell(size(channels));
    secondModeResults.quadraticVertexFrequency = cell(size(channels));
    secondModeResults.candidateProminenceDb = cell(size(channels));
    secondModeResults.candidateValid = cell(size(channels));
    secondModeResults.modePresent = cell(size(channels));
    secondModeResults.smoothedPeakContrast = cell(size(channels));
    secondModeResults.contrastEligible = cell(size(channels));
    secondModeResults.amplitudeEligible = cell(size(channels));
    secondModeResults.edgeEligible = cell(size(channels));
    secondModeResults.stateValid = cell(size(channels));

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

        bandSpectrumDb = 20 * log10(double(bandMagnitude) + eps);
        smoothedSpectrumDb = movmean( ...
            bandSpectrumDb, ...
            frequencySmoothBins, ...
            1, ...
            'omitnan');
        smoothedSpectrumDb = movmean( ...
            smoothedSpectrumDb, ...
            timeSmoothBins, ...
            2, ...
            'omitnan');

        numberOfTimeWindows = size(bandMagnitude, 2);

        candidateFrequency = nan(1, numberOfTimeWindows);
        peakAmplitude = nan(1, numberOfTimeWindows);
        backgroundLevel = nan(1, numberOfTimeWindows);
        peakContrast = nan(1, numberOfTimeWindows);
        localSlope = nan(size(bandMagnitude));
        slopeCandidate = false(1, numberOfTimeWindows);
        mediumCandidate = false(1, numberOfTimeWindows);
        broadCandidate = false(1, numberOfTimeWindows);
        quadraticCurvature = nan(1, numberOfTimeWindows);
        quadraticFitImprovement = nan(1, numberOfTimeWindows);
        quadraticVertexFrequency = nan(1, numberOfTimeWindows);
        candidateProminenceDb = nan(1, numberOfTimeWindows);

        for timeIndex = 1:numberOfTimeWindows

            spectrumSlice = double(bandMagnitude(:, timeIndex));
            finiteValues = isfinite(spectrumSlice);

            if ~any(finiteValues)
                continue
            end

            spectrumDb = smoothedSpectrumDb(:, timeIndex);
            finiteSpectrumDb = isfinite(spectrumDb);

            if nnz(finiteSpectrumDb) < smallSlopeFitBins
                continue
            end

            halfFitBins = floor(smallSlopeFitBins / 2);
            for frequencyIndex = 1:numel(bandFrequency)
                fitStart = max(1, frequencyIndex - halfFitBins);
                fitEnd = min(numel(bandFrequency), frequencyIndex + halfFitBins);
                fitIndices = fitStart:fitEnd;

                if numel(fitIndices) < 3 || ...
                        any(~isfinite(spectrumDb(fitIndices)))
                    continue
                end

                centeredFrequency = ...
                    (bandFrequency(fitIndices) - ...
                    bandFrequency(frequencyIndex)) / 1e3;

                fitCoefficients = polyfit( ...
                    centeredFrequency, ...
                    spectrumDb(fitIndices), ...
                    1);

                localSlope(frequencyIndex, timeIndex) = ...
                    fitCoefficients(1);
            end

            positiveToNegative = find( ...
                localSlope(1:end - 1, timeIndex) > 0 & ...
                localSlope(2:end, timeIndex) < 0);

            if isempty(positiveToNegative)
                continue
            end

            transitionScores = -Inf(size(positiveToNegative));
            for transitionIndex = 1:numel(positiveToNegative)
                transition = positiveToNegative(transitionIndex) + 1;
                leftStart = max(1, transition - broadSlopeFitBins);
                rightEnd = min( ...
                    numel(bandFrequency), ...
                    transition + broadSlopeFitBins);
                leftShoulder = spectrumDb(leftStart:transition - 1);
                rightShoulder = spectrumDb(transition + 1:rightEnd);

                if ~isempty(leftShoulder) && ~isempty(rightShoulder)
                    transitionScores(transitionIndex) = ...
                        spectrumDb(transition) - max( ...
                        median(leftShoulder, 'omitnan'), ...
                        median(rightShoulder, 'omitnan'));
                end
            end

            [bestProminence, bestTransition] = max(transitionScores);
            if ~isfinite(bestProminence) || ...
                    bestProminence < minimumProminenceDb
                continue
            end

            candidateProminenceDb(timeIndex) = bestProminence;
            peakIndex = positiveToNegative(bestTransition) + 1;
            candidateAmplitude = spectrumSlice(peakIndex);

            if ~isfinite(candidateAmplitude)
                continue
            end

            candidateFrequency(timeIndex) = bandFrequency(peakIndex);
            peakAmplitude(timeIndex) = candidateAmplitude;
            slopeCandidate(timeIndex) = true;

            mediumHalfFitBins = floor(mediumSlopeFitBins / 2);
            mediumSearchStart = max(1, peakIndex - mediumHalfFitBins);
            mediumSearchEnd = min( ...
                numel(bandFrequency), ...
                peakIndex + mediumHalfFitBins);
            mediumSlope = nan(size(bandFrequency));

            for mediumIndex = mediumSearchStart:mediumSearchEnd
                fitStart = max(1, mediumIndex - mediumHalfFitBins);
                fitEnd = min( ...
                    numel(bandFrequency), ...
                    mediumIndex + mediumHalfFitBins);
                fitIndices = fitStart:fitEnd;

                if numel(fitIndices) < 3 || ...
                        any(~isfinite(spectrumDb(fitIndices)))
                    continue
                end

                centeredFrequency = ...
                    (bandFrequency(fitIndices) - ...
                    bandFrequency(mediumIndex)) / 1e3;

                fitCoefficients = polyfit( ...
                    centeredFrequency, ...
                    spectrumDb(fitIndices), ...
                    1);

                mediumSlope(mediumIndex) = fitCoefficients(1);
            end

            mediumTransitions = find( ...
                mediumSlope(1:end - 1) > 0 & ...
                mediumSlope(2:end) < 0);
            mediumTransitions = mediumTransitions( ...
                mediumTransitions >= mediumSearchStart & ...
                mediumTransitions <= mediumSearchEnd - 1);

            if isempty(mediumTransitions)
                candidateFrequency(timeIndex) = NaN;
                peakAmplitude(timeIndex) = NaN;
                continue
            end

            [~, nearestTransition] = min( ...
                abs(mediumTransitions + 1 - peakIndex));
            mediumPeakIndex = mediumTransitions(nearestTransition) + 1;
            maximumDrift = maximumCandidateDrift;

            if abs(bandFrequency(mediumPeakIndex) - ...
                    bandFrequency(peakIndex)) > maximumDrift
                candidateFrequency(timeIndex) = NaN;
                peakAmplitude(timeIndex) = NaN;
                continue
            end

            candidateFrequency(timeIndex) = bandFrequency(mediumPeakIndex);
            peakAmplitude(timeIndex) = spectrumSlice(mediumPeakIndex);
            mediumCandidate(timeIndex) = true;

            broadHalfFitBins = floor(broadSlopeFitBins / 2);
            broadSearchStart = max(1, mediumPeakIndex - broadHalfFitBins);
            broadSearchEnd = min( ...
                numel(bandFrequency), ...
                mediumPeakIndex + broadHalfFitBins);
            broadSlope = nan(size(bandFrequency));

            for broadIndex = broadSearchStart:broadSearchEnd
                fitStart = max(1, broadIndex - broadHalfFitBins);
                fitEnd = min( ...
                    numel(bandFrequency), ...
                    broadIndex + broadHalfFitBins);
                fitIndices = fitStart:fitEnd;

                if numel(fitIndices) < 3 || ...
                        any(~isfinite(spectrumDb(fitIndices)))
                    continue
                end

                centeredFrequency = ...
                    (bandFrequency(fitIndices) - ...
                    bandFrequency(broadIndex)) / 1e3;

                fitCoefficients = polyfit( ...
                    centeredFrequency, ...
                    spectrumDb(fitIndices), ...
                    1);

                broadSlope(broadIndex) = fitCoefficients(1);
            end

            broadTransitions = find( ...
                broadSlope(1:end - 1) > 0 & ...
                broadSlope(2:end) < 0);
            broadTransitions = broadTransitions( ...
                broadTransitions >= broadSearchStart & ...
                broadTransitions <= broadSearchEnd - 1);

            if isempty(broadTransitions)
                candidateFrequency(timeIndex) = NaN;
                peakAmplitude(timeIndex) = NaN;
                continue
            end

            [~, nearestTransition] = min( ...
                abs(broadTransitions + 1 - mediumPeakIndex));
            broadPeakIndex = broadTransitions(nearestTransition) + 1;

            if abs(bandFrequency(broadPeakIndex) - ...
                    bandFrequency(mediumPeakIndex)) > maximumDrift
                candidateFrequency(timeIndex) = NaN;
                peakAmplitude(timeIndex) = NaN;
                continue
            end

            broadFitStart = max(1, broadPeakIndex - broadHalfFitBins);
            broadFitEnd = min( ...
                numel(bandFrequency), ...
                broadPeakIndex + broadHalfFitBins);
            broadFitIndices = broadFitStart:broadFitEnd;
            broadFitFrequency = ...
                (bandFrequency(broadFitIndices) - ...
                bandFrequency(broadPeakIndex)) / 1e3;
            broadFitSpectrum = spectrumDb(broadFitIndices);

            if numel(broadFitIndices) < 5 || ...
                    any(~isfinite(broadFitSpectrum))
                candidateFrequency(timeIndex) = NaN;
                peakAmplitude(timeIndex) = NaN;
                continue
            end

            linearFitCoefficients = polyfit( ...
                broadFitFrequency, ...
                broadFitSpectrum, ...
                1);
            quadraticFitCoefficients = polyfit( ...
                broadFitFrequency, ...
                broadFitSpectrum, ...
                2);

            linearResidual = sum((broadFitSpectrum - ...
                polyval(linearFitCoefficients, broadFitFrequency)).^2);
            quadraticResidual = sum((broadFitSpectrum - ...
                polyval(quadraticFitCoefficients, broadFitFrequency)).^2);

            quadraticCurvature(timeIndex) = ...
                quadraticFitCoefficients(1);
            quadraticFitImprovement(timeIndex) = 1 - ...
                quadraticResidual / max(linearResidual, eps);

            if quadraticFitCoefficients(1) >= 0
                candidateFrequency(timeIndex) = NaN;
                peakAmplitude(timeIndex) = NaN;
                continue
            end

            if quadraticFitImprovement(timeIndex) < ...
                    minimumQuadraticFitImprovement
                candidateFrequency(timeIndex) = NaN;
                peakAmplitude(timeIndex) = NaN;
                continue
            end

            quadraticVertex = -quadraticFitCoefficients(2) / ...
                (2 * quadraticFitCoefficients(1));
            vertexIsInsideFit = quadraticVertex >= ...
                broadFitFrequency(1) && quadraticVertex <= ...
                broadFitFrequency(end);

            if ~vertexIsInsideFit
                candidateFrequency(timeIndex) = NaN;
                peakAmplitude(timeIndex) = NaN;
                continue
            end

            candidateFrequency(timeIndex) = ...
                bandFrequency(broadPeakIndex);
            peakAmplitude(timeIndex) = spectrumSlice(broadPeakIndex);
            quadraticVertexFrequency(timeIndex) = ...
                bandFrequency(broadPeakIndex) + quadraticVertex * 1e3;
            candidateFrequency(timeIndex) = ...
                quadraticVertexFrequency(timeIndex);
            broadCandidate(timeIndex) = true;

            finiteSpectrum = spectrumSlice(isfinite(spectrumSlice));
            backgroundLevel(timeIndex) = median(finiteSpectrum, 'omitnan');

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

        candidateValid = ...
            broadCandidate & ...
            smoothedContrast >= cfg.secondMode.minimumContrast & ...
            peakAmplitude >= cfg.secondMode.minimumAmplitude & ...
            awayFromLowerEdge & ...
            awayFromUpperEdge;

        contrastEligible = smoothedContrast >= ...
            cfg.secondMode.minimumContrast;
        amplitudeEligible = peakAmplitude >= ...
            cfg.secondMode.minimumAmplitude;
        edgeEligible = awayFromLowerEdge & awayFromUpperEdge;

        candidateValid = candidateValid & ...
            isfinite(candidateFrequency);

        candidateFraction = movmean( ...
            double(candidateValid), ...
            stateSmoothingBins, ...
            'omitnan');
        stateValid = candidateFraction >= minimumCandidateFraction;

        appearanceIndex = firstConsecutiveRun( ...
            stateValid, ...
            cfg.secondMode.minimumVisibleWindows, ...
            1);

        modePresent = false(size(candidateValid));
        disappearanceIndex = NaN;

        if ~isnan(appearanceIndex)
            disappearanceIndex = firstConsecutiveRun( ...
                ~stateValid, ...
                cfg.secondMode.minimumInvisibleWindows, ...
                appearanceIndex + cfg.secondMode.minimumVisibleWindows);

            if ~isnan(disappearanceIndex)
                invalidRunReachesRecordEnd = ...
                    all(~stateValid(disappearanceIndex:end));

                if invalidRunReachesRecordEnd
                    disappearanceIndex = NaN;
                end
            end

            if isnan(disappearanceIndex)
                modePresent(appearanceIndex:end) = true;
            elseif disappearanceIndex > appearanceIndex
                modePresent(appearanceIndex:disappearanceIndex - 1) = true;
            end
        end

        frequencyTrace = candidateFrequency;
        frequencyTrace(~modePresent) = NaN;

        validValues = modePresent & isfinite(frequencyTrace);

        secondModeResults.time{channelIndex} = time;
        secondModeResults.frequencyTrace{channelIndex} = frequencyTrace;

        secondModeResults.peakAmplitude{channelIndex} = peakAmplitude;
        secondModeResults.backgroundLevel{channelIndex} = backgroundLevel;
        secondModeResults.peakContrast{channelIndex} = peakContrast;
        secondModeResults.isVisible{channelIndex} = modePresent;
        secondModeResults.localSlope{channelIndex} = localSlope;
        secondModeResults.slopeCandidate{channelIndex} = slopeCandidate;
        secondModeResults.mediumCandidate{channelIndex} = mediumCandidate;
        secondModeResults.broadCandidate{channelIndex} = broadCandidate;
        secondModeResults.quadraticCurvature{channelIndex} = ...
            quadraticCurvature;
        secondModeResults.quadraticFitImprovement{channelIndex} = ...
            quadraticFitImprovement;
        secondModeResults.quadraticVertexFrequency{channelIndex} = ...
            quadraticVertexFrequency;
        secondModeResults.candidateProminenceDb{channelIndex} = ...
            candidateProminenceDb;
        secondModeResults.candidateValid{channelIndex} = candidateValid;
        secondModeResults.modePresent{channelIndex} = modePresent;
        secondModeResults.smoothedPeakContrast{channelIndex} = ...
            smoothedContrast;
        secondModeResults.contrastEligible{channelIndex} = ...
            contrastEligible;
        secondModeResults.amplitudeEligible{channelIndex} = ...
            amplitudeEligible;
        secondModeResults.edgeEligible{channelIndex} = edgeEligible;
        secondModeResults.stateValid{channelIndex} = stateValid;

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

function value = getSecondModeValue(cfg, fieldName, defaultValue)
if isfield(cfg, 'secondMode') && ...
        isfield(cfg.secondMode, fieldName) && ...
        ~isempty(cfg.secondMode.(fieldName))
    value = cfg.secondMode.(fieldName);
else
    value = defaultValue;
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