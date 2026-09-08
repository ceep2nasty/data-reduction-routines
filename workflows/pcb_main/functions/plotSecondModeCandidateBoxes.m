function plotSecondModeCandidateBoxes( ...
    axesHandle, cfg, secondModeResults, currentTime, frequencies, psdValues)
%PLOTSECONDMODECANDIDATEBOXES Box accepted second-mode features on a PSD plot.

boxHalfWidth = 30e3;
if isfield(cfg, 'secondMode') && ...
        isfield(cfg.secondMode, 'visualBoxHalfWidth') && ...
        ~isempty(cfg.secondMode.visualBoxHalfWidth)
    boxHalfWidth = cfg.secondMode.visualBoxHalfWidth;
end

for channelIndex = 1:numel(secondModeResults.channels)
    if channelIndex > numel(frequencies) || ...
            isempty(frequencies{channelIndex}) || ...
            channelIndex > numel(psdValues) || ...
            isempty(psdValues{channelIndex})
        continue
    end

    modeTime = secondModeResults.time{channelIndex};
    modeVisible = secondModeResults.isVisible{channelIndex};
    modeFrequency = secondModeResults.frequencyTrace{channelIndex};
    if isfield(secondModeResults, 'quadraticVertexFrequency')
        vertexFrequency = ...
            secondModeResults.quadraticVertexFrequency{channelIndex};
    else
        vertexFrequency = modeFrequency;
    end

    if isempty(modeTime) || isempty(modeVisible) || ...
            isempty(modeFrequency)
        continue
    end

    [~, timeIndex] = min(abs(modeTime - currentTime));

    if ~modeVisible(timeIndex) || ...
            ~isfinite(modeFrequency(timeIndex))
        continue
    end

    if ~isempty(vertexFrequency) && ...
            isfinite(vertexFrequency(timeIndex))
        boxCenterFrequency = vertexFrequency(timeIndex);
    else
        boxCenterFrequency = modeFrequency(timeIndex);
    end

    frequency = frequencies{channelIndex}(:);
    powerSpectralDensity = psdValues{channelIndex}(:);
    localMask = frequency >= boxCenterFrequency - boxHalfWidth & ...
        frequency <= boxCenterFrequency + boxHalfWidth & ...
        isfinite(powerSpectralDensity) & ...
        powerSpectralDensity > 0;

    if nnz(localMask) < 2
        continue
    end

    localPsd = powerSpectralDensity(localMask);
    lowerPsd = max(min(localPsd) * 0.7, realmin);
    upperPsd = max(localPsd) * 1.4;

    rectangle(axesHandle, ...
        'Position', [ ...
        (boxCenterFrequency - boxHalfWidth) / 1e3, ...
        lowerPsd, ...
        2 * boxHalfWidth / 1e3, ...
        upperPsd - lowerPsd], ...
        'EdgeColor', 'r', ...
        'LineWidth', 2.0, ...
        'LineStyle', '-', ...
        'HandleVisibility', 'off');
end
end
