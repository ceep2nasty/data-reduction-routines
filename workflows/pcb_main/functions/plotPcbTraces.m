function figures = plotPcbTraces(cfg, dataData, triggerData, driverData)
%PLOTPCBTRACES Plots the traces of the specified PCB channels for analysis.

if cfg.plotting.savePlots && ~ isfolder(cfg.plotting.saveFolder)
    mkdir(cfg.plotting.saveFolder);
end

% Keep the extracted data unchanged and preprocess plotting copies only.
plotDriverData = driverData;
plotDataData = dataData;
plotTriggerData = triggerData;

% Reset to relative time.
for i = 1:length(plotDriverData.channels)
    plotDriverData.time{i} = ...
        plotDriverData.time{i} - plotDriverData.time{i}(1);
end

for i = 1:length(plotDataData.channels)
    plotDataData.time{i} = ...
        plotDataData.time{i} - plotDataData.time{i}(1);
end

for i = 1:length(plotTriggerData.channels)
    plotTriggerData.time{i} = ...
        plotTriggerData.time{i} - plotTriggerData.time{i}(1);
end

if cfg.plotting.smoothData
    for i = 1:length(plotDriverData.channels)
        plotDriverData.signal{i} = smooth(plotDriverData.signal{i});
    end
    for i = 1:length(plotDataData.channels)
        plotDataData.signal{i} = smooth(plotDataData.signal{i});
    end
    for i = 1:length(plotTriggerData.channels)
        plotTriggerData.signal{i} = smooth(plotTriggerData.signal{i});
    end
end

% Plot driver channel.
figures = struct();
figures.driver = figure('Name', 'Driver Tube Pressure', ...
    'Position', cfg.plotting.figurePosition);

% Calibrate driver tube
driverp = [51.7 87.8*6.89476 61*6.89476 150*6.89476 14.6*6.89476 93*6.89476].*1000; %(Pa)
driverv=[-8.08 -0.73153 -3.3495 4.8098 -7.4776 -0.5246]; %(V)
driver_FIT = polyfit(driverv,driverp,1);

calibratedDriverSignal = ...
    driverData.signal{1} .* driver_FIT(1) + driver_FIT(2);
plot(plotDriverData.time{1}, calibratedDriverSignal, ...
    'DisplayName', plotDriverData.channels(1));
hold on
grid on
legend('show', 'Location', 'best', 'FontSize', cfg.plotting.fontSize);
xlabel('Time (s)', 'FontSize', cfg.plotting.fontSize);
ylabel('Pressure (Pa)', 'FontSize', cfg.plotting.fontSize);
title('Calibrated Driver Tube Pressure', 'FontSize', cfg.plotting.fontSize);

% Plot data channels
figures.data = figure('Name', 'PCB Data Traces', 'Position', cfg.plotting.figurePosition); 
hold on
grid on

for i = 1:length(plotDataData.channels)
    plot(plotDataData.time{i}, plotDataData.signal{i}, ...
        'DisplayName', plotDataData.channels(i));
end

xlabel('Time (s)', 'FontSize', cfg.plotting.fontSize);
ylabel('Signal', 'FontSize', cfg.plotting.fontSize);
title('PCB Data Traces', 'FontSize', cfg.plotting.fontSize);
legend('show', 'Location', 'best', 'FontSize', cfg.plotting.fontSize);


% Plot trigger channel
figures.trigger = figure('Name', 'PCB Trigger Traces', 'Position', cfg.plotting.figurePosition);
hold on
grid on

for i = 1:length(plotTriggerData.channels)
    plot(plotTriggerData.time{i}, plotTriggerData.signal{i}, ...
        'DisplayName', plotTriggerData.channels(i));
end

xlabel('Time (s)', 'FontSize', cfg.plotting.fontSize);
ylabel('Signal', 'FontSize', cfg.plotting.fontSize);
title('PCB Trigger Traces', 'FontSize', cfg.plotting.fontSize);
legend('show', 'Location', 'best', 'FontSize', cfg.plotting.fontSize);


if cfg.plotting.savePlots
    saveas(figures.driver, fullfile(cfg.plotting.saveFolder, 'driver_tube_pressure.png'));
    saveas(figures.data, fullfile(cfg.plotting.saveFolder, 'pcb_data_traces.png'));
    saveas(figures.trigger, fullfile(cfg.plotting.saveFolder, 'pcb_trigger_traces.png'));
    fprintf("Trace plots saved to %s\n", cfg.plotting.saveFolder);
end

end