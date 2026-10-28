%% Plot Contour of temperature and heat flux
% Requires qdot from Master3_qcalc; use xTExtract for temperature-only results.
MainDir = 'C:\Users\coled\Notre Dame\Github\data-reduction-routines\workflows\campaigns\afosr_heated_cone\ir';
repoRoot = 'C:\Users\coled\Notre Dame\Github\data-reduction-routines';
addpath(MainDir, genpath(fullfile(repoRoot,'matlab')));
close all; clc
FrameView = 220;
AveFrames = 10;
%qdot_filt = filloutliers(qdot(:,:,FrameView),'linear');

%% option to load previously saved results if not a new reduction process
loadPrevious = 0;

if loadPrevious

    ResultsDir = "Z:\Cole\heated_cone\heatedCone_F26\AFOSR_Heated_Cone_Jan2026\January_2026_IR_Data\Saved_Reduction_mats";
    [file,path] = uigetfile(fullfile(ResultsDir,'*_data.mat'),'Select saved IR result');
    if isequal(file,0); error('No file selected.'); end

    load(fullfile(path,file),'out');

    % ---- recover metadata ----
    if isfield(out.meta,'FrameView');   FrameView   = out.meta.FrameView;   end
    if isfield(out.meta,'AveFrames');   AveFrames   = out.meta.AveFrames;   end
    if isfield(out.meta,'cone_length'); cone_length = out.meta.cone_length; end

    % ---- recover grids ----
    XC   = out.grid.XC;
    YC   = out.grid.YC;
    ZC   = out.grid.ZC;
    PhiC = out.grid.PhiC;

    % ---- recover reduced fields ----
    Tc   = out.fields.Tc;
    qdot = out.fields.qdot;

end



%% Primary contour plotting block
assert(exist('qdot','var') == 1, ...
    'Heat-flux plots require qcalc results. Use xTExtract for temperature-only extraction.');
i1 = round(FrameView - AveFrames*0.5);
i2 = round(FrameView + AveFrames*0.5);
qdot_TimeAve = mean(qdot(:,:,i1:i2),3);
xMin = XC(1) + 0.02 ;
xMax = cone_length -0.05 ;
Tc_frame = Tc(:,:,FrameView) ;


figure; tiledlayout('flow')
nexttile
surf(XC,YC,ZC,(Tc_frame)); shading interp
axis equal tight; colorbar
xlim([xMin, xMax]);
title('Temperature in Celsius mapped to cone') ;
nexttile
surf(XC,YC,ZC,qdot_TimeAve); shading interp
axis equal tight
xlim([xMin, xMax]);
x0=10; y0=10; width=1000*1.25; height=400*1.25; set(gcf,'position',[x0,y0,width,height]);colorbar
title('Heat Flux (W/m^2) mapped to cone') ;
nexttile
surf(XC,YC,qdot_TimeAve); shading interp;view(2); axis equal tight
xlim([xMin, xMax]);
x0=10; y0=10; width=1000*1.25; height=400*1.25; set(gcf,'position',[x0,y0,width,height]);colorbar
title('Heat Flux (W/m^2) mapped to cone (viewed from above)') ;
nexttile
surf(XC,PhiC,qdot_TimeAve); shading interp;view(2);
xlim([xMin, xMax]);
x0=10; y0=10; width=1000*1.25; height=400*1.25; set(gcf,'position',[x0,y0,width,height]);colorbar
xlabel('axial position (m)'); ylabel('azimuthal position (degrees)');
title('Heat Flux (W/m^2) mapped to x-phi space')

%%
clear centerq_iso3

tf = 180; %which frame to take[

%filter in phi
for i = 5:357
   centerq_iso3(i,:) = (1/9)*(qdot(i-4,:,tf)+qdot(i-3,:,tf)+qdot(i-2,:,tf)+qdot(i-1,:,tf)+qdot(i,:,tf)+qdot(i+1,:,tf)+qdot(i+2,:,tf)+qdot(i+3,:,tf)+qdot(i+4,:,tf));
end

%filter in x
for i = 7:600
   centerq_iso3_filt(i) = (1/13)*(centerq_iso3(179,i-6)+centerq_iso3(179,i-5)+centerq_iso3(179,i-4)+centerq_iso3(179,i-3)+centerq_iso3(179,i-2)+centerq_iso3(179,i-1)+centerq_iso3(179,i)+centerq_iso3(179,i+1)+centerq_iso3(179,i+2)+centerq_iso3(179,i+3)+centerq_iso3(179,i+4)+centerq_iso3(179,i+5)+centerq_iso3(179,i+6));
end
   
xx = linspace(.375,.755,length(centerq_iso3_filt));

figure()
plot(xx,centerq_iso3_filt./1000)

%% Centerline heating correlation
close all; clc
FrameView = 440;
AveFrames = 5;

i1 = round(FrameView - AveFrames*0.5);
i2 = round(FrameView + AveFrames*0.5);
qdot_TimeAve = mean(qdot(:,:,i1:i2),3);
xMin = XC(1) + 0.02 ;
xMax = cone_length -0.05 ;

qdot_TimeAve_SpanAve = mean(qdot_TimeAve,1);
qdot_TimeAve_SpanAve = filloutliers(qdot_TimeAve_SpanAve,'linear');
Tc_TimeAve = mean(Tc(1:end,:,FrameView:FrameView+AveFrames),3);
Tc_TimeAve_SpanAve = mean(Tc_TimeAve,1);
Tc_TimeAve_SpanAve = filloutliers(Tc_TimeAve_SpanAve,'linear');
M = 5.7;
T0 = 435;
P0 = 90*6895;

[Re_per_m,T_inf,rho_infty,a_inf,u_infty,mu_inf] = freestreamFromStagnation(T0,P0,M);
c_p_air = 1004; % (J/kg/K)
Stanton_profile = qdot_TimeAve_SpanAve./(u_infty*rho_infty*c_p_air*(T0-Tc_TimeAve_SpanAve));
figure;tiledlayout('vertical')
nexttile; hold on
StartX = 1;
plot(XC(1,StartX:end),qdot_TimeAve_SpanAve(StartX:end),'LineWidth',2)
nexttile; hold on
h1 = plot(XC(1,StartX:end),movmean(Stanton_profile(StartX:end),40)*1000,'LineWidth',2) ;
ylim([0 3])
Reuse = Re_per_m;
M = 5.7;
oL = -0.5; % omega laminar
oT = -0.2; % omega turbulent
aL = -0.197; % alpha laminar
aT = -0.363; % alpha turbulent
BL = 0.7565; % B laminar for 7 deg.
BT = 0.0461; % B turbulent for 7 deg.
VecX = (0:.001:1);
StL = BL *  M.^aL .* (Reuse* VecX).^oL; % laminar St
StT = BT *  M.^aT .* (Reuse * VecX).^oT; % turbulent St
h2 = plot(VecX,StL.*1000,'k-','linewidth',1.5) ;
h3 = plot(VecX,StT.*1000,'k--','linewidth',1.5) ;
legend([h1 h2 h3], {'Measured Centerline St', 'Laminar correlation', 'Turbulent correlation'} , ...
    'Location', 'northeast') ;

xpl = XC(1,StartX:end);
ypl = movmean(Stanton_profile(StartX:end),40) * 1000;
