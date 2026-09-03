function [f_peak, A_peak, Power_peak] = find_band_peak(freq_kHz, PSD, prange, peak_dec,ShowPeaks)
% FINDBANDPEAK identifies the dominant peak frequency within a given range.
% freq_kHz : frequency array [kHz]
% PSD      : power spectral density (same size)
% prange   : [fmin fmax] in kHz
% peak_dec : fractional drop from max to define scaled level (e.g., 0.3)

% Restrict to specified band
band_idx = freq_kHz >= prange(1) & freq_kHz <= prange(2);
f_band = freq_kHz(band_idx);
PSD_band = PSD(band_idx);

if isempty(f_band)
    error('No frequencies found within prange [%g %g] kHz.', prange(1), prange(2));
end

% Find local maximum in the band
[PSD_max, i_max] = max(PSD_band);
scaled_val = PSD_max * peak_dec;

% Lower crossing
i_lower = find(PSD_band(1:i_max) <= scaled_val, 1, 'last');
if isempty(i_lower), i_lower = 1; end
if i_lower == i_max, i_lower = max(1,i_max-1); end
f_lower = interp1(PSD_band(i_lower:i_lower+1), f_band(i_lower:i_lower+1), scaled_val, 'linear', f_band(i_lower));

% Upper crossing
i_upper = i_max - 1 + find(PSD_band(i_max:end) <= scaled_val, 1, 'first');
if isempty(i_upper), i_upper = length(PSD_band)-1; end
if i_upper == i_max, i_upper = min(length(PSD_band)-1,i_max+1); end
f_upper = interp1(PSD_band(i_upper:i_upper+1), f_band(i_upper:i_upper+1), scaled_val, 'linear', f_band(i_upper));

% Compute averaged peak frequency and amplitude
f_peak = mean([f_lower f_upper]);
A_peak = interp1(f_band, PSD_band, f_peak);

% Compute integrated power in the band
Power_peak = trapz(f_band, PSD_band);

% Optional plot
if ShowPeaks == 1
plot([f_band(1) f_band(end)], [scaled_val scaled_val], 'k--','HandleVisibility','off')
plot(f_band(i_max), PSD_max, 'rO', 'MarkerSize', 10, 'LineWidth', 1.5,'HandleVisibility','off')
plot([f_lower f_upper], [scaled_val scaled_val], 'ko', 'MarkerSize', 8,'HandleVisibility','off')
plot(f_peak, A_peak, 'r*', 'MarkerSize', 8, 'LineWidth', 1.5,'HandleVisibility','off')
end
end