function [Sxx, Freq_Ny_kHz, Freq_Resolution] = Power_Spectral_Density(x, fsamp, nseg, pct_overlap, method, numBands,FiltAmount)
% PSDit Computes one-sided PSD using specified method
%
% Inputs:
%   x           - signal vector
%   fsamp       - sampling frequency [Hz]
%   nseg        - number of segments
%   pct_overlap - fractional overlap (0-1, e.g., 0.5 for 50%)
%   method      - optional string: 'original' (default) or 'pwelch'
%   numBands    - optional for filterbank (default 20)
%
% Outputs:
%   Sxx             - one-sided PSD
%   Freq_Ny_kHz     - frequency vector [kHz]
%   Freq_Resolution - frequency resolution [Hz]

if nargin < 5 || isempty(method), method = 'pwelch'; end
if nargin < 6 || isempty(numBands), numBands = 20; end

x = x(:);
N = length(x);

% Determine segment length and step from nseg and pct_overlap
pointsperblock = floor(N/nseg);
step = floor(pointsperblock*(1 - pct_overlap));
if step < 1, error('Percent overlap too high for number of segments.'); end

switch lower(method)
    case 'original'
        %% Block-averaged Hanning PSD
        Nblocks = floor((N-pointsperblock)/step)+1;
        Sxx_accum = zeros(pointsperblock,1);
        window = 0.5*(1 - cos(2*pi*(0:pointsperblock-1)'/(pointsperblock-1)));
        U = sum(window.^2)/pointsperblock;

        for k = 1:Nblocks
            idx = (1:pointsperblock) + (k-1)*step;
            X = fft(x(idx).*window)/pointsperblock;
            Sxx_accum = Sxx_accum + abs(X).^2 / U * (pointsperblock/fsamp);
        end
        Sxx_mean = Sxx_accum / Nblocks;
        half = floor(pointsperblock/2);
        Sxx = Sxx_mean(1:half); Sxx(2:end)=2*Sxx(2:end);
        Freq_Ny_kHz = (0:half-1)'*fsamp/pointsperblock/1000;
        Freq_Resolution = fsamp/pointsperblock;

    case 'pwelch'
        %% MATLAB pwelch PSD
        WIN = blackman(pointsperblock);
        [Pxx, f] = pwelch(x, WIN, round(pct_overlap*pointsperblock), pointsperblock, fsamp);
        
        f_cutoff = 10e3; % kHz below which low freq is preserved
        Pxx_sm = Pxx;
        Pxx_sm(f > f_cutoff) = sgolayfilt(Pxx_sm(f > f_cutoff), 2, FiltAmount);
        Sxx = Pxx_sm;
        Freq_Ny_kHz = f/1000;
        Freq_Resolution = fsamp/pointsperblock;

    case 'filterbank'
        %% Filterbank PSD (FFT + sum across bands)
        edges = linspace(1, fsamp/2-1, numBands+1);
        Sxx = zeros(floor(N/2)+1,1);
        for k = 1:numBands
            Wn = edges(k:k+1)/(fsamp/2); Wn(Wn<=0)=0.001; Wn(Wn>=1)=0.999;
            b = fir1(128,Wn);
            xfilt = filter(b,1,x);
            Xf = fft(xfilt)/N;
            Pxx = (abs(Xf(1:floor(N/2)+1)).^2)*2;
            Sxx = Sxx + Pxx;
        end
        Freq_Ny_kHz = (0:floor(N/2))'*fsamp/N/1000;
        Freq_Resolution = fsamp/N;

    case 'filterbank_pwelch'
        %% Filterbank PSD (pwelch per band)
        edges = linspace(1, fsamp/2-1, numBands+1);
        Sxx = zeros(floor(pointsperblock/2)+1,1);
        for k = 1:numBands
            Wn = edges(k:k+1)/(fsamp/2); 
            Wn(Wn<=0)=0.001; Wn(Wn>=1)=0.999;
            b = fir1(128, Wn);
            xfilt = filter(b,1,x);
            [Pxx, f] = pwelch(xfilt, pointsperblock, round(pct_overlap*pointsperblock), pointsperblock, fsamp);
            Sxx = Sxx + Pxx;
        end
        Freq_Ny_kHz = f/1000;
        Freq_Resolution = fsamp/pointsperblock;
end
end