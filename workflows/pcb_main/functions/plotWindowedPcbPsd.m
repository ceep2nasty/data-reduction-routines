function figures = plotWindowedPcbPsd(cfg, psdResults)
%PLOTWINDOWEDPCBPSD Save all PSD windows and independently preview selections.
% Returned handles contain only preview figures. Export-only figures are
% created invisibly and closed immediately after saving.

windowCount = numel(psdResults.windowCenterTime);
requestedIndices = cfg.psd.previewWindowIndices;
if ~cfg.run.windowedPsdPreview
    requestedIndices = [];
end
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
if isempty(windowIndices) && cfg.run.windowedPsdPreview
    warning('plotWindowedPcbPsd:NoAvailableWindows', ...
        'No requested PSD preview windows are available.');
end
windowIndices = unique(windowIndices, 'stable');
renderIndices = windowIndices;
if cfg.output.saveWindowedPsdPlots
    renderIndices = 1:windowCount;
end

if cfg.output.saveWindowedPsdPlots && ...
        ~isfolder(cfg.output.windowedPsdFolder)
    mkdir(cfg.output.windowedPsdFolder);
end

figures = gobjects(numel(windowIndices), 1);
frequencyKHz = psdResults.frequency / 1e3;
plotBandKHz = cfg.psd.plotFrequencyBand / 1e3;
colors = lines(numel(psdResults.channels));

for windowIndex = renderIndices
    previewIndex = find(windowIndices == windowIndex, 1);
    figureName = sprintf('PCB PSD %.4f-%.4f s', ...
        psdResults.windowStartTime(windowIndex), ...
        psdResults.windowEndTime(windowIndex));
    plotFigure = figure('Name', figureName, ...
        'Position', cfg.plotting.figurePosition, 'Visible', 'off');
    % Also release an export-only figure if plotting or saving fails.
    cleanupFigure = onCleanup(@() closeExportFigure(plotFigure, isempty(previewIndex)));
    axesHandle = axes('Parent', plotFigure);
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
        exportgraphics(axesHandle, fullfile( ...
            cfg.output.windowedPsdFolder, fileName), 'Resolution', 300);
    end
    if ~isempty(previewIndex)
        figures(previewIndex) = plotFigure;
        set(plotFigure, 'Visible', 'on');
    end
    clear cleanupFigure
end
end

function closeExportFigure(fig, exportOnly)
if exportOnly && isgraphics(fig)
    close(fig);
end
end
