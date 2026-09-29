function runData = exportPcbRun(cfg)
%EXPORTPCBRUN Save complete PCB voltages and calibrated driver pressure.
% Accept the user-facing geometry in cm while storing the archive in m.
if isfield(cfg.channels, 'axialDistance_cm')
    assert(~isfield(cfg.channels, 'axialDistance_m'), ...
        'exportPcbRun:Positions', 'Specify axialDistance_cm or axialDistance_m, not both.');
    cfg.channels.axialDistance_m = cfg.channels.axialDistance_cm / 100;
end
% MATLAB appends .mat on save; normalize before existence checks and reload.
[~, ~, outputExtension] = fileparts(cfg.output.file);
if strlength(outputExtension) == 0
    cfg.output.file = string(cfg.output.file) + ".mat";
end
ids = [string(cfg.channels.pcb(:)); string(cfg.channels.driver); ...
    string(cfg.channels.trigger)];
assert(numel(ids) == 9 && numel(unique(ids)) == 9, ...
    'exportPcbRun:ChannelMapping', 'Configure seven unique PCBs, driver, and trigger.');
for name = ["positionIndex", "sensorNumber", "axialDistance_m", "pcbSamplingRate_Hz"]
    assert(numel(cfg.channels.(name)) == 7, ...
        'exportPcbRun:ChannelMapping', '%s must contain seven values.', name);
