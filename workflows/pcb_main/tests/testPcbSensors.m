function tests = testPcbSensors
tests = functiontests(localfunctions);
end

function testAxialPositionsFollowSelection(testCase)
folder = fileparts(fileparts(mfilename('fullpath')));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(folder));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(folder, 'functions')));
cfg = createPcbConfig();
cfg.channels.data = ["D01", "C01", "D05"];
cfg.channels.sensorNumbers = [2 4 5];
cfg.channels.axialDistance_m = [.31 .52 .63];
cfg.channels.order = [5 2];
cfg = selectPcbSensors(cfg);
verifyEqual(testCase, cfg.channels.axialDistance_m, [.63; .31]);
verifyEqual(testCase, pcbChannelLabel(cfg, "D05"), "x = 0.63 m");
end

function testAbsoluteAndRelativeTime(testCase)
folder = fileparts(fileparts(mfilename('fullpath')));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(folder));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(folder, 'functions')));
cfg = createPcbConfig();
cfg.channels.data = "C01";
pcbData.channels = ["A01"; "B01"; "C01"];
record = struct('time', [10; 10.01; 10.02], 'signal', [1; 2; 3]);
pcbData.signalData = repmat(record, 3, 1);
cfg.analysis.timeReference = "absolute";
[~, ~, data] = extractPcbChannels(cfg, pcbData);
verifyEqual(testCase, data.time{1}, record.time);
cfg.analysis.timeReference = "relative";
[~, ~, data] = extractPcbChannels(cfg, pcbData);
verifyEqual(testCase, data.time{1}, record.time-10);
end

function testSelectionAndLabels(testCase)
folder = fileparts(fileparts(mfilename('fullpath')));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(folder));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(folder, 'functions')));
cfg = createPcbConfig();
cfg.channels.data = ["D01", "C01", "D05"];
cfg.channels.sensorNumbers = [2 4 5];
cfg.channels.order = [5 2];
cfg = selectPcbSensors(cfg);
verifyEqual(testCase, cfg.channels.data, ["D05"; "D01"]);
verifyEqual(testCase, cfg.channels.sensorNumbers, [5;2]);
verifyEqual(testCase, pcbChannelLabel(cfg, "D05"), "PCB 5 (D05)");
verifyEqual(testCase, pcbChannelLabel(cfg, "A01"), "A01");
cfg.channels.order = [2 7];
verifyError(testCase, @() selectPcbSensors(cfg), 'selectPcbSensors:InvalidOrder');
end
