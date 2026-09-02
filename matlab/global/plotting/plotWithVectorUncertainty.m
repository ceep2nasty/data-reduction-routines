function plotWithVectorUncertainty(x, y, uncert, lineColor, lineWidth, alpha, StringLegendName)
% plotWithVectorUncertainty: Plots a curve with shaded uncertainty band
%
% Inputs:
%   x         : x-axis data (vector)
%   y         : y-axis data (vector)
%   uncert    : vector of uncertainties (same size as y)
%   lineColor : RGB vector or color spec for main line
%   lineWidth : line width of main curve
%   alpha     : transparency of the shaded region (0-1)
%   StringLegendName : legend entry for the main curve
%
% Example:
%   plotWithVectorUncertainty(xvec, ShearLoc_WN, uncertVec, [0 0.4470 0.7410], 3, 0.3, 'Shear Layer')

    % Defaults
    if nargin < 7
        StringLegendName = '';
    end
    if nargin < 6
        alpha = 0.3;
    end
    if nargin < 5
        lineWidth = 2;
    end
    if nargin < 4
        lineColor = [0 0 1];
    end

    % Check input size
    if ~isvector(uncert) || length(uncert) ~= length(y)
        error('Uncertainty must be a vector of the same length as y.');
    end

    % Upper and lower bounds
    y_upper = y + uncert; y_upper = fillmissing(y_upper,'linear');
    y_lower = y - uncert;  y_lower = fillmissing(y_lower,'linear');

    % Shaded band
    hold on;
    fill([x(:); flipud(x(:))], [y_upper(:); flipud(y_lower(:))], ...
         lineColor, 'FaceAlpha', alpha, 'EdgeColor', 'none', 'HandleVisibility','off');

    % Main curve
    % plot(x, y, '-', 'Color', lineColor, 'LineWidth', lineWidth, 'DisplayName', StringLegendName, 'HandleVisibility','off');

end