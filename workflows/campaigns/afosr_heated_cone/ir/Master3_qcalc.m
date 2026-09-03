% Thomas Juliano, edited by Harrison Yates
% 10-11-12, edited 5/7/17
% qcalc.m translated and enhanced from qcalc96.for
% calculates heat transfer from wall and backface temperatures

%% set material properties

%close all; clear all; clc;
materialID_1 = 'PEEK'; % material ID number.  See materials.m
[cp, k, rho] = materials(materialID_1);
thermdiff = k / (rho*cp); % (m^2/s) thermal diffusivity (alpha)

%% define geometry, Tc
[m,n] = size(Tc(:,:,1));
thickcalc = zeros(size(Tc(:, :, 1))) ;
for i = 1:m
    for j = 1:n
        thickcalc(i,j) = 0.00762; % (meters) it is variable so this is a source of uncertainty
    end
end

%% set coordinate system
close all;clc; cd(MainDir)
%--------------------------------------------------------------------------

% coord = 0; % flat plate (Cartesian)
coord = 1; % cylindrical
% coord = 2; % spherical

% choose back face boundary condition
% backface = [1 0 0]; % back face thermocouple
 %backface = [0 1 0]; % adiabatic
 backface = [0 0 1]; % isothermal
% backface = [0.5 0 0.5]; % mutant hybrid

% n.b.: TBabiabatic is only calculated correctly when backface = [0 1 0]

nodes_user_max = 80;

%% compute number of nodes based upon time step and stability criteria
close all;clc; cd(MainDir)
%--------------------------------------------------------------------------

