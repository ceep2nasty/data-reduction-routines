function spectrogramResults = computePcbSpectrogram(cfg, dataData)
    % Initialize the output structure
    spectrogramResults = struct();

    spectrogramResults.channels = dataData.channels;
    spectrogramResults.time = cell(size(dataData.channels));
    spectrogramResults.frequency = cell(size(dataData.channels));
    spectrogramResults.magnitude = cell(size(dataData.channels));

    % Loop through each data channel to compute the spectrogram
    for i = 1:length(dataData.channels) 
        signal = dataData.signal{i};
        samplingRate = dataData.samplingRate;
            [time, frequency, magnitude] = Spectrogram( ...
        signal, ...
        samplingRate, ...
        cfg.spectrogram.windowLength, ...
        cfg.spectrogram.overlap, ...
        cfg.spectrogram.colormap, ...
        cfg.spectrogram.frequencyBand);
        
        spectrogramResults.time{i} = time;
        spectrogramResults.frequency{i} = frequency;
        spectrogramResults.magnitude{i} = magnitude;

    end

    % save outputs
    if cfg.analysis.saveSpectrogram
        saveFolder = cfg.analysis.saveSpectrogramFolder;
        if ~exist(saveFolder, 'dir')
            mkdir(saveFolder);
        end
        saveFileName = fullfile(saveFolder, 'spectrogramResults.mat');
        save(saveFileName, 'spectrogramResults');
        fprintf("Spectrogram results saved to %s\n", saveFileName);
    end
    
    fprintf("Spectrogram computation completed for %d channels\n", length(dataData.channels));
end