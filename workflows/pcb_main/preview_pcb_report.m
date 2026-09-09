%% Load analysis results
resultsFile = ...
    "C:\Users\coled\Notre Dame\final_test_pcb_workflow\pcb_analysis_results.mat";

loaded = load(resultsFile, 'results');
results = loaded.results;

% Keep report assets together.
reportFolder = fullfile(fileparts(resultsFile), "report");
figureFolder = fullfile(reportFolder, "figures");

if ~isfolder(figureFolder)
    mkdir(figureFolder);
end

%% Select a PSD window
psd = results.windowedPsd;

assert(isstruct(psd) && isfield(psd, 'powerSpectralDensity'), ...
    'These results do not contain windowed PSD data.');

%% Select a representative PSD window
psd = results.windowedPsd;

% Find helpers relative to this script.
scriptFolder = fileparts(mfilename('fullpath'));
addpath(fullfile(scriptFolder, "reporting"));

% Driver-flat intervals may be absent from some results.
driverFlatWindows = struct('startTime', {}, 'endTime', {});

if isstruct(results.timingDiagnostics) && ...
        isfield(results.timingDiagnostics, 'driverFlatWindows')

    driverFlatWindows = results.timingDiagnostics.driverFlatWindows;
end

% For this step, require a valid quasi-steady interval.
steadyWindow = results.steadyWindow;

assert(isstruct(steadyWindow) && ...
    isfield(steadyWindow, 'startTime') && ...
    isfield(steadyWindow, 'endTime') && ...
    isfinite(steadyWindow.startTime) && ...
    isfinite(steadyWindow.endTime) && ...
    steadyWindow.endTime > steadyWindow.startTime, ...
    'Automatic report selection currently requires a valid quasi-steady interval.');

selection = selectRepresentativePsdWindow( ...
    psd, steadyWindow, driverFlatWindows);

windowIndex = selection.index;

fprintf('Selected PSD window %d: %.4f to %.4f s\n', ...
    windowIndex, selection.startTime, selection.endTime);

fprintf('Selection reason: %s\n', char(selection.reason));

numberOfWindows = numel(psd.windowCenterTime);

assert(windowIndex >= 1 && windowIndex <= numberOfWindows, ...
    'windowIndex must be between 1 and %d.', numberOfWindows);

fprintf('Plotting window %d: %.4f to %.4f s\n', ...
    windowIndex, ...
    psd.windowStartTime(windowIndex), ...
    psd.windowEndTime(windowIndex));

%% Create a report-sized figure
fig = figure( ...
    'Name', 'Report PSD preview', ...
    'Color', 'white', ...
    'Units', 'inches', ...
    'Position', [1 1 6.5 3.5]);

layout = tiledlayout(fig, 1, 1, ...
    'TileSpacing', 'compact', ...
    'Padding', 'compact');

ax = nexttile(layout);
hold(ax, 'on');

channelColors = lines(numel(psd.channels));

for channelIndex = 1:numel(psd.channels)
    spectrum = psd.powerSpectralDensity( ...
        :, windowIndex, channelIndex);

    % Nonpositive values cannot be displayed on a logarithmic scale.
    spectrum(spectrum <= 0) = NaN;

    plot(ax, psd.frequency / 1e3, 10*log10(spectrum), ...
        'Color', channelColors(channelIndex, :), ...
        'LineWidth', 1.2, ...
        'DisplayName', psd.channels(channelIndex));
end

set(ax, ...
    'FontName', 'Times New Roman', ...
    'FontSize', 10, ...
    'LineWidth', 0.75, ...
    'TickDir', 'out', ...
    'Box', 'on');

xlabel(ax, 'Frequency (kHz)');
ylabel(ax, 'PSD (dB)');

xlim(ax, results.cfg.report.psdFrequencyBand / 1e3);

title(ax, sprintf('PSD from %.3f to %.3f s', ...
    psd.windowStartTime(windowIndex), ...
    psd.windowEndTime(windowIndex)), ...
    'FontWeight', 'normal');

legend(ax, 'Location', 'best', 'Interpreter', 'none');
grid(ax, 'on');
ax.GridAlpha = 0.15;

drawnow;

%% Export the figure
pdfFile = fullfile(figureFolder, "representative_psd.pdf");
pngFile = fullfile(figureFolder, "representative_psd.png");

% Vector export: use this version in the LaTeX report.
exportgraphics(ax, pdfFile, ...
    'ContentType', 'vector', ...
    'BackgroundColor', 'white');

% Raster export: useful for quick previews and comparison.
exportgraphics(ax, pngFile, ...
    'Resolution', 300, ...
    'BackgroundColor', 'white');

fprintf('PDF: %s\nPNG: %s\n', pdfFile, pngFile);