N = total_frames; % number of data points
sampling = 355; % (Hz) mean sampling rate
t = linspace(0, N/sampling, N);
dt = [0; diff(t)']; % (s) time step   
dx_min = sqrt(thermdiff*max(dt)*2); % (m) minimum thickness step
nodes_user_max = 50 ;
clear dx

for i = 1:m
    for j = 1:n
        nodes_stability_max = floor(0.9.*thickcalc(i,j)./dx_min); % maximum nodes in wall
        I = min([nodes_user_max, nodes_stability_max]);
        dx(i,j) = thickcalc(i,j)./(I-1); % (m) thickness step size
    end
end

%% define radius for cylindrical or spherical coordinate calculations
close all;clc; cd(MainDir)
%--------------------------------------------------------------------------

clear rcalc
clc
for i = 1:m
    for j = 1:n
        if exist('radius_inside', 'var') == 1
            rcalc(i,j,:) = linspace(Rc(i,j), thickcalc(i,j), I); % (m) local radius of curvature
        elseif isinf(Rc(i,j))
            rcalc(i,j,:) = inf*ones(1, I); % (m) local radius of curvature
        else
            rcalc(i,j,:) = linspace(Rc(i,j), Rc(i,j)-thickcalc(i,j), I); % (m) local radius of curvature
        end
        % if Rc(i,j) < 0
        %     r(i,j,:) = -r(i,j,:); % (m) radius
        % end
        
    end
end

%% qcalc Tc 
close all;clc; cd(MainDir)
%--------------------------------------------------------------------------
qdot = zeros(size(Tc));

for i = 1:m
    for j = 1:n
        Tcalc = zeros(N, I); % (K) temperature; each row is one time, each column, one location
        Tcalc(1, :) = linspace(Tc(i,j,1), Tc(i,j,1), I); % (K) initial temperature
        Tcalc(:, 1) = Tc(i,j,1:N); % (K) boundary condition from TC data (camera data)
        Tcalc(:, I) = Tc(i,j,1); % (K) boundary condition from TC data (backface)
        TBadiabatic(i,j,:) = Tc(i,j,1)*ones(N, 1);
        TBisothermal(i,j) = Tc(i,j,1);   %changed
        if backface(3)==1
            TBcalc_hchc3(i,j,:) = TBisothermal(i,j)*ones(N, 1);
        end

        % loop through time and loc
        for jj = 2:1:N % time index
            for kk = 2:1:I-1 % location index

                dTTTcalc = ((thermdiff*dt(jj))/(dx(i,j)^2)) * (Tcalc(jj-1,kk+1) - (2*Tcalc(jj-1,kk)) + Tcalc(jj-1,kk-1))...
                    - (coord * ((thermdiff*dt(jj))/dx(i,j)/rcalc(i,j,kk)/2) * (Tcalc(jj-1,kk+1)-Tcalc(jj-1,kk-1)));
                Tcalc(jj,kk) = Tcalc(jj-1,kk)+dTTTcalc;
            end
            TBadiabatic(i,j,jj) = ((4*Tcalc(jj-1, I-1)) - Tcalc(jj-1, I-2)) / 3; % adiabatic definition of back face T
            Tcalc(jj, I) = sum(backface .* [TBcalc_hchc3(i,j,jj) TBadiabatic(i,j,jj) TBisothermal(i,j)]);
            qdot(i,j,jj) = ((-0.5*k)/dx(i,j))* ((-3*Tcalc(jj,1))+(4*Tcalc(jj,2))-Tcalc(jj,3)); % (W/m^2) heat flux
            %qdotB(i,j,nn) = -0.5*k/dx(i,j)* (-3*T(nn,I)+4*T(nn,I-1)-T(nn,I-2)); % (W/m^2) heat flux at back face
        end

    end
    if mod(i,50)==0
        fprintf('%d of %d\n', i, m)
    end
end


%% Save results to .mat
saveResults = 1;
FrameView = 440 ; 

if saveResults

    % ---- save location ----
    saveRoot = "C:\Users\coled\Notre Dame\Github\Peters-Lab-PC\AFOSR_HeatedCone\Saved_Reduction_mats";

    if ~exist(saveRoot, 'dir')
        mkdir(saveRoot);
    end

    % ---- build run name ----
    stamp = datestr(now,'yyyymmdd_HHMMSS');
    runTag = sprintf('qcalc_%s_%s', materialID_1, stamp);

    saveName = fullfile(saveRoot, sprintf('%s_data.mat', runTag));

    % ---- pack outputs into struct ----
    out = struct();

    % metadata
    out.meta = struct();
    out.meta.materialID      = materialID_1;
    out.meta.coord           = coord;
    out.meta.backface        = backface;
    out.meta.nodes_user_max  = nodes_user_max;
    out.meta.total_frames    = total_frames;
    out.meta.sampling        = sampling;
    out.meta.N               = N;
    out.meta.m               = m;
    out.meta.n               = n;

    % save if they exist in workspace
    if exist('cone_length','var')
        out.meta.cone_length = cone_length;
    end
    if exist('FrameView','var')
        out.meta.FrameView = FrameView;
    end
    if exist('AveFrames','var')
        out.meta.AveFrames = AveFrames;
    end
    if exist('MainDir','var')
        out.meta.MainDir = MainDir;
    end

    % material properties
    out.material = struct();
    out.material.cp        = cp;
    out.material.k         = k;
    out.material.rho       = rho;
    out.material.thermdiff = thermdiff;

    % geometry / grids
    out.grid = struct();
    if exist('XC','var');   out.grid.XC   = XC;   end
    if exist('YC','var');   out.grid.YC   = YC;   end
    if exist('ZC','var');   out.grid.ZC   = ZC;   end
    if exist('PhiC','var'); out.grid.PhiC = PhiC; end
    if exist('Rc','var');   out.grid.Rc   = Rc;   end

    % reduction settings / supporting arrays
    out.reduction = struct();
    out.reduction.thickcalc = thickcalc;
    out.reduction.dx        = dx;
    out.reduction.dt        = dt;
    out.reduction.t         = t;
    if exist('rcalc','var'); out.reduction.rcalc = rcalc; end

    % main reduced fields needed later
    out.fields = struct();
    out.fields.Tc   = Tc;
    out.fields.qdot = qdot;

    % optional boundary-temperature products if you want them later
    if exist('TBadiabatic','var')
        out.fields.TBadiabatic = TBadiabatic;
    end
    if exist('TBisothermal','var')
        out.fields.TBisothermal = TBisothermal;
    end
    if exist('TBcalc_hchc3','var')
        out.fields.TBcalc_hchc3 = TBcalc_hchc3;
    end

    % ---- save ----
    save(saveName, 'out', '-v7.3');

    fprintf('Saved reduced qcalc results to:\n%s\n', saveName);

end
