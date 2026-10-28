%% Spanwise Average of Heatflux 
% Requires qdot_TimeAve from contourPlots_main; xTExtract needs no heat flux.
assert(exist('qdot_TimeAve','var') == 1 && exist('PhiC','var') == 1, ...
    'Run the heat-flux contour averaging block first, or use xTExtract for temperature.');

% qdot_TimeAve is size [Nphi, Nx]
[Nphi, Nx] = size(qdot_TimeAve);

phiCenter = 0;
phiNan    = 4;
phiAve    = 10;

phiVec = PhiC(:,1); % use the actual mapped angular grid

maskBand = abs(phiVec - phiCenter) <= phiAve;     % 1xNphi logical
qdotKeep = qdot_TimeAve(maskBand, :);             % Nkeep x Nx
phiKeep  = phiVec(maskBand);

maskNan = abs(phiKeep - phiCenter) <= phiNan;
qdotKeep(maskNan, :) = NaN;

qdotFill = fillmissing(qdotKeep, 'linear', 1, 'EndValues','nearest');

qdot_stream = mean(qdotFill, 1, 'omitnan');      


% plot it

PhiCKeep = PhiC(maskBand, :) ; 
XCKeep = XC(maskBand, :) ;

figure
surf(XCKeep, PhiCKeep, qdotFill) ; colorbar ; 
shading interp
view(2)
axis tight
xlabel('x (m)','FontSize',20,'FontName','Times New Roman') ; 
ylabel('\phi (deg)','FontSize',20,'FontName','Times New Roman');
title('Heat flux about centerline (PCBs removed)', ...
      'FontSize',20,'FontName','Times New Roman')

set(gca,'FontSize',20,'FontName','Times New Roman')