%% Build the timing summary
pcb = results.dataData;
timing = results.timingDiagnostics;

% Interval shared by all PCB channels.
recordStart = max(cellfun(@(t) t(1), pcb.time));
recordEnd = min(cellfun(@(t) t(end), pcb.time));

intervalNames = ["Recorded interval"; "Quasi-steady interval"];

startTimes = [
    recordStart
    results.steadyWindow.startTime
];

endTimes = [
    recordEnd
    results.steadyWindow.endTime
];

% Append one row for each detected driver-flat window.
flatWindows = timing.driverFlatWindows;

for k = 1:numel(flatWindows)
    intervalNames(end + 1, 1) = "Driver-flat window " + string(k);
    startTimes(end + 1, 1) = flatWindows(k).startTime;
    endTimes(end + 1, 1) = flatWindows(k).endTime;
end

durationSeconds = endTimes - startTimes;

timingTable = table( ...
    intervalNames, startTimes, endTimes, durationSeconds, ...
    'VariableNames', {'Interval', 'Start_s', 'End_s', 'Duration_s'});

disp(timingTable);
fprintf('Trigger threshold time: %.4f s\n', timing.triggerTime);

%% Format timing values for LaTeX
timingRows = strings(height(timingTable), 1);

for k = 1:height(timingTable)
    values = [
        timingTable.Start_s(k)
        timingTable.End_s(k)
        timingTable.Duration_s(k)
    ];

    formattedValues = compose("%.4f", values);
    formattedValues(~isfinite(values)) = "--";

    timingRows(k) = timingTable.Interval(k) + " & " + ...
        strjoin(formattedValues, " & ") + " \\";
end

triggerText = "Not detected";

if isfinite(timing.triggerTime)
    triggerText = compose("%.4f s", timing.triggerTime);
end

%% Generate trace figures using the existing workflow
scriptFolder = fileparts(mfilename('fullpath'));
addpath(fullfile(scriptFolder, "functions"));

% Use a local configuration copy for report plotting.
traceCfg = results.cfg;
traceCfg.output.saveTracePlots = false;
traceCfg.plotting.fontSize = 10;
traceCfg.plotting.smoothData = false;

traceFigures = plotPcbTraces( ...
    traceCfg, ...
    results.dataData, ...
    results.triggerData, ...
    results.driverData);
%% Style and export the trace panels
panelNames = ["driver", "data", "trigger"];

panelTitles = [
    "Driver tube pressure"
    "PCB traces"
    "Trigger trace"
];

for k = 1:numel(panelNames)
    panelName = panelNames(k);
    traceFig = traceFigures.(char(panelName));
    traceAx = findobj(traceFig, 'Type', 'axes');

    assert(isscalar(traceAx), ...
        'Expected one axes in the %s figure.', char(panelName));

    set(traceFig, ...
        'Color', 'white', ...
        'Units', 'inches', ...
        'Position', [1 1 6.5 1.8]);

    set(traceAx, ...
        'FontName', 'Times New Roman', ...
        'FontSize', 10, ...
        'LineWidth', 0.75, ...
        'TickDir', 'out', ...
        'Box', 'on');

    title(traceAx, panelTitles(k), ...
        'FontSize', 10, 'FontWeight', 'normal');

    xlabel(traceAx, 'Time (s)', 'FontSize', 10);
    traceAx.YLabel.FontSize = 10;

    xlim(traceAx, [recordStart recordEnd]);
    traceAx.GridAlpha = 0.15;
    hold(traceAx, 'on');

    % Mark the trigger event on every panel.
    if isfinite(timing.triggerTime)
        xline(traceAx, timing.triggerTime, ':', ...
            'Color', [0.35 0.35 0.35], ...
            'LineWidth', 1, ...
            'HandleVisibility', 'off');
    end

    % Mark the quasi-steady start and end on every panel.
    steadyBounds = [
        results.steadyWindow.startTime
        results.steadyWindow.endTime
    ];

    for boundary = steadyBounds.'
        if isfinite(boundary)
            xline(traceAx, boundary, '--', ...
                'Color', [0 0.45 0.25], ...
                'LineWidth', 1.2, ...
                'HandleVisibility', 'off');
        end
    end

    % Mark each driver-flat interval above the driver trace.
    if panelName == "driver"
        yLimits = ylim(traceAx);
        markerHeight = yLimits(2) + 0.06*diff(yLimits);

        for j = 1:numel(flatWindows)
            plot(traceAx, ...
                [flatWindows(j).startTime flatWindows(j).endTime], ...
                [markerHeight markerHeight], ...
                'Color', [0.85 0.4 0], ...
                'LineWidth', 3, ...
                'HandleVisibility', 'off');
        end

        ylim(traceAx, [yLimits(1), yLimits(2) + 0.15*diff(yLimits)]);
    end

    legend(traceAx, 'Location', 'best', ...
        'FontSize', 9, 'Interpreter', 'none');

    drawnow;

    exportgraphics(traceAx, ...
        fullfile(figureFolder, "trace_" + panelName + ".png"), ...
        'Resolution', 300, ...
        'BackgroundColor', 'white');
