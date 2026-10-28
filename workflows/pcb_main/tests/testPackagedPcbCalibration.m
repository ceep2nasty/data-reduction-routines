function tests = testPackagedPcbCalibration
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
folder = fileparts(fileparts(mfilename('fullpath')));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(folder));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(folder, 'functions')));
end

function testMappingCalibrationAndPressurePsd(testCase)
folder = tempname;
mkdir(folder);
testCase.addTeardown(@() rmdir(folder, 's'));
fs = 20e3;
t = (0:1/fs:0.1-1/fs).';
v = sin(2*pi*2000*t);
record = struct('sourceChannel', "D01", 'positionIndex', 2, ...
    'sensorNumber', 8, 'axialDistance_m', .97, 'samplingRate_Hz', fs, 'time_s', t, 'signal_V', v, ...
    'calibration', struct('constant_Pa_per_V', NaN, 'sensitivity_mV_per_psi', 100));
runData.data.pcb01 = record;
record.sourceChannel = "C02";
record.positionIndex = 1;
record.sensorNumber = 3;
record.axialDistance_m = .41;
record.calibration.constant_Pa_per_V = 2;
runData.data.pcb02 = record;
runData.data.driver = struct('sourceChannel', "A01", 'samplingRate_Hz', fs, ...
    'time_s', t, 'pressure_Pa', 100000+v);
runData.data.trigger = struct('sourceChannel', "B01", 'samplingRate_Hz', fs, ...
    'time_s', t, 'signal_V', zeros(size(t)));
runData.metadata = struct('runId', "synthetic");
file = fullfile(folder, 'calibrated.mat');
save(file, 'runData');
cfg = createPcbConfig();
cfg.input.source = "mat";
cfg.input.file = file;
cfg.input.useRunDataMapping = true;
cfg.input.applyPcbCalibration = true;
[data, cfg] = loadPcbData(cfg);
verifyEqual(testCase, cfg.channels.data, ["C02", "D01"]);
verifyEqual(testCase, cfg.channels.sensorNumbers, [3 8]);
verifyEqual(testCase, cfg.channels.order, [3 8]);
verifyEqual(testCase, cfg.channels.axialDistance_m, [.41 .97]);
[driver, ~, pressure] = extractPcbChannels(cfg, data);
verifyEqual(testCase, driver.signal{1}, 100000+v);
verifyEqual(testCase, driver.units, "Pa");
verifyEqual(testCase, pressure.signal{1}, 2*v);
gain = 6894.757293168*1000/100;
verifyEqual(testCase, pressure.signal{2}, gain*v);
verifyEqual(testCase, pressure.units, "Pa");
verifyEqual(testCase, pcbChannelLabel(cfg, "D01"), "x = 0.97 m");
cfg.psd.windowDuration = 0.05;
cfg.psd.windowStep = 0.05;
cfg.psd.welchSegmentDuration = 0.01;
psd = computeWindowedPcbPsd(cfg, pressure);
verifyEqual(testCase, psd.signalUnits, "Pa");
verifyEqual(testCase, psd.powerSpectralDensity(:,:,2), ...
    psd.powerSpectralDensity(:,:,1)*(gain/2)^2, 'RelTol', 1e-8, 'AbsTol', 1e-12);
cfg.input.applyPcbCalibration = false;
raw = loadPcbData(cfg);
verifyEqual(testCase, raw.signalData(1).signal, v);
verifyEqual(testCase, raw.signalData(1).units, "V");
saved = load(file, 'runData');
verifyEqual(testCase, saved.runData.data.pcb01.signal_V, v);
verifyTrue(testCase, isnan(saved.runData.data.pcb01.calibration.constant_Pa_per_V));
end

function testPsdAxisUnits(testCase)
cfg = createPcbConfig();
cfg.run.windowedPsdPreview = true;
cfg.output.saveWindowedPsdPlots = false;
cfg.psd.previewWindowIndices = 1;
psd = struct('windowCenterTime', .05, 'windowStartTime', 0, ...
    'windowEndTime', .1, 'frequency', [0; 1000], 'channels', "C01", ...
    'powerSpectralDensity', [1; 2], 'signalUnits', "Pa");
figures = plotWindowedPcbPsd(cfg, psd);
testCase.addTeardown(@() close(figures));
ax = findobj(figures(1), 'Type', 'axes');
verifyEqual(testCase, string(ax.YLabel.String), "PSD (dB Pa^2/Hz)");
verifyEqual(testCase, ax.XLim, [0 400]);
verifyEqual(testCase, ax.FontSize, 24);
verifyEqual(testCase, string(ax.FontName), "Times New Roman");
verifyEqual(testCase, string(ax.Title.String), "");
verifyEqual(testCase, ax.Legend.FontSize, 18);
end
