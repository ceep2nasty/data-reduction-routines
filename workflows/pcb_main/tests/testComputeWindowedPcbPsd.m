function tests = testComputeWindowedPcbPsd
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
functionFolder = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    'functions');
testCase.applyFixture( ...
    matlab.unittest.fixtures.PathFixture(functionFolder));
end

function testComputesExpectedWindowsAndPeakFrequencies(testCase)
samplingRate = 20e3;
time = (0:1 / samplingRate:0.15 - 1 / samplingRate).';

dataData.channels = ["C01", "C02"];
dataData.time = {time, time};
dataData.signal = { ...
    sin(2 * pi * 2e3 * time), ...
    sin(2 * pi * 3e3 * time)};
dataData.samplingRate = samplingRate;

cfg.psd.windowDuration = 0.050;
cfg.psd.windowStep = 0.050;
cfg.psd.welchSegmentDuration = 0.010;
cfg.psd.welchOverlap = 0.50;
cfg.psd.detrend = "linear";

results = computeWindowedPcbPsd(cfg, dataData);

testCase.verifyEqual(size(results.powerSpectralDensity), ...
    [101 3 2]);
testCase.verifyEqual(results.windowStartTime, [0; 0.05; 0.10], ...
    'AbsTol', 10 * eps);

for channelIndex = 1:2
    [~, peakIndex] = max( ...
        results.powerSpectralDensity(:, 1, channelIndex));
    expectedPeak = channelIndex * 1e3 + 1e3;
    testCase.verifyEqual(results.frequency(peakIndex), expectedPeak, ...
        'AbsTol', samplingRate * eps);
end
end
