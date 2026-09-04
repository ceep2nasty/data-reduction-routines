function spectrogramFig = plotPcbSpectrogram(cfg, spectrogramResults)
    % Implementation for plotting spectrograms
    for channelIndex = 1:length(spectrogramResults.channels)
    spectrogramFig = figure('Name', ...
        "Spectrogram " + spectrogramResults.channels(channelIndex));

    pcolor( ...
        spectrogramResults.time{channelIndex}, ...
        spectrogramResults.frequency{channelIndex} / 1e3, ...
        spectrogramResults.magnitude{channelIndex});

    shading interp;
    xlabel('Time (s)');
    ylabel('Frequency (kHz)');
    title("Spectrogram " + ...
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
        for channelIndex = 1:length(spectrogramResults.channels)
            saveFileName = fullfile(saveFolder, ...
                "spectrogram_" + spectrogramResults.channels(channelIndex) + ".png");
            saveas(spectrogramFig, saveFileName);
            fprintf("Spectrogram plot saved to %s\n", saveFileName);
        end
    end
end