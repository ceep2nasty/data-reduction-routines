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

loadedData = load(filePath, variableName);
if ~isfield(loadedData, variableName)
    error('loadPcbData:MissingVariable', ...
        'Variable "%s" was not found in %s.', variableName, filePath);
end

data = struct();
data.raw = loadedData.(variableName);
data.sourceFile = string(filePath);
data.sourceVariable = string(variableName);

fprintf('Loaded PCB data: %s\n', filePath);
end