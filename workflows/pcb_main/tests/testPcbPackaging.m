function tests = testPcbPackaging
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
workflowFolder = fileparts(fileparts(mfilename('fullpath')));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(workflowFolder));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
    fullfile(workflowFolder, 'functions')));
end

function setup(testCase)
temporaryFolder = string(tempname);
mkdir(temporaryFolder);
testCase.addTeardown(@() removeTemporaryFolder(temporaryFolder));

samplingRate = 20e3;
time = (0:1 / samplingRate:0.15 - 1 / samplingRate).';
channels = ["A01", "B01", "C01", "C02", "D01"];
signals = {zeros(size(time)), zeros(size(time)), ...
    0.1 * randn(size(time)), ...
    sin(2 * pi * 2e3 * time), ...
    sin(2 * pi * 3e3 * time)};

signalData = repmat(struct('time', [], 'signal', []), ...
    numel(channels), 1);
for channelIndex = 1:numel(channels)
    signalData(channelIndex).time = time;
    signalData(channelIndex).signal = signals{channelIndex};
end
pcbData = struct('channels', channels, 'signalData', signalData);

inputFile = fullfile(temporaryFolder, 'synthetic_pcb.mat');
save(inputFile, 'pcbData');

testCase.TestData.temporaryFolder = temporaryFolder;
testCase.TestData.inputFile = inputFile;
testCase.TestData.samplingRate = samplingRate;
end

function testConstructorCanSaveConfiguration(testCase)
configurationFile = fullfile( ...
    testCase.TestData.temporaryFolder, 'synthetic_cfg.mat');

cfg = createPcbConfig(configurationFile);
saved = load(configurationFile, 'cfg');

testCase.verifyEqual(saved.cfg, cfg);
testCase.verifyEqual(cfg.secondMode.channelsExcluded, "C01");
testCase.verifyEqual(cfg.psd.windowDuration, 0.050);
end

function testSecondModeAutomaticallyComputesPsd(testCase)
cfg = syntheticConfiguration(testCase);
cfg.run.secondModeAnalysis = true;

configurationFile = fullfile( ...
    testCase.TestData.temporaryFolder, 'run_cfg.mat');
save(configurationFile, 'cfg');
results = run_pcb_main(configurationFile);

testCase.verifyFalse(results.cfg.run.windowedPsd);
testCase.verifyTrue(results.stages.needsWindowedPsd);
testCase.verifyTrue(results.stageStatus.windowedPsd);
testCase.verifyTrue(results.stageStatus.secondModeAnalysis);
testCase.verifyEqual(results.secondMode.channels, ["C02"; "D01"]);
testCase.verifySize(results.secondMode.found, [3 2]);
testCase.verifyTrue(all(results.secondMode.found, 'all'));
testCase.verifyEqual(median(results.secondMode.frequency(:, 1)), ...
    2e3, 'AbsTol', 100);
testCase.verifyEqual(median(results.secondMode.frequency(:, 2)), ...
    3e3, 'AbsTol', 100);
testCase.verifyNotEmpty(results.metadata.completedAt);
end

function testNoProductsStillLoadsAndExtracts(testCase)
cfg = syntheticConfiguration(testCase);

results = run_pcb_main(cfg);

testCase.verifyTrue(results.stageStatus.inputLoaded);
testCase.verifyTrue(results.stageStatus.channelsExtracted);
testCase.verifyFalse(results.stages.needsWindowedPsd);
testCase.verifyEmpty(results.windowedPsd);
testCase.verifyEqual(results.dataData.channels, ...
    ["C01"; "C02"; "D01"]);
end

function testSavedResultsUseStableContract(testCase)
cfg = syntheticConfiguration(testCase);
cfg.run.saveResults = true;

returnedResults = run_pcb_main(cfg);
saved = load(cfg.output.resultsFile, 'results');

testCase.verifyTrue(returnedResults.stageStatus.resultsSaved);
testCase.verifyNotEmpty(returnedResults.pcbData);
testCase.verifyTrue(saved.results.stageStatus.resultsSaved);
testCase.verifyEmpty(saved.results.pcbData);
testCase.verifyEmpty(fieldnames(saved.results.figures));
testCase.verifyEqual(saved.results.files.results, ...
    string(cfg.output.resultsFile));
end

function cfg = syntheticConfiguration(testCase)
cfg = createPcbConfig();
samplingRate = testCase.TestData.samplingRate;

cfg.input.source = "mat";
cfg.input.file = testCase.TestData.inputFile;
cfg.channels.driverSamplingRate = samplingRate;
cfg.channels.triggerSamplingRate = samplingRate;
cfg.channels.dataSamplingRate = samplingRate;

runFields = string(fieldnames(cfg.run));
for fieldName = runFields.'
    cfg.run.(fieldName) = false;
end

cfg.analysis.interval = "full";
cfg.spectrogram.windowLength = 100;
cfg.spectrogram.frequencyBand = [0 8e3];
cfg.psd.windowDuration = 0.050;
cfg.psd.windowStep = 0.050;
cfg.psd.welchSegmentDuration = 0.010;
cfg.psd.welchOverlap = 0.50;
cfg.psd.plotFrequencyBand = [0 8e3];
cfg.secondMode.channelsExcluded = "C01";
cfg.secondMode.frequencyBand = [1e3 4e3];
cfg.secondMode.minimumProminenceDb = 3;
cfg.secondMode.minimumWidth = 50;
cfg.secondMode.fitHalfWidth = 500;

cfg.output.rootFolder = testCase.TestData.temporaryFolder;
cfg.output.convertedDataFolder = testCase.TestData.temporaryFolder;
cfg.output.tracePlotFolder = testCase.TestData.temporaryFolder;
cfg.output.spectrogramFolder = testCase.TestData.temporaryFolder;
cfg.output.windowedPsdFolder = testCase.TestData.temporaryFolder;
cfg.output.resultsFile = fullfile( ...
    testCase.TestData.temporaryFolder, 'results.mat');
cfg.output.saveTracePlots = false;
cfg.output.saveSpectrogramData = false;
cfg.output.saveSpectrogramPlots = false;
cfg.output.saveWindowedPsdPlots = false;
end

function removeTemporaryFolder(folder)
if isfolder(folder)
    rmdir(folder, 's');
end
end
