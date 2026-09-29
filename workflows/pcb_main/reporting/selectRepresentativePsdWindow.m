function selection = selectRepresentativePsdWindow( ...
    windowedPsd, steadyWindow, driverFlatWindows)
%SELECTREPRESENTATIVEPSDWINDOW Select a reproducible report PSD window.
%
% Preference order:
%   1. Completely inside the quasi-steady interval and a driver-flat window.
%   2. Completely inside the quasi-steady interval.
%   3. Greatest overlap with the quasi-steady interval.
%
% Ties are resolved by proximity to the quasi-steady midpoint.

validateattributes(windowedPsd.windowStartTime, ...
    {'numeric'}, {'vector', 'real', 'finite'});
validateattributes(windowedPsd.windowEndTime, ...
    {'numeric'}, {'vector', 'real', 'finite'});
validateattributes(windowedPsd.windowCenterTime, ...
    {'numeric'}, {'vector', 'real', 'finite'});

windowStart = windowedPsd.windowStartTime(:);
windowEnd = windowedPsd.windowEndTime(:);
windowCenter = windowedPsd.windowCenterTime(:);

if isempty(windowCenter)
    error('selectRepresentativePsdWindow:NoWindows', ...
        'No windowed PSD results are available.');
end

hasSteadyWindow = ...
    isstruct(steadyWindow) && ...
    isfield(steadyWindow, 'startTime') && ...
    isfield(steadyWindow, 'endTime') && ...
    isfinite(steadyWindow.startTime) && ...
    isfinite(steadyWindow.endTime) && ...
    steadyWindow.endTime > steadyWindow.startTime;

if hasSteadyWindow
    targetStart = steadyWindow.startTime;
    targetEnd = steadyWindow.endTime;
else
    targetStart = min(windowStart);
    targetEnd = max(windowEnd);
end

targetCenter = mean([targetStart targetEnd]);

insideSteady = ...
    windowStart >= targetStart & ...
    windowEnd <= targetEnd;

insideDriverFlat = false(size(windowStart));

if nargin >= 3 && ~isempty(driverFlatWindows)
    for flatIndex = 1:numel(driverFlatWindows)
        flatStart = driverFlatWindows(flatIndex).startTime;
        flatEnd = driverFlatWindows(flatIndex).endTime;

        if ~isfinite(flatStart) || ~isfinite(flatEnd)
            continue
        end

        insideDriverFlat = insideDriverFlat | ...
            (windowStart >= flatStart & windowEnd <= flatEnd);
    end
end

preferredMask = insideSteady & insideDriverFlat;

if any(preferredMask)
    candidates = find(preferredMask);
    reason = "inside quasi-steady and driver-flat intervals";
    usedFallback = false;

elseif any(insideSteady)
    candidates = find(insideSteady);
    reason = "inside quasi-steady interval";
    usedFallback = false;

else
    overlap = max(0, ...
        min(windowEnd, targetEnd) - ...
        max(windowStart, targetStart));

    maximumOverlap = max(overlap);
    candidates = find(overlap == maximumOverlap);
    reason = "greatest available overlap with quasi-steady interval";
    usedFallback = true;
end

[~, nearestIndex] = min( ...
    abs(windowCenter(candidates) - targetCenter));

selectedIndex = candidates(nearestIndex);

selection = struct();
selection.index = selectedIndex;
selection.startTime = windowStart(selectedIndex);
selection.endTime = windowEnd(selectedIndex);
selection.centerTime = windowCenter(selectedIndex);
selection.targetCenterTime = targetCenter;
selection.reason = reason;
selection.usedFallback = usedFallback;
selection.insideQuasiSteady = insideSteady(selectedIndex);
selection.insideDriverFlat = insideDriverFlat(selectedIndex);
end