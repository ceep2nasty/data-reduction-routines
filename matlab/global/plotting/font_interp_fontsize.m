%Custom plot settings
% Set global defaults for figures
set(groot, 'defaultAxesFontName', 'Times New Roman');
set(groot, 'defaultTextFontName', 'Times New Roman');
set(groot, 'defaultAxesFontSize', UseFontSizeGloabl);
set(groot, 'defaultTextFontSize', UseFontSizeGloabl);
% Enable LaTeX interpreter globally
set(groot, 'defaultTextInterpreter', 'latex');
set(groot, 'defaultLegendInterpreter', 'latex');
set(groot, 'defaultAxesTickLabelInterpreter', 'latex');
% Set default figure and axes colors to white
set(groot, 'defaultFigureColor', 'w');   % gcf background
set(groot, 'defaultAxesColor', 'w');     % gca background