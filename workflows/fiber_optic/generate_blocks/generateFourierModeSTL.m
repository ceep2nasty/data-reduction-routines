function TR = generateFourierModeSTL(params)
% generateFourierModeSTL
% Flexible generator for Fourier mode surfaces + STL export


%% input params for solo run
soloRun = 0 ;

if soloRun
params.modes      = [2 2];
params.amplitudes = [-1.0];
params.coeffs     = [1.0];

params.Nx = 20;
params.Ny = 20;

params.Lx = 100;
params.Ly = 100;

end
% make params a field 
%% ------------------ DEFAULTS ------------------
if ~isfield(params,'Lx'); params.Lx = 100; end
if ~isfield(params,'Ly'); params.Ly = 100; end
if ~isfield(params,'Lb'); params.Lb = 0; end
if ~isfield(params,'thickness'); params.thickness = 25; end

if ~isfield(params,'Nx'); params.Nx = 301; end
if ~isfield(params,'Ny'); params.Ny = 301; end

if ~isfield(params,'transition_width'); params.transition_width = 0; end
if ~isfield(params,'smoothing_sigma'); params.smoothing_sigma = 0.5; end

if ~isfield(params,'preview'); params.preview = true; end
if ~isfield(params,'export'); params.export = true; end
if ~isfield(params,'filename'); params.filename = 'mode.stl'; end



%% ------------------ GRID ------------------
x_mode = linspace(0, params.Lx, params.Nx);
y      = linspace(0, params.Ly, params.Ny);
x_back = linspace(-params.Lb, 0, 2);

x = [x_back, x_mode(2:end)];
[X,Y] = meshgrid(x,y);

%% ------------------ MODE CONSTRUCTION ------------------
% params.modes = [m n; m n; ...]
% params.amplitudes = [A1 A2 ...]
% params.coeffs = [c1 c2 ...]

W = zeros(size(X));

for k = 1:size(params.modes,1)
    m = params.modes(k,1);
    n = params.modes(k,2);

    phi = sin(m*pi*X/params.Lx).*sin(n*pi*Y/params.Ly);

    W = W + params.coeffs(k)*params.amplitudes(k)*phi;
end

%% ------------------ SMOOTHING ------------------
if params.smoothing_sigma > 0
    W = imgaussfilt(W, params.smoothing_sigma);
end

%% ------------------ BACKING TRANSITION ------------------
if params.transition_width > 0
    taper = smoothstep(X, -params.transition_width, 0);
    W = W .* taper;
else
    W(X < 0) = 0;
end

%% ------------------ SOLID CREATION ------------------
Ztop = W;
Zbot = -params.thickness * ones(size(W));

S1 = surf2patch(X,Y,Ztop,'triangles');
S2 = surf2patch(X,Y,Zbot,'triangles');

V1 = S1.vertices; F1 = S1.faces;
V2 = S2.vertices; F2 = fliplr(S2.faces);

V = [V1; V2];
F2 = F2 + size(V1,1);

%% ------------------ SIDE WALLS ------------------
[Ny,Nx] = size(X);
idx = reshape(1:Ny*Nx,Ny,Nx);

loop = [ ...
    idx(1,1:Nx), ...
    idx(2:Ny,Nx)', ...
    fliplr(idx(Ny,1:Nx-1)), ...
    flipud(idx(2:Ny-1,1))' ...
];

loop_bot = loop + size(V1,1);

Fs = [];

for k = 1:length(loop)
    k2 = mod(k,length(loop)) + 1;

    a = loop(k);
    b = loop(k2);
    c = loop_bot(k2);
    d = loop_bot(k);

    Fs = [Fs;
        a b c
        a c d];
end

F = [F1; F2; Fs];
TR = triangulation(F,V);

%% ------------------ EXPORT ------------------
if params.export
    folder = fullfile(pwd,'STL_exports\brian_negatives');
    if ~exist(folder,'dir'); mkdir(folder); end

    filename = fullfile(folder, params.filename);
    stlwrite(TR, filename, 'binary');

    fprintf('STL written:\n%s\n', filename);
end

%% ------------------ PREVIEW ------------------
if params.preview
    figure
    trisurf(TR)
    axis equal
    view(35,25)
    camlight
    lighting gouraud
end

end

%% HELPER

function y = smoothstep(x, edge0, edge1)
t = (x - edge0) ./ (edge1 - edge0);
t = max(0, min(1, t));
y = t.^2 .* (3 - 2*t);
end