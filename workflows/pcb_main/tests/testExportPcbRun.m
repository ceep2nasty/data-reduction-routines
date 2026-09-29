function tests = testExportPcbRun
tests = functiontests(localfunctions);
end

function testCompleteRecordsAndCalibration(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root, 'functions'));
% Read the script's editable defaults without executing its export section.
script = fileread(fullfile(root, 'export_pcb_run.m'));
sections = split(string(script), '%% EXECUTION');
eval(char(sections(1)));
folder = tempname;
mkdir(folder);
cleanup = onCleanup(@() rmdir(folder, 's')); %#ok<NASGU>
cfg.input.file = string(fullfile(folder, 'input.mat'));
cfg.output.file = string(fullfile(folder, 'output'));
cfg.channels.axialDistance_cm = [31 41 52 63 75 86 97];
cfg.channels.pcbSamplingRate_Hz = nan(1, 7);
cfg.channels.driverSamplingRate_Hz = NaN;
cfg.channels.triggerSamplingRate_Hz = NaN;
cfg.calibration.pcb.constant_Pa_per_V = nan(1, 7);
cfg.calibration.pcb.constant_Pa_per_V(2) = 2; % Stored, never applied.
cfg.metadata.driver.recordedP0_Pa = NaN;
cfg.calibration.driver.offsetToAbsolutePa = 0;
pcbData.channels = [cfg.channels.pcb, cfg.channels.driver, cfg.channels.trigger];
for k = 1:9
    % Unequal lengths/rates, nonzero origins, and a gap in each record.
    t = [0:4, 8:(12+k)]' / (1000*k) + 2;
    pcbData.signalData(k).time = t;
    pcbData.signalData(k).signal = (1:numel(t))';
end
pcbData.signalData(9).signal(:) = 0; % Preserve an all-zero trigger.
save(cfg.input.file, 'pcbData');
result = exportPcbRun(cfg);
verifyEqual(testCase, result.data.pcb01.time_s, pcbData.signalData(1).time);
for k = 1:7
    channel = result.data.(sprintf('pcb%02d', k));
    verifyEqual(testCase, channel.signal_V, pcbData.signalData(k).signal);
    verifyFalse(testCase, isfield(channel, 'pressure_Pa'));
    verifyFalse(testCase, isfield(channel, 'pressureReference'));
end
verifyTrue(testCase, isnan(result.data.pcb01.calibration.constant_Pa_per_V));
verifyEqual(testCase, result.data.pcb02.calibration.constant_Pa_per_V, 2);
verifyEqual(testCase, result.data.pcb02.calibration.status, "not_applied");
fit = polyfit(cfg.calibration.driver.voltage_V, cfg.calibration.driver.pressure_Pa, 1);
verifyEqual(testCase, result.data.driver.pressure_Pa, polyval(fit, pcbData.signalData(8).signal));
verifyEqual(testCase, result.data.trigger.signal_V, pcbData.signalData(9).signal);
verifyEqual(testCase, result.data.pcb07.axialDistance_m, 0.97, 'AbsTol', 1e-12);
verifyTrue(testCase, isnan(result.metadata.driver.recordedP0_Pa));
verifyError(testCase, @() exportPcbRun(cfg), 'exportPcbRun:OutputExists');
cfg.calibration.driver.offsetToAbsolutePa = NaN;
verifyError(testCase, @() exportPcbRun(cfg), 'exportPcbRun:CalibrationRequired');
end
