function Sxx_clean = removeBroadNoisePeaks(FreqNoise, SxxNoise, Freq, Sxx, Fband)
    % Fband = [Fmin, Fmax] in same units as Freq
    Fmin = Fband(1);
    Fmax = Fband(2);

    % Ensure column vectors
    FreqNoise = FreqNoise(:);
    SxxNoise = SxxNoise(:);
    Freq = Freq(:);
    Sxx = Sxx(:);

    % Only consider wind-off spectrum in frequency band
    band_mask = (FreqNoise >= Fmin) & (FreqNoise <= Fmax);
    SxxNoise_band = SxxNoise(band_mask);
    FreqNoise_band = FreqNoise(band_mask);

    % Normalize
    SxxNoise_norm = SxxNoise_band / max(SxxNoise_band);

    % Detect peaks
    [~, peak_idx_noise] = findpeaks(SxxNoise_norm);
    peak_freqs = FreqNoise_band(peak_idx_noise);

    % Initialize mask
    mask = ones(size(Sxx));

    % Match frequencies in wind-on spectrum
    [~, idx_match] = min(abs(Freq - peak_freqs'), [], 1);

    % Zero out corresponding points
    mask(idx_match) = mask(idx_match)/2;

    % Apply mask
Sxx_clean = Sxx .*smooth( mask, 0.1, 'rloess'); % 10% of data as window
end