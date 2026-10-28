%% Centerline temperature profile (run after Master2_ImageMapping; no qcalc needed)
% Uses a near-centerline band, excluding the PCB strip, rather than direct phi=0.
MainDir = 'C:\Users\coled\Notre Dame\Github\data-reduction-routines\workflows\campaigns\afosr_heated_cone\ir';
repoRoot = 'C:\Users\coled\Notre Dame\Github\data-reduction-routines';
addpath(MainDir, genpath(fullfile(repoRoot,'matlab')));

%% Optionally load a previously saved mapped result
loadPrevious = 0; % 0 uses Tc, XC and PhiC already in the workspace
ResultsDir = 'Z:\Cole\heated_cone\heatedCone_F26\AFOSR_Heated_Cone_Jan2026\January_2026_IR_Data\Saved_Reduction_mats';
if loadPrevious
    [file,path] = uigetfile(fullfile(ResultsDir,'*_data.mat'),'Select mapped IR result');
    if isequal(file,0); error('No file selected.'); end
    loadedResult = load(fullfile(path,file),'out');
    Tc = loadedResult.out.fields.Tc;
    XC = loadedResult.out.grid.XC;
    PhiC = loadedResult.out.grid.PhiC;
end

%% Extraction and save settings
FrameView = 440;
AveFrames = 2; % inclusive endpoints: this selects frames 439:441
phiCenter = 0;
phiNan = 4; % exclude |phi| <= 4 degrees around the PCB strip
phiAve = 8; % average remaining samples through |phi| <= 8 degrees
caseName = 'Jan_AllH_90psi'; % set explicitly to identify the mapped dataset
saveResults = 1;
saveFolder = 'Z:\Cole\heated_cone\heatedCone_F26\AFOSR_Heated_Cone_Jan2026\January_2026_IR_Data\Saved_Temperature_Profiles';
maskAxial = 0;
xMinMask = 0.6;
xMaxMask = 1.0;

%% Average temperature over time and the band around the centerline
assert(exist('Tc','var') == 1 && exist('XC','var') == 1 && exist('PhiC','var') == 1, ...
    'Run Master2_ImageMapping first, or enable loadPrevious. qcalc is not required.');
assert(isequal(size(XC),size(PhiC),size(Tc(:,:,1))), ...
    'Tc, XC and PhiC must use the same spatial grid.');
i1 = round(FrameView-AveFrames*0.5);
i2 = round(FrameView+AveFrames*0.5);
assert(i1 >= 1 && i2 <= size(Tc,3) && i1 <= i2, 'Selected frames are outside Tc.');
assert(phiNan >= 0 && phiAve > phiNan, 'Require 0 <= phiNan < phiAve.');
TcSelected = Tc(:,:,i1:i2);
assert(~any(imag(TcSelected(:)) ~= 0), ...
    'Selected Tc frames contain imaginary values. Check the emissivity correction before extraction.');
Tc_TimeAve = mean(TcSelected,3); % preserves missing temporal data as NaN
phiVec = PhiC(:,1);
maskBand = abs(phiVec-phiCenter) <= phiAve;
phiKeep = phiVec(maskBand);
maskNan = abs(phiKeep-phiCenter) <= phiNan;
assert(any(~maskNan), 'No samples remain in the selected angular band.');
TcMasked = Tc_TimeAve(maskBand,:);
TcMasked(maskNan,:) = NaN;
Tc_stream = mean(TcMasked,1,'omitnan');
Tc_x = Tc_stream;
Tc_x_Kelvin = Tc_x+273.15;
xVec = XC(1,:);
assert(any(isfinite(Tc_x)), 'No finite temperatures remain in the selected band.');
PhiCKeep = PhiC(maskBand,:);
XCKeep = XC(maskBand,:);
xPlot = xVec;
TcPlot = Tc_x_Kelvin;
if maskAxial
    maskX = xVec >= xMinMask & xVec <= xMaxMask;
    xPlot = xVec(maskX);
    TcPlot = Tc_x_Kelvin(maskX);
end