end
%% Build the second-mode comparison and history from saved detections
[secondModeTex, secondModeTable, secondModeFigure] = ...
    createSecondModeReportSection(results, figureFolder);
disp(secondModeTable);

%% Assemble a minimal LaTeX report
texLines = [
    "\documentclass[11pt,letterpaper]{article}"
    "\usepackage[margin=1in]{geometry}"
    "\usepackage{graphicx}"
    "\usepackage{booktabs}"
    ""
    "\begin{document}"
    ""
    "\begin{center}"
    "  {\Large\bfseries PCB Analysis Preview}\\[4pt]"
    "  MATLAB-generated analysis report"
    "\end{center}"
    ""
        "\section*{Trace overview}"
    "\begin{center}"
    "\includegraphics[width=0.97\linewidth]{figures/trace_driver.png}\\[4pt]"
    "\includegraphics[width=0.97\linewidth]{figures/trace_data.png}\\[4pt]"
    "\includegraphics[width=0.97\linewidth]{figures/trace_trigger.png}"
    "\end{center}"
    "{\small Green dashed lines mark the quasi-steady boundaries."
    "The dotted line marks the trigger threshold time."
    "Orange bars above the driver trace mark driver-flat windows.}"
    ""
    "\clearpage"
    "\section*{Timing summary}"
    "All timestamps use the recorded time coordinate."
    "Recorded duration is the common PCB record end minus its start."
    ""
    "\begin{center}"
    "\begin{tabular}{lrrr}"
    "\toprule"
    "Interval & Start (s) & End (s) & Duration (s) \\"
    "\midrule"
    timingRows
    "\bottomrule"
    "\end{tabular}"
    "\end{center}"
    ""
    "Trigger threshold time: " + triggerText + "."
    ""
    "\clearpage"
    "\section*{Selected analysis window}"
    "The representative PSD window was selected automatically using the detected timing intervals."
    compose("Selection criterion: %s.", selection.reason)
    ""
    "\begin{center}"
    "\begin{tabular}{lr}"
    "\toprule"
    "Quantity & Value \\"
    "\midrule"
    compose("Window index & %d \\\\", windowIndex)
    compose("Start time (s) & %.4f \\\\", psd.windowStartTime(windowIndex))
    compose("End time (s) & %.4f \\\\", psd.windowEndTime(windowIndex))
    compose("PCB channels & %d \\\\", numel(psd.channels))
    "\bottomrule"
    "\end{tabular}"
    "\end{center}"
    ""
    "\begin{figure}[htbp]"
    "  \centering"
    "  \includegraphics[width=\linewidth]{figures/representative_psd.pdf}"
    "  \caption{Channel PSDs for the selected window. The decibel reference remains to be specified.}"
    "  \label{fig:psd}"
    "\end{figure}"
    ""
    secondModeTex
    "\end{document}"
];

texContent = strjoin(texLines, newline);

%% Write the LaTeX source
texFile = fullfile(reportFolder, "report.tex");

[fid, message] = fopen(texFile, 'w', 'n', 'UTF-8');

assert(fid ~= -1, ...
    'Could not open report file: %s', message);

try
    fprintf(fid, '%s\n', char(texContent));
catch exception
    fclose(fid);
    rethrow(exception);
end

fclose(fid);

fprintf('LaTeX source written to:\n%s\n', texFile);

%% Compile the LaTeX report
originalFolder = pwd;

try
    cd(reportFolder);

    command = ...
        'pdflatex -interaction=nonstopmode -halt-on-error report.tex';

    % Two passes allow LaTeX to resolve references and numbering.
    for pass = 1:2
        fprintf('LaTeX compilation: pass %d\n', pass);

        [status, compilerOutput] = system(command);

        if status ~= 0
            fprintf('%s\n', compilerOutput);
            error('previewPcbReport:CompilationFailed', ...
                'LaTeX compilation failed. See the output above and report.log.');
        end
    end

catch exception
    cd(originalFolder);
    rethrow(exception);
end

cd(originalFolder);

reportPdf = fullfile(reportFolder, "report.pdf");

assert(isfile(reportPdf), ...
    'Compilation finished, but the report PDF was not found.');

fprintf('Report created:\n%s\n', reportPdf);

%% Open the compiled report
winopen(reportPdf);
