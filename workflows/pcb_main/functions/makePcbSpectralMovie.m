function makePcbSpectralMovie( ...
    cfg, dataData, secondModeResults, outputFile)
%MAKEPCBSPECTRALMOVIE Create a PSD and mode-history analysis movie.

if nargin < 4 || isempty(outputFile)
    error('makePcbSpectralMovie:MissingOutputFile', ...
        'An output MP4 filename is required.');
end

if ~endsWith(string(outputFile), '.mp4', 'IgnoreCase', true)
    error('makePcbSpectralMovie:InvalidOutputFile', ...
        'The movie output must have an .mp4 extension.');
end

if isempty(secondModeResults.time) || ...
        isempty(secondModeResults.time{1})
    error('makePcbSpectralMovie:MissingTime', ...
        'Second-mode time history is empty.');
end

frameTime = secondModeResults.time{1}(:);
frameStep = getMovieValue(cfg, 'frameStep', 1);
frameIndices = 1:frameStep:numel(frameTime);

videoWriter = VideoWriter(char(outputFile), 'MPEG-4');
videoWriter.FrameRate = getMovieValue(cfg, 'frameRate', 10);
open(videoWriter);

movieFigure = figure( ...
    'Name', 'PCB second-mode spectral movie', ...
    'Color', 'w', ...
    'Visible', 'off');
cleanupObject = onCleanup(@() closeMovie(movieFigure, videoWriter));

for framePosition = 1:numel(frameIndices)
    timeIndex = frameIndices(framePosition);
    currentTime = frameTime(timeIndex);

    clf(movieFigure);
    layout = tiledlayout(movieFigure, 2, 1, ...
        'TileSpacing', 'compact', ...
        'Padding', 'compact');

    psdAxes = nexttile(layout, 1);
    hold(psdAxes, 'on');
    grid(psdAxes, 'on');
    box(psdAxes, 'on');
    set(psdAxes, 'YScale', 'log');
    colors = lines(numel(dataData.channels));
    frameFrequencies = cell(numel(dataData.channels), 1);
    framePsdValues = cell(numel(dataData.channels), 1);

    for channelIndex = 1:numel(dataData.channels)
        channelTime = dataData.time{channelIndex};
        channelSignal = dataData.signal{channelIndex};
        channelTime = channelTime - channelTime(1);
        halfWindow = cfg.movie.psdWindowDuration / 2;
        sampleMask = channelTime >= currentTime - halfWindow & ...
            channelTime <= currentTime + halfWindow;
        selectedSignal = channelSignal(sampleMask);

        if strcmpi(string(cfg.psd.detrend), "linear")
            selectedSignal = detrend(selectedSignal, 1);
        elseif strcmpi(string(cfg.psd.detrend), "constant")
            selectedSignal = detrend(selectedSignal, 0);
        end

        [frequency, powerSpectralDensity] = computePcbPsdWindow( ...
            selectedSignal, dataData.samplingRate, cfg);

        if ~isempty(frequency)
            frameFrequencies{channelIndex} = frequency;
            framePsdValues{channelIndex} = powerSpectralDensity;
            plot(psdAxes, frequency / 1e3, powerSpectralDensity, ...
                'Color', colors(channelIndex, :), ...
                'LineWidth', 1.5, ...
                'DisplayName', char(dataData.channels(channelIndex)));
        end
    end

    xline(psdAxes, cfg.secondMode.frequencyBand(1) / 1e3, ...
        'k--', 'HandleVisibility', 'off');
    xline(psdAxes, cfg.secondMode.frequencyBand(2) / 1e3, ...
        'k--', 'HandleVisibility', 'off');
    xlim(psdAxes, cfg.psd.frequencyBand / 1e3);
    xlabel(psdAxes, 'Frequency (kHz)');
    ylabel(psdAxes, 'PSD ((signal units)^2/Hz)');
    title(psdAxes, sprintf('Windowed PCB PSD, t = %.6f s', currentTime));
    legend(psdAxes, 'Location', 'southwest');

    plotSecondModeCandidateBoxes( ...
        psdAxes, ...
        cfg, ...
        secondModeResults, ...
        currentTime, ...
        frameFrequencies, ...
        framePsdValues);

    historyAxes = nexttile(layout, 2);
    hold(historyAxes, 'on');
    grid(historyAxes, 'on');
    box(historyAxes, 'on');

    for channelIndex = 1:numel(secondModeResults.channels)
        plot(historyAxes, ...
            secondModeResults.time{channelIndex}, ...
            secondModeResults.frequencyTrace{channelIndex} / 1e3, ...
            'LineWidth', 1.2, ...
            'DisplayName', char(secondModeResults.channels(channelIndex)));
    end

    xline(historyAxes, currentTime, 'r-', ...
        'LineWidth', 1.2, ...
        'DisplayName', 'Current time');
    xlabel(historyAxes, 'Time (s)');
    ylabel(historyAxes, 'Second-mode frequency (kHz)');
    title(historyAxes, 'Tracked second-mode frequency history');
    legend(historyAxes, 'Location', 'best');

    drawnow;
    writeVideo(videoWriter, getframe(movieFigure));
end

clear cleanupObject
closeMovie(movieFigure, videoWriter);
fprintf('PCB spectral movie saved to %s\n', outputFile);
end

function value = getMovieValue(cfg, fieldName, defaultValue)
if isfield(cfg, 'movie') && isfield(cfg.movie, fieldName) && ...
        ~isempty(cfg.movie.(fieldName))
    value = cfg.movie.(fieldName);
else
    value = defaultValue;
end
end

function closeMovie(movieFigure, videoWriter)
try
    close(videoWriter);
catch
end
if isgraphics(movieFigure)
    close(movieFigure);
end
end
