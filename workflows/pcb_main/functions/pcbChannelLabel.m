function label = pcbChannelLabel(cfg, channel)
%PCBCHANNELLABEL Keep recorder identity visible alongside physical numbering.
label = string(channel);
if isfield(cfg.channels, 'sensorNumbers') && ~isempty(cfg.channels.sensorNumbers)
    index = find(string(cfg.channels.data) == label, 1);
    if ~isempty(index)
        label = "PCB " + cfg.channels.sensorNumbers(index) + " (" + label + ")";
    end
end
end
