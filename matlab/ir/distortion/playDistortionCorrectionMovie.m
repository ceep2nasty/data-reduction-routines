function playDistortionCorrectionMovie(Calibration_Data, Data_Distort_Corrected)
% playDistortionCorrectionMovie - Plays a side-by-side movie of RAW, corrected, and difference images.
%
% Inputs:
%   Calibration_Data         - 3D matrix of raw image frames (HxWxN)
%   Data_Distort_Corrected   - 3D matrix of distortion-corrected frames (HxWxN)

    % Set colormaps
    ColormapUse = flipud(gray); 
    DifferenceMap = turbo;

    % Get number of frames
    numFrames = size(Calibration_Data, 3);

    % Create figure and tiled layout
    figure('Name', 'Distortion Correction Movie', 'Color', 'w');
    t = tiledlayout(1, 3, 'Padding', 'compact', 'TileSpacing', 'compact');
    
    % Pre-create axes
    ax1 = nexttile; % Corrected
    ax2 = nexttile; % RAW
    ax3 = nexttile; % Difference

    % Loop through frames
    for Frame = 1:numFrames
        % Corrected
        surf(ax1, Data_Distort_Corrected(:,:,Frame));
        view(ax1, 2); shading(ax1, 'interp'); axis(ax1, 'equal', 'tight');
        title(ax1, sprintf('Corrected - Frame %d', Frame));
        colormap(ax1, ColormapUse);

        % RAW
        surf(ax2, Calibration_Data(:,:,Frame));
        view(ax2, 2); shading(ax2, 'interp'); axis(ax2, 'equal', 'tight');
        title(ax2, 'RAW');
        colormap(ax2, ColormapUse);

        % Difference
        surf(ax3, Data_Distort_Corrected(:,:,Frame) - Calibration_Data(:,:,Frame));
        view(ax3, 2); shading(ax3, 'interp'); axis(ax3, 'equal', 'tight');
        title(ax3, 'Difference');
        colormap(ax3, DifferenceMap);

        drawnow;
        pause(0.05); % Playback speed
    end
end