%% Save extracted temperatures and provenance to MAT before exporting figures
profileMeta = struct('caseName',caseName,'FrameView',FrameView, ...
    'AveFrames',AveFrames,'frameIndices',i1:i2,'phiCenter',phiCenter, ...
    'phiNan',phiNan,'phiAve',phiAve,'maskAxial',maskAxial, ...
    'xMinMask',xMinMask,'xMaxMask',xMaxMask, ...
    'temperatureUnits','K (Tc_x_Kelvin), Celsius (Tc_x)', ...
    'axialUnits','same as mapping xAx; expected meters', ...
    'method','Temporal mean, then angular mean excluding the central PCB strip');
if exist('frame_rate','var'); profileMeta.frame_rate = frame_rate; end
if exist('IRDir','var'); profileMeta.IRDir = IRDir; end
if exist('IRFolder','var'); profileMeta.IRFolder = IRFolder; end
if exist('DirectionalEmissivityCorrection','var')
    profileMeta.DirectionalEmissivityCorrection = DirectionalEmissivityCorrection;
end
if exist('PTM_3D','var'); profileMeta.PTM_3D = PTM_3D; end
if exist('xAx','var'); profileMeta.xAx = xAx; end
if exist('phiDeg','var'); profileMeta.phiDeg = phiDeg; end
if exist('xi','var'); profileMeta.xi = xi; end
if exist('yi','var'); profileMeta.yi = yi; end
if loadPrevious
    % Live registration variables may belong to another run; use saved metadata.
    profileMeta = rmfield(profileMeta,intersect(fieldnames(profileMeta), ...
        {'frame_rate','IRDir','IRFolder','DirectionalEmissivityCorrection', ...
        'PTM_3D','xAx','phiDeg','xi','yi'}));
    profileMeta.sourceFile = fullfile(path,file);
    if isfield(loadedResult.out,'meta'); profileMeta.sourceMeta = loadedResult.out.meta; end
end
if saveResults
    if ~exist(saveFolder,'dir'); mkdir(saveFolder); end
    stamp = datestr(now,'yyyymmdd_HHMMSS_FFF');
    saveTag = sprintf('%s_f%d-%d_phi%.1f-%.1f_%s',caseName,i1,i2,phiNan,phiAve,stamp);
    matName = fullfile(saveFolder,[saveTag '_data.mat']);
    assert(~exist(matName,'file'),'Output already exists; rerun to generate a new timestamp.');
    save(matName,'xVec','Tc_x','Tc_x_Kelvin','Tc_stream','phiVec', ...
        'phiAve','phiNan','TcMasked','xPlot','TcPlot','profileMeta');
    fprintf('Saved temperature profile (no qcalc required):\n%s\n',matName);
end

%% Plot and export the extracted profile and angular band
surfPlot = figure;
surfAx = axes('Parent',surfPlot);
surf(surfAx,XCKeep,PhiCKeep,TcMasked,'EdgeColor','none');
view(surfAx,2); axis(surfAx,'tight'); colorbar(surfAx);
xlabel(surfAx,'x (m)'); ylabel(surfAx,'phi (degrees)');
title(surfAx,sprintf('%s: frames %d-%d, central PCB strip excluded', ...
    caseName,i1,i2),'Interpreter','none');
streamPlot = figure;
streamAx = axes('Parent',streamPlot);
plot(streamAx,xPlot,TcPlot,'-','LineWidth',1.5);
xlabel(streamAx,'x (m)'); ylabel(streamAx,'Temperature (K)');
title(streamAx,sprintf('%s: %.1f < |phi| <= %.1f degrees', ...
    caseName,phiNan,phiAve),'Interpreter','none');
if saveResults
    exportgraphics(surfAx,fullfile(saveFolder,[saveTag '_surfPlot.png']),'Resolution',300);
    exportgraphics(streamAx,fullfile(saveFolder,[saveTag '_streamPlot.png']),'Resolution',300);
    savefig(surfPlot,fullfile(saveFolder,[saveTag '_surfPlot.fig']));
    savefig(streamPlot,fullfile(saveFolder,[saveTag '_streamPlot.fig']));
end
