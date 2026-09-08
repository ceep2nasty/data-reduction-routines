function peak = detectSecondModePeak(cfg, frequency, psdValues)
    %DETECTSECONDMODEPEAK Find and refine one peak in one PSD.
    %
    % This function analyzes one channel during one time window.
    %
    % Inputs:
    %   cfg         workflow configuration
    %   frequency   PSD frequency vector [Hz]
    %   psdValues   power spectral density
    %
    % Output:
    %   peak        structure containing the detection and fit results

    frequency = frequency(:);
    psdValues = psdValues(:);

    %% Initialize the result

    peak = struct();

    peak.found = false;
    peak.coarseFrequency = NaN;
    peak.frequency = NaN;
    peak.amplitudeDb = NaN;
    peak.prominenceDb = NaN;
    peak.width = NaN;
    peak.curvature = NaN;
    peak.fitRSquared = NaN;

    %% Restrict the PSD to the expected frequency region

    frequencyBand = cfg.secondMode.frequencyBand;

    bandMask = ...
        frequency >= frequencyBand(1) & ...
        frequency <= frequencyBand(2) & ...
        isfinite(psdValues) & ...
        psdValues > 0;

    bandFrequency = frequency(bandMask);
    bandPsd = psdValues(bandMask);

    if numel(bandFrequency) < 3
        return
    end

    bandPsdDb = pow2db(bandPsd);

    %% Find sufficiently prominent and sufficiently broad local peaks

    [~, peakLocations, peakWidths, peakProminences] = ...
        findpeaks( ...
            bandPsdDb, ...
            bandFrequency, ...
            'MinPeakProminence', ...
                cfg.secondMode.minimumProminenceDb, ...
            'MinPeakWidth', ...
                cfg.secondMode.minimumWidth);

    if isempty(peakLocations)
        return
    end

    %% Select the most prominent candidate

    [~, selectedIndex] = max(peakProminences);

    coarseFrequency = peakLocations(selectedIndex);

    peak.coarseFrequency = coarseFrequency;
    peak.prominenceDb = peakProminences(selectedIndex);
    peak.width = peakWidths(selectedIndex);

    %% Select the local region used for the parabola

    fitMask = abs(bandFrequency - coarseFrequency) <= ...
        cfg.secondMode.fitHalfWidth;

    fitFrequency = bandFrequency(fitMask);
    fitPsdDb = bandPsdDb(fitMask);

    if numel(fitFrequency) < 3
        return
    end

    %% Fit a parabola in frequency-versus-dB space

    % Express frequency relative to the coarse peak and in kHz.
    % This keeps the polynomial coefficients numerically well scaled.
    fitFrequencyOffsetKHz = ...
        (fitFrequency - coarseFrequency) / 1e3;

    fitCoefficients = polyfit( ...
        fitFrequencyOffsetKHz, ...
        fitPsdDb, ...
        2);

    fittedPsdDb = polyval( ...
        fitCoefficients, ...
        fitFrequencyOffsetKHz);

    curvature = fitCoefficients(1);

    %% Find the vertex of the fitted parabola

    vertexOffsetKHz = ...
        -fitCoefficients(2) / (2 * fitCoefficients(1));

    refinedFrequency = ...
        coarseFrequency + vertexOffsetKHz * 1e3;

    refinedAmplitudeDb = polyval( ...
        fitCoefficients, ...
        vertexOffsetKHz);

    %% Calculate fit quality for diagnosis

    residualSumSquares = sum( ...
        (fitPsdDb - fittedPsdDb).^2);

    totalSumSquares = sum( ...
        (fitPsdDb - mean(fitPsdDb)).^2);

    fitRSquared = 1 - residualSumSquares / ...
        max(totalSumSquares, eps);

    %% Decide whether the fitted shape is physically plausible

    opensDownward = curvature < 0;

    vertexInsideFitRegion = ...
        refinedFrequency >= fitFrequency(1) && ...
        refinedFrequency <= fitFrequency(end);

    peak.found = opensDownward && vertexInsideFitRegion;

    %% Store diagnostic results

    peak.curvature = curvature;
    peak.fitRSquared = fitRSquared;

    if peak.found
        peak.frequency = refinedFrequency;
        peak.amplitudeDb = refinedAmplitudeDb;
    end
end
