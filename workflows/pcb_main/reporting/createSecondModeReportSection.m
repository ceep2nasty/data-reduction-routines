function [texLines, comparison, fig] = createSecondModeReportSection(results, figureFolder)
%CREATESECONDMODEREPORTSECTION Compare raw window detections and plot history.
% Missing detections remain gaps; no frequencies are interpolated or bridged.

texLines = ["\clearpage"; "\section*{Second-mode comparison}"];
comparison = table();
fig = gobjects(0);
if ~isstruct(results.secondMode) || isempty(results.secondMode) || ...
        ~isfield(results.secondMode, 'windowCenterTime') || ...
        isempty(results.secondMode.windowCenterTime)
    texLines(end+1) = "Second-mode analysis was not computed or contains no windows.";
    return
end

mode = results.secondMode;
channels = string(results.windowedPsd.channels(:));
count = numel(channels);
status = repmat("Excluded", count, 1);
detected = zeros(count, 1);
total = nan(count, 1);
medianKHz = nan(count, 1);
iqrKHz = nan(count, 1);
prominenceDb = nan(count, 1);
firstCenter = nan(count, 1);
lastCenter = nan(count, 1);
colors = lines(count);

fig = figure('Name', 'Second-mode history', 'Color', 'white', ...
    'Units', 'inches', 'Position', [1 1 6.5 3.5]);
ax = axes('Parent', fig);
hold(ax, 'on');
rows = strings(count, 1);
for k = 1:count
    source = find(string(mode.channels) == channels(k), 1);
    detectionText = "--";
    if ~isempty(source)
        frequency = mode.frequency(:, source);
        valid = mode.found(:, source) & isfinite(frequency);
        detected(k) = nnz(valid);
        total(k) = numel(valid);
        status(k) = "Not detected";
        detectionText = compose("%d/%d", detected(k), total(k));
        if any(valid)
            status(k) = "Detected";
            medianKHz(k) = median(frequency(valid)) / 1e3;
            iqrKHz(k) = iqr(frequency(valid)) / 1e3;
            prominenceDb(k) = median(mode.prominenceDb(valid, source), 'omitnan');
            times = mode.windowCenterTime(:);
            firstCenter(k) = times(find(valid, 1, 'first'));
            lastCenter(k) = times(find(valid, 1, 'last'));
        end
        frequency(~valid) = NaN;
        plot(ax, mode.windowCenterTime, frequency / 1e3, '-o', ...
            'Color', colors(k,:), 'LineWidth', 1.2, 'MarkerSize', 4, ...
            'DisplayName', channels(k));
    end
    values = [medianKHz(k), iqrKHz(k), prominenceDb(k)];
    labels = compose("%.2f", values);
    labels(~isfinite(values)) = "--";
    rows(k) = escapeLatex(channels(k)) + " & " + status(k) + " & " + ...
        detectionText + " & " + strjoin(labels, " & ") + " \\";
end

comparison = table(channels, status, detected, total, medianKHz, iqrKHz, ...
    prominenceDb, firstCenter, lastCenter, 'VariableNames', ...
    {'Channel','Status','DetectedWindows','TotalWindows','MedianFrequency_kHz', ...
    'FrequencyIQR_kHz','MedianProminence_dB','FirstDetectionCenter_s', ...
    'LastDetectionCenter_s'});

set(ax, 'FontName', 'Times New Roman', 'FontSize', 10, ...
    'TickDir', 'out', 'Box', 'on');
xlabel(ax, 'PSD window center time (s)');
ylabel(ax, 'Second-mode frequency (kHz)');
grid(ax, 'on');
ax.GridAlpha = 0.15;
xlim(ax, [min(mode.windowStartTime), max(mode.windowEndTime)]);
ylim(ax, results.cfg.secondMode.frequencyBand / 1e3);
legend(ax, 'Location', 'best', 'Interpreter', 'none');
if ~any(detected)
    text(ax, 0.5, 0.5, 'No second-mode peaks detected', ...
        'Units', 'normalized', 'HorizontalAlignment', 'center');
end
drawnow;
exportgraphics(ax, fullfile(figureFolder, 'second_mode_history.pdf'), ...
    'ContentType', 'vector', 'BackgroundColor', 'white');

texLines = [texLines
    "\begin{center}"
    "\small"
    "\setlength{\tabcolsep}{4pt}"
    "\begin{tabular}{llrrrr}"
    "\toprule"
    "Channel & Status & Windows & Median & IQR & Prominence \\"
    " & & detected/total & (kHz) & (kHz) & (dB) \\"
    "\midrule"
    rows
    "\bottomrule"
    "\end{tabular}"
    "\end{center}"
    "Statistics use finite raw peak detections across the analyzed PSD windows."
    "IQR is the interquartile range of detected frequencies, not an uncertainty estimate."
    "Excluded channels were not analyzed; missing values are shown as dashes."
    "\begin{figure}[htbp]"
    "\centering"
    "\includegraphics[width=\linewidth]{figures/second_mode_history.pdf}"
    "\caption{Second-mode frequency at each PSD window center. Gaps indicate missing detections; lines join adjacent detected windows only. No persistence filtering or gap bridging is applied.}"
    "\end{figure}"
];
end

function output = escapeLatex(input)
characters = char(input);
parts = strings(1, numel(characters));
for k = 1:numel(characters)
    switch characters(k)
        case '\'
            parts(k) = "\textbackslash{}";
        case {'_', '%', '&', '#', '$', '{', '}'}
            parts(k) = "\" + string(characters(k));
        case '^'
            parts(k) = "\textasciicircum{}";
        case '~'
            parts(k) = "\textasciitilde{}";
        otherwise
            parts(k) = string(characters(k));
    end
end
output = join(parts, "");
end
