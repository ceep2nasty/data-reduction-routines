function plotWithUncertainty(x, y, uncert, lineColor, lineWidth, alpha,StringLegendName)
% plotWithUncertainty: Plots a curve with shaded uncertainty band
%
% Inputs:
%   x         : x-axis data (vector)
%   y         : y-axis data (vector)
%   uncert    : scalar or vector for uncertainty (same size as y)
%   lineColor : RGB vector or color spec for main line
%   lineWidth : line width of main curve
%   alpha     : transparency of the shaded region (0-1)
%
% Example:
%   plotWithUncertainty(xvec, ShearLoc_WN, 0.16, [0 0.4470 0.7410], 3, 0.3)

    if nargin < 6
        alpha = 0.3; % default transparency
    end
    if nargin < 5
        lineWidth = 2; % default line width
    end
    if nargin < 4
        lineColor = [0 0 1]; % default color blue
    end

    % If uncertainty is scalar, make it a vector
    if isscalar(uncert)
        uncert = uncert * ones(size(y));
    end

    % Shaded region
    y_upper = y + uncert;
    y_lower = y - uncert;
    hold on;
    fill([x, fliplr(x)], [y_upper, fliplr(y_lower)], lineColor, ...
         'FaceAlpha', alpha, 'EdgeColor', 'none','HandleVisibility','off');

    % Main line on top
    plot(x, y, '-', 'Color', lineColor, 'LineWidth', lineWidth,'DisplayName',StringLegendName);

end