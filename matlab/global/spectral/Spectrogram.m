function [T,F, SpectroLog] = Spectrogram(sig, fsamp, nseg, pct_overlap, cmap, fband)
% PLOT_SPECTROGRAM  Plots spectrogram of a signal with optional frequency band
% sig: signal vector
% fsamp: sampling frequency (Hz)
% nseg: segment length for FFT
% pct_overlap: fraction overlap (0–1)
% cmap: (optional) colormap, e.g., 'turbo'
% fband: (optional) [fmin fmax] in Hz

if nargin < 5 || isempty(cmap), cmap = 'turbo'; end
if nargin < 6, fband = []; end

window = hamming(nseg);
noverlap = round(pct_overlap * nseg);
[S,F,T] = spectrogram(sig, window, noverlap, nseg, fsamp, 'yaxis');
SpectroLog = abs(S);

% Limit to desired frequency band
if ~isempty(fband)
    idx = F >= fband(1) & F <= fband(2);
    F = F(idx); SpectroLog = SpectroLog(idx,:);
end

end