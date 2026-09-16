%% Master1: Generate basis function block .stl's

% Build input 'params' to pass through main function

% Fields:

% modes: specify n, m modes (1,1), (2,2), ...
% modes can be combined (1 row per mode)

% amplitudes: specify the amplitude of each mode, mapping each to
% corresponding mode

% coeffs: somewhat redundant from amplitudes, but allows you to dial up
% "how much" of each mode is present 

% thickness: default 25 mm, but specifies depth of block

% Nx, Ny: spatial resolution in x, y directions (30-40 per wavelength is
% good)

% transition_width: transition from backing block to mode shape. default
% 2mm is plenty

% smoothing sigma: gaussian smoothing parameter, default 0.5 is good

params.modes      = [1 1];
params.amplitudes = [1.0];
params.coeffs     = [1.0];

params.Nx = 21;
params.Ny = 21;

params.Lx = 100; 
params.Ly = 100;

params.thickness = 12 ;

params.export = false ;

params.filename = 'trial_mode.stl';

subroutineDir = 'C:\Users\coled\Notre Dame\Github\Peters-Lab-PC\FTSI\fourier_routines';
cd(subroutineDir)
generateFourierModeSTL(params);