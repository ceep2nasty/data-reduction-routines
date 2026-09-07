function figures = plotQuasiSteadyPcbTraces( ...
    cfg, dataData, triggerData, driverData, steadyWindow)
%PLOTQUASISTEADYPCBTRACES Plot signals inside the detected steady interval.

if ~isfield(steadyWindow, 'startTime') || ...
        ~isfield(steadyWindow, 'endTime') || ...
        ~isfinite(steadyWindow.startTime) || ...
        ~isfinite(steadyWindow.endTime) || ...
        steadyWindow.endTime <= steadyWindow.startTime
    error('plotQuasiSteadyPcbTraces:InvalidWindow', ...
        'steadyWindow must contain a valid positive-duration interval.');
end

steadyTimeWindow = [steadyWindow.startTime steadyWindow.endTime];

fprintf('Plotting extracted data from %.6f to %.6f s\n', ...
    steadyTimeWindow(1), steadyTimeWindow(2));

plotDriverData = cropDataToWindow(driverData, steadyTimeWindow);
plotTriggerData = cropDataToWindow(triggerData, steadyTimeWindow);
plotDataData = cropDataToWindow(dataData, steadyTimeWindow);

if cfg.plotting.smoothData
    plotDriverData = smoothDataSignals(plotDriverData);
    plotTriggerData = smoothDataSignals(plotTriggerData);
    plotDataData = smoothDataSignals(plotDataData);
end

figures = struct();

figures.driver = figure( ...
    'Name', 'Detected PCB Window Driver Tube Pressure', ...
    'Position', cfg.plotting.figurePosition);

driverPressure = calibrateDriverSignal(plotDriverData.signal{1});
plot(plotDriverData.time{1}, driverPressure, ...
    'LineWidth', 1.2, ...
    'DisplayName', string(plotDriverData.channels(1)));
grid on;
box on;
xlim(steadyTimeWindow);
xlabel('Time (s)', 'FontSize', cfg.plotting.fontSize);
ylabel('Pressure (Pa)', 'FontSize', cfg.plotting.fontSize);
title(sprintf('Detected PCB Window Driver Pressure: %.4f to %.4f s', ...
    steadyTimeWindow(1), steadyTimeWindow(2)), ...
    'FontSize', cfg.plotting.fontSize);
legend('show', 'Location', 'best', ...
    'FontSize', cfg.plotting.fontSize);

figures.data = figure( ...
    'Name', 'Detected PCB Window PCB Data', ...
    'Position', cfg.plotting.figurePosition);
hold on;
grid on;
box on;

for channelIndex = 1:numel(plotDataData.channels)
    plot(plotDataData.time{channelIndex}, ...
        plotDataData.signal{channelIndex}, ...
        'LineWidth', 1.0, ...
        'DisplayName', string(plotDataData.channels(channelIndex)));
end

xlim(steadyTimeWindow);
xlabel('Time (s)', 'FontSize', cfg.plotting.fontSize);
ylabel('Signal', 'FontSize', cfg.plotting.fontSize);
title(sprintf('Detected PCB Window PCB Signals: %.4f to %.4f s', ...
    steadyTimeWindow(1), steadyTimeWindow(2)), ...
    'FontSize', cfg.plotting.fontSize);
legend('show', 'Location', 'best', ...
    'FontSize', cfg.plotting.fontSize);

figures.trigger = figure( ...
    'Name', 'Detected PCB Window Trigger Signals', ...
    'Position', cfg.plotting.figurePosition);
hold on;
grid on;
box on;

for channelIndex = 1:numel(plotTriggerData.channels)
    plot(plotTriggerData.time{channelIndex}, ...
        plotTriggerData.signal{channelIndex}, ...
        'LineWidth', 1.0, ...
        'DisplayName', string(plotTriggerData.channels(channelIndex)));
end

xlim(steadyTimeWindow);
xlabel('Time (s)', 'FontSize', cfg.plotting.fontSize);
ylabel('Trigger signal', 'FontSize', cfg.plotting.fontSize);
title(sprintf('Detected PCB Window Trigger Signals: %.4f to %.4f s', ...
    steadyTimeWindow(1), steadyTimeWindow(2)), ...
    'FontSize', cfg.plotting.fontSize);
legend('show', 'Location', 'best', ...
    'FontSize', cfg.plotting.fontSize);

if cfg.plotting.savePlots
    if ~isfolder(cfg.plotting.saveFolder)
        mkdir(cfg.plotting.saveFolder);
    end

    saveas(figures.driver, fullfile( ...
        cfg.plotting.saveFolder, ...
        'quasi_steady_driver_tube_pressure.png'));
    saveas(figures.data, fullfile( ...
        cfg.plotting.saveFolder, ...
        'quasi_steady_pcb_data_traces.png'));
    saveas(figures.trigger, fullfile( ...
        cfg.plotting.saveFolder, ...
        'quasi_steady_trigger_traces.png'));

    fprintf('Quasi-steady trace plots saved to %s\n', ...
        cfg.plotting.saveFolder);
end
end

function croppedData = cropDataToWindow(data, timeWindow)

croppedData = data;

for channelIndex = 1:numel(data.channels)
    time = data.time{channelIndex};
    signal = data.signal{channelIndex};

    mask = time >= timeWindow(1) & time <= timeWindow(2);

    croppedData.time{channelIndex} = time(mask);
    croppedData.signal{channelIndex} = signal(mask);
end
end

function smoothedData = smoothDataSignals(data)

smoothedData = data;

for channelIndex = 1:numel(data.channels)
    if ~isempty(data.signal{channelIndex})
        smoothedData.signal{channelIndex} = ...
            smooth(data.signal{channelIndex});
    end
end
end

function calibratedSignal = calibrateDriverSignal(signal)

driverPressure = [51.7 87.8*6.89476 61*6.89476 ...
    150*6.89476 14.6*6.89476 93*6.89476] .* 1000;
driverVoltage = [-8.08 -0.73153 -3.3495 4.8098 ...
    -7.4776 -0.5246];
driverFit = polyfit(driverVoltage, driverPressure, 1);

calibratedSignal = signal .* driverFit(1) + driverFit(2);
end