function data = loadPcbData(cfg)
%LOADPCBDATA Load a converted PCB MAT-file for the analysis pipeline.

if ~isfield(cfg, 'input') || ~isfield(cfg.input, 'file')
    error('loadPcbData:MissingInputFile', ...
        'Configuration must define cfg.input.file.');
end

filePath = char(cfg.input.file);
if ~isfile(filePath)
    error('loadPcbData:FileNotFound', ...
        'PCB data file not found: %s', filePath);
end

if isfield(cfg.input, 'variable') && ~isempty(cfg.input.variable)
    variableName = char(cfg.input.variable);
else
    variableName = 'Perception_Raw';
end

loadedData = load(filePath);
if isfield(loadedData, 'pcbData')
    data = loadedData.pcbData;
elseif isfield(loadedData, 'blockData')
    data = loadedData.blockData;
elseif isfield(loadedData, variableName)
    data = struct();
    data.raw = loadedData.(variableName);
    data.sourceFile = string(filePath);
    data.sourceVariable = string(variableName);
else
    error('loadPcbData:MissingVariable', ...
        '"%s" not found in %s.', variableName, filePath);
end

fprintf('Loaded PCB data: %s\n', filePath);
end