function spectrogramFig = plotPcbSpectrogram(cfg, spectrogramResults, outputLabel)
    if nargin < 3 || isempty(outputLabel)
        outputLabel = "spectrogram";
    end

    numberOfChannels = length(spectrogramResults.channels);
    spectrogramFig = gobjects(numberOfChannels, 1);

    for channelIndex = 1:numberOfChannels
    spectrogramFig(channelIndex) = figure('Name', ...
        outputLabel + " spectrogram " + ...
        spectrogramResults.channels(channelIndex));

    pcolor( ...
        spectrogramResults.time{channelIndex}, ...
        spectrogramResults.frequency{channelIndex} / 1e3, ...
        spectrogramResults.magnitude{channelIndex});

    shading interp;
    xlabel('Time (s)');
    ylabel('Frequency (kHz)');
    title(outputLabel + " spectrogram " + ...
        spectrogramResults.channels(channelIndex));

    colormap(cfg.spectrogram.colormap);
    colorbar;
    ylim(cfg.spectrogram.frequencyBand / 1e3);
    end

    if cfg.analysis.saveSpectrogram
        saveFolder = cfg.analysis.saveSpectrogramFolder;
        if ~exist(saveFolder, 'dir')
            mkdir(saveFolder);
        end
        for channelIndex = 1:numberOfChannels
            saveFileName = fullfile(saveFolder, ...
                outputLabel + "Spectrogram_" + ...
                spectrogramResults.channels(channelIndex) + ".png");
            saveFigureIfValid( ...
                spectrogramFig(channelIndex), ...
                saveFileName);
            fprintf("Spectrogram plot saved to %s\n", saveFileName);
        end
    end
end

function saveFigureIfValid(figureHandle, fileName)
if ~isgraphics(figureHandle, 'figure')
    warning('plotPcbSpectrogram:InvalidFigureHandle', ...
        'Skipping closed or invalid figure: %s', fileName);
    return
end

drawnow;
exportgraphics(figureHandle, fileName, 'Resolution', 300);
end