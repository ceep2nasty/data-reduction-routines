function conversion = convertPnrfData(cfg)
%CONVERTPNRFDATA Convert Perception PNRF recordings to MAT-files.
% Author: Cole Peters
% Date created: 09/03/2026
% Modified from earlier version created by Ben Bemis
%  The Perception pNRF reader toolkit and MATLAB ActiveX support are required
% on Windows. The output format is compatible with loadPcbData.

if ~isfield(cfg, 'conversion') || ~isfield(cfg.conversion, 'mode')
    error('convertPnrfData:MissingConversionMode', ...
        'Configuration must define cfg.conversion.mode.');
end

conversionMode = string(cfg.conversion.mode);

if ~isscalar(conversionMode) || ...
        ~ismember(conversionMode, ["memory", "disk", "both"])
    error('convertPnrfData:InvalidMode', ...
        'cfg.conversion.mode must be "memory", "disk", or "both".');
end

saveConvertedData = ismember(conversionMode, ["disk", "both"]);
returnConvertedData = ismember(conversionMode, ["memory", "both"]);


if ~isfield(cfg, 'input') || ~isfield(cfg.input, 'rawFolder')
    error('convertPnrfData:MissingRawFolder', ...
        'Configuration must define cfg.input.rawFolder.');
end
if ~isfield(cfg.input, 'blocks') || isempty(cfg.input.blocks)
    error('convertPnrfData:MissingBlocks', ...
        'Configuration must define one or more cfg.input.blocks.');
end
if ~isfield(cfg, 'output') || ~isfield(cfg.output, 'dataFolder')
    error('convertPnrfData:MissingDataFolder', ...
        'Configuration must define cfg.output.dataFolder.');
end

rawFolder = char(cfg.input.rawFolder);
dataFolder = char(cfg.output.dataFolder);
blocks = cellstr(cfg.input.blocks);

if ~isfolder(rawFolder)
    error('convertPnrfData:RawFolderNotFound', ...
        'PNRF input folder not found: %s', rawFolder);
end
if ~isfolder(dataFolder)
    mkdir(dataFolder);
end

reader = actxserver('Perception.Loaders.pNRF');
cleanupReader = onCleanup(@() delete(reader));

emptyConversion = struct( ...
    'blockName', "", ...
    'raw', [], ...
    'outputFile', "", ...
    'recordingCount', 0);

conversion = repmat(emptyConversion, numel(blocks), 1);

for blockIndex = 1:numel(blocks)
    blockName = blocks{blockIndex};
    files = dir(fullfile(rawFolder, [blockName '*.pNRF']));
    files = files(~[files.isdir]);

    fprintf('Found %d PNRF files for block %s.\n', numel(files), blockName);
    if isempty(files)
        error('convertPnrfData:NoFilesFound', ...
            'No PNRF files matched %s in %s.', blockName, rawFolder);
    end

    perceptionRaw = struct([]);
    validRecordingCount = 0;

    for recordingIndex = 1:numel(files)
        recordingPath = fullfile(files(recordingIndex).folder, files(recordingIndex).name);
        fprintf('Converting recording %d of %d: %s\n', ...
            recordingIndex, numel(files), files(recordingIndex).name);

        data = reader.LoadRecording(recordingPath);
        for recorderIndex = 1:20
            recorder = data.Recorders.Item(recorderIndex);
            if isempty(recorder)
                continue
            end

            channels = recorder.Channels;
            for channelIndex = 1:20
                channel = channels.Item(channelIndex);
                if isempty(channel)
                    continue
                end

                interfaceData = channel.DataSource(3);
                sweeps = interfaceData.Sweeps;
                segments = interfaceData.Data(sweeps.StartTime, sweeps.EndTime);
                segment = segments.Item(1);
                numberOfSamples = segment.NumberOfSamples;
                waveformData = segment.Waveform(5, 1, numberOfSamples, 1)';

                if ~any(waveformData)
                    continue
                end

                endTime = segment.StartTime + ...
                    (numberOfSamples - 1) * segment.SampleInterval;
                time = segment.StartTime:segment.SampleInterval:endTime;
                perceptionRaw(recordingIndex, recorderIndex).time = time;
                perceptionRaw(recordingIndex, recorderIndex).channel(:, channelIndex) = waveformData;
            end
        end
        validRecordingCount = validRecordingCount + 1;
    end

    outputPath = "";
if saveConvertedData
    outputPath = string(fullfile(dataFolder, [blockName '.mat']));

    Perception_Raw = perceptionRaw;
    save(outputPath, 'Perception_Raw');

    fprintf('Saved converted data to: %s\n', outputPath);
end

conversion(blockIndex).blockName = string(blockName);
conversion(blockIndex).outputFile = outputPath;
conversion(blockIndex).recordingCount = validRecordingCount;

if returnConvertedData
    conversion(blockIndex).raw = perceptionRaw;
end

clear cleanupReader reader

end

