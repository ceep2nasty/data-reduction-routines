function [psdResults, figures] = plotPcbSpectra( ...
	cfg, dataData, secondModeResults)
%PLOTPCBSPECTRA Plot windowed PCB PSDs with mode-history insets.

if ~isfield(cfg, 'psd') || ~isfield(cfg.psd, 'windowList')
	error('plotPcbSpectra:MissingConfiguration', ...
		'cfg.psd.windowList is required.');
end

if cfg.analysis.savePsdPlots && ...
		~isfolder(cfg.analysis.savePsdPlotsFolder)
	mkdir(cfg.analysis.savePsdPlotsFolder);
end

numberOfWindows = size(cfg.psd.windowList, 1);
numberOfChannels = numel(dataData.channels);
psdResults = repmat(struct( ...
	'timeWindow', [], ...
	'frequency', [], ...
	'powerSpectralDensity', []), numberOfWindows, 1);
figures = gobjects(numberOfWindows, 1);

for windowIndex = 1:numberOfWindows
	timeWindow = cfg.psd.windowList(windowIndex, :);
	figures(windowIndex) = figure('Name', sprintf( ...
		'PCB PSD %.4f-%.4f s', timeWindow(1), timeWindow(2)));
	axesHandle = axes(figures(windowIndex));
	hold(axesHandle, 'on');
	grid(axesHandle, 'on');
	box(axesHandle, 'on');
	set(axesHandle, 'YScale', 'log');

	psdResults(windowIndex).timeWindow = timeWindow;
	colors = lines(numberOfChannels);
	windowFrequencies = cell(numberOfChannels, 1);
	windowPsdValues = cell(numberOfChannels, 1);

	for channelIndex = 1:numberOfChannels
		channelTime = dataData.time{channelIndex};
		channelSignal = dataData.signal{channelIndex};
		if ~isempty(channelTime)
			channelTime = channelTime - channelTime(1);
		end
		sampleMask = channelTime >= timeWindow(1) & ...
			channelTime <= timeWindow(2);
		selectedSignal = channelSignal(sampleMask);

		if strcmpi(string(cfg.psd.detrend), "linear")
			selectedSignal = detrend(selectedSignal, 1);
		elseif strcmpi(string(cfg.psd.detrend), "constant")
			selectedSignal = detrend(selectedSignal, 0);
		end

		[frequency, powerSpectralDensity] = computePcbPsdWindow( ...
			selectedSignal, dataData.samplingRate, cfg);

		if channelIndex == 1
			psdResults(windowIndex).frequency = frequency;
			psdResults(windowIndex).powerSpectralDensity = ...
				nan(numel(frequency), numberOfChannels);
		end

		if ~isempty(frequency)
			windowFrequencies{channelIndex} = frequency;
			windowPsdValues{channelIndex} = powerSpectralDensity;
			psdResults(windowIndex).powerSpectralDensity(:, channelIndex) = ...
				powerSpectralDensity;
			plot(axesHandle, frequency / 1e3, powerSpectralDensity, ...
				'Color', colors(channelIndex, :), ...
				'LineWidth', 1.5, ...
				'DisplayName', char(dataData.channels(channelIndex)));
		end
	end

	xline(axesHandle, cfg.secondMode.frequencyBand(1) / 1e3, ...
		'k--', 'HandleVisibility', 'off');
	xline(axesHandle, cfg.secondMode.frequencyBand(2) / 1e3, ...
		'k--', 'HandleVisibility', 'off');
	xlim(axesHandle, cfg.psd.frequencyBand / 1e3);
	xlabel(axesHandle, 'Frequency (kHz)');
	ylabel(axesHandle, 'PSD ((signal units)^2/Hz)');
	title(axesHandle, sprintf( ...
		'PCB PSD: %.4f to %.4f s', timeWindow(1), timeWindow(2)));
	legend(axesHandle, 'Location', 'southwest');

	plotSecondModeCandidateBoxes( ...
		axesHandle, ...
		cfg, ...
		secondModeResults, ...
		mean(timeWindow), ...
		windowFrequencies, ...
		windowPsdValues);

	if cfg.analysis.savePsdPlots
		fileName = sprintf('steady_PSD_%07.4f_%07.4f_s.png', ...
			timeWindow(1), timeWindow(2));
		exportgraphics(figures(windowIndex), ...
			fullfile(cfg.analysis.savePsdPlotsFolder, fileName), ...
			'Resolution', 300);
	end
end

if cfg.analysis.savePsdPlots
	save(fullfile(cfg.analysis.savePsdPlotsFolder, ...
		'steadyPsdResults.mat'), 'psdResults');
end
end
