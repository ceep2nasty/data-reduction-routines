function varargout = psd_estimate(x, fs, method, nfft, doPlot)
% PSD_ESTIMATE  Estimate power spectral density using FilterBank, Welch, or Both
%
%   Usage:
%       % Normal multiple outputs
%       [f,Pxx] = psd_estimate(x,fs,'FilterBank',256,1);
%       [f_FB,Pxx_FB,f_Welch,Pxx_Welch] = psd_estimate(x,fs,'Both',256,1);
%
%       % Single-cell output containing everything
%       out = psd_estimate(x,fs,'Both',256,1);
%       f_FB      = out{1};
%       Pxx_FB    = out{2};
%       f_Welch   = out{3};
%       Pxx_Welch = out{4};

    if nargin < 3 || isempty(method), method = 'FilterBank'; end
    if nargin < 4 || isempty(nfft), nfft = 256; end
    if nargin < 5, doPlot = false; end

    x = x(:);

    switch lower(method)
        case 'filterbank'
            % FilterBank PSD using dsp.SpectrumEstimator
            Hs = dsp.SpectrumEstimator( ...
                'SampleRate', fs, ...
                'SpectrumType', 'Power density', ...
                'FrequencyRange', 'onesided', ...
                'SpectralAverages', 10, ...
                'FFTLengthSource', 'Property', ...
                'FFTLength', nfft);

            Pxx = Hs(x);
            f = getFrequencyVector(Hs);
            Pxx = 10*log10(Pxx);

            outputs = {f, Hs(x)};

            if doPlot
                figure;
                plot(f, Pxx, 'b-', 'LineWidth', 1.5);
                grid on; xlabel('Frequency (Hz)'); ylabel('PSD (dB/Hz)');
                title('FilterBank PSD Estimate');
            end

        case 'welch'
            win = hamming(nfft);
            noverlap = round(0.5*length(win));
            [Pxx, f] = pwelch(x, win, noverlap, nfft, fs, 'onesided');
            Pxx = 10*log10(Pxx);

            outputs = {f, Pxx};

            if doPlot
                figure;
                plot(f, Pxx, 'r-', 'LineWidth', 1.5);
                grid on; xlabel('Frequency (Hz)'); ylabel('PSD (dB/Hz)');
                title('Welch PSD Estimate');
            end

        case 'both'
            % FilterBank
            Hs = dsp.SpectrumEstimator( ...
                'SampleRate', fs, ...
                'SpectrumType', 'Power density', ...
                'FrequencyRange', 'onesided', ...
                'SpectralAverages', 10, ...
                'FFTLengthSource', 'Property', ...
                'FFTLength', nfft);

            Pxx_FB = Hs(x);
            f_FB = getFrequencyVector(Hs);
            Pxx_FB = 10*log10(Pxx_FB);

            % Welch
            win = hamming(nfft);
            noverlap = round(0.5*length(win));
            [Pxx_Welch,f_Welch] = pwelch(x, win, noverlap, nfft, fs, 'onesided');
            Pxx_Welch = 10*log10(Pxx_Welch);

            outputs = {f_FB, Pxx_FB, f_Welch, Pxx_Welch};

            if doPlot
                figure;
                plot(f_FB, Pxx_FB, 'b-', 'LineWidth', 1.5, 'DisplayName','FilterBank');
                hold on;
                plot(f_Welch, Pxx_Welch, 'r--', 'LineWidth', 1.5, 'DisplayName','Welch');
                grid on; xlabel('Frequency (Hz)'); ylabel('PSD (dB/Hz)');
                title('FilterBank vs Welch PSD Estimate');
                legend('show');
            end

        otherwise
            error('Unknown method. Use ''FilterBank'', ''Welch'', or ''Both''.');
    end

    % --- Assign outputs ---
    if nargout <= 1
        % Single output: return everything in a cell array
        varargout{1} = outputs;
    else
        % Multiple outputs: unpack
        for k = 1:nargout
            varargout{k} = outputs{k};
        end
    end
end