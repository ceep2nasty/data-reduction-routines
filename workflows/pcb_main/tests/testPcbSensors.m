function tests = testPcbSensors
tests = functiontests(localfunctions);
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
