function cfg = selectPcbSensors(cfg)
%SELECTPCBSENSORS Resolve optional physical sensor numbers to recorder IDs.
if ~isfield(cfg.channels, 'sensorNumbers') || isempty(cfg.channels.sensorNumbers)
    return
end
numbers = cfg.channels.sensorNumbers(:);
assert(isnumeric(numbers) && numel(numbers) == numel(cfg.channels.data) && ...
    all(isfinite(numbers) & numbers > 0 & numbers == fix(numbers)) && ...
    numel(unique(numbers)) == numel(numbers), ...
    'selectPcbSensors:InvalidMapping', 'Provide one unique positive sensor number per data channel.');
order = numbers;
if isfield(cfg.channels, 'order') && ~isempty(cfg.channels.order)
    order = cfg.channels.order(:);
end
[found, indices] = ismember(order, numbers);
assert(all(found) && numel(unique(order)) == numel(order), ...
    'selectPcbSensors:InvalidOrder', 'Channel order must contain unique mapped sensor numbers.');
channels = string(cfg.channels.data(:));
cfg.channels.data = channels(indices);
cfg.channels.sensorNumbers = numbers(indices);
cfg.secondMode.channelsExcluded = intersect( ...
    string(cfg.secondMode.channelsExcluded), cfg.channels.data, 'stable');
end
