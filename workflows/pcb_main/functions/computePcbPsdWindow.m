function [frequency, powerSpectralDensity] = computePcbPsdWindow( ...
    signal, samplingRate, cfg)
%COMPUTEPCBPSDWINDOW Compute one Welch PSD using PCB workflow settings.

signal = signal(:);

if numel(signal) < 2
    frequency = [];
    powerSpectralDensity = [];
    return
end

segmentCount = cfg.psd.segmentCount;
overlap = cfg.psd.overlap;
method = char(cfg.psd.method);
filtAmount = cfg.psd.filtAmount;

[powerSpectralDensity, frequencyKHz] = Power_Spectral_Density( ...
    signal, ...
    samplingRate, ...
    segmentCount, ...
    overlap, ...
    method, ...
    [], ...
    filtAmount);

frequency = frequencyKHz * 1e3;
end
