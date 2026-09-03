function plotMajorPeaksPSD(Freq_Ny_kHz, Sxx, ytop)
    if nargin < 3 || isempty(ytop)
        ytop = max(Sxx) * 1.05;  % default slightly above top of figure
    end

    baseline = movmean(Sxx, 10);  % smooth PSD
    [pks, locs] = findpeaks(Sxx - baseline, Freq_Ny_kHz, 'MinPeakDistance', 35);
    majorIdx = pks > 1e-4*max(Sxx);  % significant peaks
    locs = locs(majorIdx);

    for i = 1:length(locs)
        xline(locs(i), '--k', 'HandleVisibility','off','LineWidth',1.5);
        text(locs(i)+55, ytop-ytop*0.6, sprintf('%.1f kHz', locs(i)), ...
            'VerticalAlignment','bottom', 'HorizontalAlignment','center', ...
            'FontSize',19, 'Rotation',90)
    end

    xlabel('Frequency (kHz)'); ylabel('Sxx'); grid on
end