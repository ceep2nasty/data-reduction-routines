%% Play a saved PCB spectral movie
clear; close all; clc

movieFile = cfg.movie.outputFile;

if ~isfile(movieFile)
    error('Movie file not found: %s', movieFile);
end

videoReader = VideoReader(movieFile);
playerFigure = figure('Name', 'PCB spectral movie player', 'Color', 'k');
playerAxes = axes('Parent', playerFigure);

while hasFrame(videoReader) && isgraphics(playerFigure)
    frame = readFrame(videoReader);
    imshow(frame, 'Parent', playerAxes);
    drawnow;
end
