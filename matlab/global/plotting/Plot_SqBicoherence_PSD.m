function Plot_SqBicoherence_PSD(F, bic, Freq_Ny_kHz, Sxx, fs, colorlims)
% Plot_SqBicoherence_PSD - Plots squared bicoherence and PSD in a tiled layout
%
% Inputs:
%   F            - frequency vector for bicoherence (Hz)
%   bic          - squared bicoherence matrix
%   colorlims    - [min max] color limits for bicoherence (optional, default [0 1])
%   Freq_Ny_kHz  - frequency vector for PSD (kHz)
%   Sxx          - PSD vector
%   fs           - sampling frequency (Hz)

% Set default color limits if not provided
if nargin < 6 || isempty(colorlims)
    colorlims = [0 max(bic(:))];
end

figure; 
tiledlayout(2,1);
% --- PSD plot ---
nexttile; hold on
semilogy(Freq_Ny_kHz, Sxx, 'LineWidth', 2); grid on;
xlim([0 fs/2/1000])
set(gca, 'YScale', 'log');  % log y-axis only
set(gca,'layer','top'); 
xlabel('$f$ (kHz)','Interpreter','latex'); 
ylabel('$S_{xx}$ (/Hz)','Interpreter','latex');

% --- Bicoherence contour ---
nexttile; hold on
contourf(F/1000, F/1000, bic', 100,'EdgeColor', 'none'); 
shading interp; axis equal tight; grid on;  
ylim([0 fs/4/1000]); xlim([0 fs/2/1000]);
set(gca,'layer','top'); 
xlabel('$f_1$ (kHz)','Interpreter','latex'); 
ylabel('$f_2$ (kHz)','Interpreter','latex');
c = colorbar; 
c.Label.String = '$b^2$'; 
c.Label.Interpreter = 'latex';
colormap(parula)
clim(colorlims)
plot(F/1000, F/1000, 'r--', 'LineWidth', 1.5);  % red dashed line
x0 = 200; y0 = 200; width = 700; height = 700;  set(gcf,'position',[x0,y0,width,height])

end