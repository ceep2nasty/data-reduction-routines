function f_peak_time = spectrogram_peak_track(T, F, SpectroLog, prange, peak_dec)
% Tracks refined peak frequency over time from a spectrogram matrix.

% Convert dB to linear if needed
if max(SpectroLog(:)) > 1
    PSD_all = 10.^(SpectroLog/10);
else
    PSD_all = SpectroLog;
end

% Restrict frequency band
band_idx = F >= prange(1) & F <= prange(2);
F_band = F(band_idx);
PSD_band_all = PSD_all(band_idx,:);

nTime = size(PSD_band_all,2);
f_peak_time = nan(1,nTime);

for k = 1:nTime
    PSD_slice = PSD_band_all(:,k);
    
    if all(PSD_slice==0)
        continue
    end

    [PSD_max, i_max] = max(PSD_slice);
    scaled_val = PSD_max * peak_dec;

    % --- Lower crossing
    i_lower = find(PSD_slice(1:i_max) <= scaled_val, 1, 'last');
    if isempty(i_lower) || i_lower == i_max
        f_lower = F_band(i_max);
    else
        i_lower = min(i_lower, length(PSD_slice)-1);
        f_lower = interp1(PSD_slice(i_lower:i_lower+1), F_band(i_lower:i_lower+1), scaled_val, 'linear');
    end

    % --- Upper crossing
    i_upper_rel = find(PSD_slice(i_max:end) <= scaled_val, 1, 'first');
    if isempty(i_upper_rel)
        f_upper = F_band(i_max);
    else
        i_upper = i_max -1 + i_upper_rel;
        i_upper = min(i_upper, length(PSD_slice)-1);
        f_upper = interp1(PSD_slice(i_upper:i_upper+1), F_band(i_upper:i_upper+1), scaled_val, 'linear');
    end

    % Refined peak frequency
    f_peak_time(k) = mean([f_lower f_upper]);
end
end