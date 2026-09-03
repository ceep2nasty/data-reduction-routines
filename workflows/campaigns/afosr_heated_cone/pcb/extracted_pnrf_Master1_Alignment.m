
%% MASTER: PCB Process
restoredefaultpath; clear; close all; clc
%--------------------------------------------------------------------------
%--------------------------------------------------------------------------
%Author/s: Jonathan Davami
%Date created:  01/09/2025
%Date modified: 02/18/2026
%Modified by: Cole Peters
%--------------------------------------------------------------------------
%Description: This code is used for aligment with PCB sensors
%--------------------------------------------------------------------------
%--------------------------------------------------------------------------
%Setup up all required directory paths.....................................
%Load in global routines
ScriptDir = fileparts(mfilename('fullpath'));
RepoDir = 'C:\Users\coled\Notre Dame\Github\data-reduction-routines';
assert(isfolder(RepoDir), 'Repository folder not found.')
cd(RepoDir)
%Data loading directory

% Assuming work begins with converted .pnrf file - grab that parent
converted_mats_path = 'C:\Users\coled\Notre Dame\test_pcb_workflow\matlab_exports' ;

% add child folder containing exported matlab files
LoadDataDir = converted_mats_path ;
addpath(LoadDataDir)

% add name of file of interest
dataTag = 'alignment_60psi_feb2026.mat' ;

%Figure path save
% saveTag will be the name of the file stored; saveDir is the directory it
% will fall under
saveTag = 'test1';
saveDir = 'C:\Users\coled\Notre Dame\test_pcb_workflow\saved_pcb_figs';
if ~isfolder(saveDir)
    mkdir(saveDir);
end
addpath(genpath(saveDir));
%..........................................................................
%Run plot preferences
GlobalDir = fullfile(RepoDir, 'matlab', 'global');
addpath(genpath(GlobalDir));
UseFontSizeGloabl = 20;
run(fullfile(GlobalDir, 'plotting', 'font_interp_fontsize.m'));

%% LOAD: PCB data (v7.3 struct/cell style)
close all; clc; cd(RepoDir)
TestNumber = '01';
fname = fullfile(LoadDataDir, dataTag) ;
S = load(fname);
R = S.Perception_Raw ;

% Select Desired Channels
% Should be well ordered (A-Z, 1-8) in R.channel
% R.time indices match
% Using channels (Ch C01 Ch C02 Ch D01) for alignment


% PCB Array: all channels from the high-rate recorders.
PCB_MAT = [R(3).channel, R(4).channel];
Driver_Trigger = [R(1).channel(:, 1), R(2).channel(:,1)] ;

