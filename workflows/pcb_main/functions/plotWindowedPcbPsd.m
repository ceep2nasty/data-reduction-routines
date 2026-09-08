function figures = plotWindowedPcbPsd(cfg, psdResults)
%PLOTWINDOWEDPCBPSD Plot selected windowed PSDs for all PCB channels.

windowCount = numel(psdResults.windowCenterTime);
requestedIndices = cfg.psd.previewWindowIndices;
if isstring(requestedIndices) && requestedIndices == "all"
    windowIndices = 1:windowCount;
else
    windowIndices = requestedIndices(:).';
end

unavailableIndices = windowIndices(windowIndices > windowCount);
if ~isempty(unavailableIndices)
    warning('plotWindowedPcbPsd:WindowIndexOutOfRange', ...
        ['Skipping preview window indices [%s]; only %d PSD ', ...
        'window(s) are available.'], num2str(unavailableIndices), windowCount);
    windowIndices(windowIndices > windowCount) = [];
end
if isempty(windowIndices)
    warning('plotWindowedPcbPsd:NoAvailableWindows', ...
        'No requested PSD preview windows are available.');
    figures = gobjects(0, 1);
    return
end

if cfg.output.saveWindowedPsdPlots && ...
        ~isfolder(cfg.output.windowedPsdFolder)
    mkdir(cfg.output.windowedPsdFolder);
end

figures = gobjects(numel(windowIndices), 1);
frequencyKHz = psdResults.frequency / 1e3;
plotBandKHz = cfg.psd.plotFrequencyBand / 1e3;
colors = lines(numel(psdResults.channels));

for plotIndex = 1:numel(windowIndices)
    windowIndex = windowIndices(plotIndex);
    figureName = sprintf('PCB PSD %.4f-%.4f s', ...
        psdResults.windowStartTime(windowIndex), ...
        psdResults.windowEndTime(windowIndex));
    figures(plotIndex) = figure('Name', figureName, ...
        'Position', cfg.plotting.figurePosition);
    axesHandle = axes('Parent', figures(plotIndex));
    hold(axesHandle, 'on');
    grid(axesHandle, 'on');
    box(axesHandle, 'on');

    for channelIndex = 1:numel(psdResults.channels)
        channelPsd = psdResults.powerSpectralDensity( ...
            :, windowIndex, channelIndex);
        plot(axesHandle, frequencyKHz, pow2db(channelPsd), ...
            'LineWidth', 1.5, ...
            'Color', colors(channelIndex, :), ...
            'DisplayName', psdResults.channels(channelIndex));
    end

    xlim(axesHandle, plotBandKHz);
    xlabel(axesHandle, 'Frequency (kHz)');
    ylabel(axesHandle, 'PSD (dB/Hz)');
    title(axesHandle, sprintf('PCB PSD: %.4f to %.4f s', ...
        psdResults.windowStartTime(windowIndex), ...
        psdResults.windowEndTime(windowIndex)));
    legend(axesHandle, 'Location', 'best');

    if cfg.output.saveWindowedPsdPlots
        fileName = sprintf('pcb_psd_%07.4f_%07.4f_s.png', ...
            psdResults.windowStartTime(windowIndex), ...
            psdResults.windowEndTime(windowIndex));
        exportgraphics(figures(plotIndex), fullfile( ...
            cfg.output.windowedPsdFolder, fileName), 'Resolution', 300);
    end
end
end
