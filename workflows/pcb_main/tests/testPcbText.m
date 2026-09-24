function tests = testPcbText
tests = functiontests(localfunctions);
end

function testTextInputThroughRunner(testCase)
folder = fileparts(fileparts(mfilename('fullpath')));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(folder));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(folder, 'functions')));
file = [tempname '.txt'];
testCase.addTeardown(@() delete(file));
fid = fopen(file, 'wt');
fprintf(fid, 'File: export\n\nTime\tCh A01\tEv A09_01\tCh B01\tCh C03\tCh D08\n');
fprintf(fid, 's\tV\t\tV\tV\tV\n');
fprintf(fid, '0\t1\t99\t0\t3\t0\t\n0.0000005\t2\t99\t5\t4\t0\t\n');
fclose(fid);
cfg = createPcbConfig();
cfg.input.source = "txt";
cfg.input.file = file;
cfg.channels.data = ["C03", "D08"];
cfg.channels.driverSamplingRate = 2e6;
cfg.channels.triggerSamplingRate = 2e6;
cfg.channels.dataSamplingRate = 2e6;
cfg.timing.pcbAnalysisChannel = "C03";
cfg.secondMode.channelsExcluded = strings(0,1);
for name = string(fieldnames(cfg.run)).'
    cfg.run.(name) = false;
end
r = run_pcb_main(cfg);
verifyEqual(testCase, r.pcbData.channels, ["A01"; "B01"; "C03"; "D08"]);
verifyEqual(testCase, r.dataData.signal{1}, [3;4]);
verifyEqual(testCase, r.dataData.signal{2}, [0;0]); % Keep even empty inputs.
verifyEqual(testCase, r.triggerData.signal{1}, [0;5]);
verifyEqual(testCase, r.pcbData.exportSamplingRate, 2e6, 'RelTol', 1e-12);
cfg.channels.driverSamplingRate = 250e3;
verifyError(testCase, @() loadPcbData(cfg), 'loadPcbData:SamplingRateMismatch');
fid = fopen(file, 'at');
fprintf(fid, '0.0000017\t2\t99\t5\t4\t0\t\n');
fclose(fid);
verifyError(testCase, @() loadPcbData(cfg), 'loadPcbData:InvalidTextTime');
end
