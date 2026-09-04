function [driverData, triggerData, dataData] = extractPcbChannels(cfg, pcbData)
%EXTRACTPCBCHANNELS Extracts specified channels from PCB data for analysis.

if cfg.analysis.extractChannels
    driverData = struct('channels', "", 'time', [], 'signal', [], 'samplingRate', []);
    triggerData = struct('channels', "", 'time', [], 'signal', [], 'samplingRate', []);
    dataData = struct('channels', "", 'time', [], 'signal', [], 'samplingRate', []);

    driverChannel = cfg.analysis.driverChannel;
    triggerChannels = cfg.analysis.triggerChannels;
    dataChannels = cfg.analysis.dataChannels;

    driverSamplingRate = cfg.analysis.driverSamplingRate;
    triggerSamplingRate = cfg.analysis.triggerSamplingRate;
    dataSamplingRate = cfg.analysis.dataSamplingRate;

    % Label channels by their analysis role.
    driverData.channels = driverChannel;
    triggerData.channels = triggerChannels;
    dataData.channels = dataChannels;

    % Assign sampling rates to the output structures
    driverData.samplingRate = driverSamplingRate;
    triggerData.samplingRate = triggerSamplingRate;
    dataData.samplingRate = dataSamplingRate;

    % Extract the driver channel.
    channelIndex = find(pcbData.channels == driverChannel, 1);
    if ~isempty(channelIndex)
        driverData.time{1} = pcbData.signalData(channelIndex).time;
        driverData.signal{1} = pcbData.signalData(channelIndex).signal;
    else
        warning('Channel %s not found in PCB data.', driverChannel);
    end

    % Extract trigger channels.
    for i = 1:length(triggerChannels)
        channelLabel = triggerChannels(i);
        channelIndex = find(pcbData.channels == channelLabel, 1);

        if ~isempty(channelIndex)
            triggerData.time{i} = pcbData.signalData(channelIndex).time;
            triggerData.signal{i} = pcbData.signalData(channelIndex).signal;
        else
            warning('Channel %s not found in PCB data.', channelLabel);
        end
        
    end

    % Extract data channels.
    for i = 1:length(dataChannels)
        channelLabel = dataChannels(i);
        channelIndex = find(pcbData.channels == channelLabel, 1);

        if ~isempty(channelIndex)
            dataData.time{i} = pcbData.signalData(channelIndex).time;
            dataData.signal{i} = pcbData.signalData(channelIndex).signal;
        else
            warning('Channel %s not found in PCB data.', channelLabel);
        end
    end

end

end