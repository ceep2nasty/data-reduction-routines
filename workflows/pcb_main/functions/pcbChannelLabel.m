function label = pcbChannelLabel(cfg, channel)
%PCBCHANNELLABEL Use archived axial position when available, else sensor ID.
label = string(channel);
index = find(string(cfg.channels.data) == label, 1);
if ~isempty(index) && isfield(cfg.channels, 'axialDistance_m') && ...
        isfinite(cfg.channels.axialDistance_m(index))
    label = string(sprintf('x = %.2f m', cfg.channels.axialDistance_m(index)));
    return
end
if isfield(cfg.channels, 'sensorNumbers') && ~isempty(cfg.channels.sensorNumbers)
    if ~isempty(index)
        label = "PCB " + cfg.channels.sensorNumbers(index) + " (" + label + ")";
    end
end
end