% Trigger and Kulite Array: PCB_
N = size(PCB_MAT,1); %Number of data points (#)
N_driver_trigger = size(Driver_Trigger, 1) ;
fsamp = 2*10^6; %Sample frequency (Hz)
fsamp_driver_trigger = 250*10^3; %250Hz sampling
total_time = N/fsamp; %Total time with pr trigger (s)
driver_time = N/fsamp_driver_trigger ;
Time_array_PCB = R(3).time(:) ;
Time_array_driver_trigger = R(1).time ;

%% PLOT: Traces

%Driver tube calibration
driverp=[51.7 87.8*6.89476 61*6.89476 150*6.89476 14.6*6.89476 93*6.89476].*1000; %(Pa)
driverv=[-8.08 -0.73153 -3.3495 4.8098 -7.4776 -0.5246]; %(V)
driver_FIT = polyfit(driverv,driverp,1);

%Plot PCBs, Stagnation Kulite, Valve opening,
sizethis = 25;
time_LINE = .72;

figure; tiledlayout('vertical');
nexttile; hold on; grid on
plot(Time_array_PCB,smooth(PCB_MAT(:,1)))
plot(Time_array_PCB,smooth(PCB_MAT(:,2)))
plot(Time_array_PCB,smooth(PCB_MAT(:,3)))
xline(time_LINE,'r')
set(gca, 'TickDir', 'out', 'TickLength', [.01 .01],'XMinorTick', 'on','FontSize', sizethis)
set(gca,'Box','on','linewidth',1.9,'fontsize',sizethis);

nexttile; hold on; grid on
plot(Time_array_driver_trigger,Driver_Trigger(:,1))
plot(Time_array_driver_trigger,Driver_Trigger(:,2))
xline(time_LINE,'r')
set(gca, 'TickDir', 'out', 'TickLength', [.01 .01],'XMinorTick', 'on','FontSize', sizethis)
set(gca,'Box','on','linewidth',1.9,'fontsize',sizethis);

nexttile; hold on; grid on
plot(Time_array_driver_trigger,Driver_Trigger(:,1).*driver_FIT(1)+driver_FIT(2))
hold on
xline(time_LINE,'r')
set(gca, 'TickDir', 'out', 'TickLength', [.01 .01],'XMinorTick', 'on','FontSize', sizethis)
set(gca,'Box','on','linewidth',1.9,'fontsize',sizethis);
x0=10; y0=10; width=800*1.25; height=500*1.25; set(gcf,'position',[x0,y0,width,height])

% %% PLOT: Spectrogram
% close all; clc; cd(MainDir)
% %--------------------------------------------------------------------------
% % TIME RANGE INPUT..........................................
% ON_time = [0.1 1.3];
% fband = [50e3 800e3];
% %...........................................................
% ON_numData = ON_time.*fsamp;
% cons = [1 1 1 1];
% cols = [1 2 3 4];
% % cols = [2 4 1 3];
%
% Strings = {' North wall', ' South wall', ' Bottom', 'Top'};
% PCB_MT = PCB_MAT(ON_numData(1):ON_numData(2), cols) .* cons;
%
% %Spectral parameters
% nseg = 1e3;
% pct_overlap = .75;
% cmap = (flipud(TurboPink));
% % cmap = turbo;
%
%
% figure;tiledlayout('flow');
% clear Tracked_Second_Mode f_mean_kHz Uncert_fpeak
% for iii = 1:4
%     nexttile; hold on;
%     [T,F, SpectroLog] = Spectrogram(PCB_MT(:,iii), fsamp, nseg, pct_overlap, cmap,fband);
%
%     pcolor(T, F/1e3, smoothdata(SpectroLog)); shading interp
%     xlabel('$t$ (s)'); ylabel('$f$ (kHz)');
%     colormap(cmap); colorbar; set(gca, 'ColorScale', 'log'); grid on; box on
%     ylim(fband./1e3)
%                 % Set color axis limits to enhance contrast
%                 clim_min = max(min(SpectroLog(:)), prctile(SpectroLog(:), 10));  % ignore very low values
%                 clim_max = prctile(SpectroLog(:), 99);                          % ignore extreme peaks
%                 clim([clim_min clim_max]);
%
%
%                 %Track second mode frequency through time..............................
%     % prange = [50e3 450e3];
%     % peak_dec = .1;
%     % f_peak_time = spectrogram_peak_track(T, F, SpectroLog, prange, peak_dec);
%     % Uncert_fpeak(iii) = std(f_peak_time,'omitnan')./1e3;
%     % Tracked_Second_Mode(iii,:) = filloutliers(f_peak_time, 'linear');
%     %
%     % f_mean_kHz(iii) = mean(Tracked_Second_Mode(iii,:),'omitnan')/1e3;
%     % yline(f_mean_kHz(iii), '--r', sprintf('%.2f kHz', f_mean_kHz(iii)), ...
%     %     'LabelHorizontalAlignment','right', 'LabelVerticalAlignment','bottom', ...
%     %     'FontWeight','bold', 'FontSize',12, 'Color','k', 'LineWidth',1);
%     % title(strcat(['PCB ',num2str(iii)],' ',Strings{iii}))
%     grid on; set(gca, 'GridColor', 'w', 'GridAlpha', 1) ;set(gca,'layer','top')
% end
% x0=1000; y0=10; width=450*1.25; height=900*1.25; set(gcf,'position',[x0,y0,width,height])
% %..........................................................................
%
%
%
% %Plot Tracked second mode frequency through time...........................
% figure; tiledlayout('vertical');
% nexttile; hold on; grid on
% plot(T,Tracked_Second_Mode(1,:)/1e3,'LineWidth',1)
% plot(T,Tracked_Second_Mode(2,:)/1e3,'LineWidth',1)
% plot(T,Tracked_Second_Mode(3,:)/1e3,'LineWidth',1)
% plot(T,Tracked_Second_Mode(4,:)/1e3,'LineWidth',1)
% xlabel('Time (s)'); ylabel('Second Mode Frequency (kHz)');
% grid on; box on; ylim([100 400])
%
% % Plot mean of the tracked second mode
% nexttile; hold on; grid on
% means_kHz = mean(Tracked_Second_Mode, 2,'omitnan')/1e3;   % mean of each row in kHz
% colors = lines(size(Tracked_Second_Mode,1));
% for i = 1:size(Tracked_Second_Mode,1)
%     yline(means_kHz(i), 'Color', colors(i,:), 'LineWidth', 1);
% end
% xlabel('Time (s)'); ylabel('Second Mode Frequency (kHz)');
% ylim([100 400])
% x0=1000; y0=10; width=500*1.25; height=300*1.25; set(gcf,'position',[x0,y0,width,height])
% %..........................................................................
%
% %Determine if model is aligned to the freestream...........................
% clc;
% MeanPeak = mean(means_kHz);
% PercentDeviationMean = abs(100-means_kHz./MeanPeak*100);
%
% disp('Peak frequencies are:');
% disp(f_mean_kHz');
%
% disp('Uncert. are:');
% disp(Uncert_fpeak');
%
% disp('Percent Deviations from Mean:');
% disp(PercentDeviationMean);
% %......................................................................

%% WRAPPER: loop ON_time windows + save figures

% ---- user knobs ----
ON_time_list = [ ...
    0.80 0.85
    0.85 0.90
    0.90 0.95
    0.95 1.00
    1.20 1.25
    ];

saveFig = 1;  % 1 = save outputs, 0 = just display
saveFolder = fullfile(saveDir, saveTag);
if saveFig && ~exist(saveFolder,'dir')
    mkdir(saveFolder);
end

% Keep the figure numbering stable across runs
figNumBase = 700;

% ---- wrapper loop ----
for kk = 1:size(ON_time_list,1)

    % set ON_time for this run
    ON_time = ON_time_list(kk,:);

    % fresh figure each case
    figure(figNumBase+kk); clf; hold on; grid on;



    % PLOT: PSD
    IncludeNoise = 0;
    GetPeaks =0;

    %Order the columns

    cols = 1:size(PCB_MAT, 2);
    numChannels = numel(cols) ;
    Strings = arrayfun(@(channelNumber) sprintf(' PCB %d', channelNumber), ...
        cols, 'UniformOutput', false);

    %Calibration constant
    cons = ones(1, numChannels);

    %Plot Noise------------------------------------------------------------------
    clear SavePCB_PSD_Noise
    if IncludeNoise == 1
        PlotNoisePCB_Alignment
    end

    %Spectral parameters
    nseg = 40;
    pct_overlap = .5;
    method = 'pwelch';
    FiltAmount = 3;
    DetrendCase = 'Basic';
    PlotCase = 'PSD';
    ShowPeaks = 1;

    %Plot Wind on--------------------------------------------------------------
    ON_numData = round(ON_time.*fsamp);
    PCB_MT = PCB_MAT(ON_numData(1):ON_numData(2), cols) .* cons;
    Time_array_ON = Time_array_PCB(ON_numData(1):ON_numData(2));
    for iii = 1:numChannels
        switch DetrendCase
            case 'Basic'
                x = detrend(PCB_MT(:,iii), 1);   % default
                % x = detrend(PCB_MT(:,iii), 'constant'); % remove only DC offset
            case 'CurveBias'
                t = (1:length(PCB_MT(:,iii)))';
                p = polyfit(t, PCB_MT(:,iii), 2);  % quadratic trend
                x = PCB_MT(:,iii) - polyval(p, t);
            case'HighPass'
                [b,a] = butter(3, 0.01, 'high');     % 3rd-order, 1% of Nyquist
                x = filtfilt(b, a, PCB_MT(:,iii));
        end

        %COMPUTE PSD...........................................................
        [Sxx, Freq_Ny_kHz, Freq_Resolution] = Power_Spectral_Density(x, fsamp, nseg, pct_overlap, method, [],FiltAmount);
        switch PlotCase
            case 'PSD'
                plot(Freq_Ny_kHz, Sxx, 'LineWidth', 2, 'DisplayName', sprintf('PCB %d', iii))
            case 'PSD_NoiseSubtracted'
                SavePCB_PSD_Noise_interp = interp1(Freq_Ny_kHz_noise, SavePCB_PSD_Noise(iii,:), Freq_Ny_kHz, 'linear', 'extrap');
                plot(Freq_Ny_kHz, Sxx, 'LineWidth', 2, 'DisplayName', sprintf('PCB %d', iii))
        end
        %......................................................................
    end

    xlabel('$f$ (kHz)','Interpreter','latex');
    ylabel('$S_{xx}(f)$ ([Pa]$^2$/Hz)','Interpreter','latex');


    set(gca, 'Box','on','FontName', 'Times','linewidth',1);
    xlim([0 800]); grid on
    %set(gca, 'TickDir', 'in', 'TickLength', [.01 .01],'XMinorTick', 'on','FontSize', sizethis)
    %set(gca,'Box','on','linewidth',1.9,'fontsize',sizethis);
    set(gca, 'YScale', 'log');
    x0=10; y0=10; width=450*1.25; height=450*1.25; set(gcf,'position',[x0,y0,width,height])
    % De-duplicate legend entries by DisplayName
    h = findobj(gca,'Type','line');
    h = flipud(h);  % put in plotting order
    names = get(h,'DisplayName');
    [~, ia] = unique(names,'stable');
    legend(h(ia), 'Location','northeast');

    %......................................................................

    if exist('saveFig','var') && saveFig == 1
        figTitle = sprintf('PSD_%s_ON_%.3f_%.3f.png', ...
            TestNumber, ON_time(1), ON_time(2));

        exportgraphics(gcf, fullfile(saveFolder,figTitle), ...
            'Resolution', 400);   % 300–600 typical
    end


end