end
assert(isequal(cfg.channels.positionIndex(:)', 1:7) && ...
    all(isfinite(cfg.channels.axialDistance_m)) && ...
    all(cfg.channels.axialDistance_m >= 0), ...
    'exportPcbRun:Positions', 'Configure positions 1:7 and finite nonnegative distances.');
cal = cfg.calibration.pcb;
assert(isnumeric(cal.constant_Pa_per_V) && numel(cal.constant_Pa_per_V) == 7 && ...
    all(isnan(cal.constant_Pa_per_V(:)) | ...
    (isfinite(cal.constant_Pa_per_V(:)) & cal.constant_Pa_per_V(:) ~= 0)), ...
    'exportPcbRun:InvalidPcbCalibration', ...
    'Provide seven PCB constants in Pa/V; use NaN for unknown values.');
driverCal = cfg.calibration.driver;
assert(isscalar(driverCal.offsetToAbsolutePa) && ...
    isfinite(driverCal.offsetToAbsolutePa), ...
    'exportPcbRun:CalibrationRequired', ...
    'Set driver offsetToAbsolutePa (0 only if existing calibration is absolute).');
assert(numel(driverCal.voltage_V) >= 2 && ...
    numel(driverCal.voltage_V) == numel(driverCal.pressure_Pa) && ...
    all(isfinite(driverCal.voltage_V)) && all(isfinite(driverCal.pressure_Pa)) && ...
    numel(unique(driverCal.voltage_V)) >= 2, ...
    'exportPcbRun:DriverCalibration', 'Driver calibration points are invalid.');
rates = [cfg.channels.pcbSamplingRate_Hz(:); ...
    cfg.channels.driverSamplingRate_Hz; cfg.channels.triggerSamplingRate_Hz];
assert(numel(rates) == 9 && all(isnan(rates) | (isfinite(rates) & rates > 0)), ...
    'exportPcbRun:SamplingRate', 'Sampling rates must be positive or NaN (automatic).');
assert(isfile(cfg.input.file), 'exportPcbRun:InputMissing', ...
    'Input file not found: %s', cfg.input.file);
assert(~isfile(cfg.output.file), 'exportPcbRun:OutputExists', ...
    'Output already exists. Choose another output filename: %s', cfg.output.file);

[folder, stem, extension] = fileparts(cfg.input.file);
switch lower(extension)
    case '.pnrf'
        cfg.input.rawFolder = folder;
        cfg.input.rawFileName = stem + extension;
        cfg.conversion.mode = "memory";
        pcbData = convertPnrfData(cfg);
    case '.mat'
        cfg.input.source = "mat";
        pcbData = loadPcbData(cfg);
    case '.txt'
        cfg.input.source = "txt";
        cfg.channels.driverSamplingRate = cfg.channels.driverSamplingRate_Hz;
        cfg.channels.triggerSamplingRate = cfg.channels.triggerSamplingRate_Hz;
        cfg.channels.dataSamplingRate = cfg.channels.pcbSamplingRate_Hz(:)';
        pcbData = loadPcbData(cfg);
    otherwise
        error('exportPcbRun:InputType', 'Input must be .pnrf, .mat, or .txt.');
end
available = string(pcbData.channels(:));
assert(all(ismember(ids, available)), 'exportPcbRun:MissingChannels', ...
    'Missing requested channels: %s', strjoin(setdiff(ids, available), ', '));
assert(numel(unique(available)) == numel(available), ...
    'exportPcbRun:DuplicateChannels', 'Source channel IDs must be unique.');

runData.schemaVersion = "1.1";
runData.metadata = cfg.metadata;
runData.metadata.pressureReference = "absolute";
driverFit = polyfit(driverCal.voltage_V, driverCal.pressure_Pa, 1);
for k = 1:9
    source = pcbData.signalData(find(available == ids(k), 1));
    t = double(source.time(:));
    signal = double(source.signal(:));
    assert(numel(t) >= 2 && numel(t) == numel(signal) && ...
        all(isfinite(t)) && all(diff(t) > 0), ...
        'exportPcbRun:InvalidRecord', ...
        '%s must have matching signal/time lengths and increasing finite timestamps.', ids(k));
    % Keep gaps; check that intervals are integer multiples of the sample period.
    inferredRate = 1 / median(diff(t));
    fs = rates(k);
    rateSource = "configured";
    if isnan(fs), fs = inferredRate; rateSource = "timestamps"; end
    steps = diff(t) * fs;
    assert(all(abs(steps - round(steps)) < 1e-3) && ...
        abs(fs / inferredRate - 1) < 1e-3, ...
        'exportPcbRun:SamplingMismatch', ...
        'Sampling rate does not match timestamps for %s.', ids(k));
    channel = struct('sourceChannel', ids(k), 'role', "", ...
        'positionIndex', NaN, 'sensorNumber', NaN, 'axialDistance_m', NaN, ...
        'positionStatus', "not_applicable", 'samplingRate_Hz', fs, ...
        'samplingRateSource', rateSource, 'time_s', t);
    if k <= 7
        key = sprintf('pcb%02d', k);
        channel.role = "pcb";
        channel.positionIndex = cfg.channels.positionIndex(k);
        channel.sensorNumber = cfg.channels.sensorNumber(k);
        channel.axialDistance_m = cfg.channels.axialDistance_m(k);
        channel.positionStatus = cfg.channels.positionStatus;
        channel.signal_V = signal;
        channel.calibration = struct('status', "not_applied", ...
            'constant_Pa_per_V', cal.constant_Pa_per_V(k));
    elseif k == 8
        key = 'driver';
        channel.role = "driver";
        channel.pressure_Pa = polyval(driverFit, signal) + driverCal.offsetToAbsolutePa;
        channel.pressureReference = "absolute";
        channel.calibration = driverCal;
        channel.calibration.linearFit_Pa_per_V_and_Pa = driverFit;
    else
        key = 'trigger';
        channel.role = "trigger";
        channel.signal_V = signal;
    end
    runData.data.(key) = channel;
    fprintf('%s <- %s: %d samples, %.9g Hz\n', key, ids(k), numel(t), fs);
end
runData.provenance.sourceFile = string(cfg.input.file);
runData.provenance.exportedAt = datetime('now', 'TimeZone', 'UTC');
runData.provenance.timeReference = "Original source timestamps in seconds; no time shift";
runData.provenance.exportConfig = cfg;
outputFolder = fileparts(cfg.output.file);
if strlength(outputFolder) > 0 && ~isfolder(outputFolder), mkdir(outputFolder); end
save(cfg.output.file, 'runData', '-v7.3');
saved = load(cfg.output.file, 'runData');
assert(isequaln(saved.runData, runData), ...
    'exportPcbRun:VerificationFailed', 'Saved data does not match the packaged run.');
fprintf('Verified complete run export: %s\n', cfg.output.file);
end
