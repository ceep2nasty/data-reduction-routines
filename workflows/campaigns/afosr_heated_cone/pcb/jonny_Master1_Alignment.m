
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

%Setup up all requierd directory paths.....................................
    %Load in global routines
    TopDir = 'C:\Users\coled\Notre Dame\Github\Peters-Lab-PC\AFOSR_HeatedCone';
    cd(TopDir); addpath(genpath('Global_Routines'));
    
    % Working directory
    MainDir = 'C:\Users\coled\Notre Dame\Github\Peters-Lab-PC\AFOSR_HeatedCone\Measurements\PCB';
    cd(MainDir)
    
    %Data loading directory
    dataTag = '\Feb2026_Alignment' ;
    LoadDataDir = strcat([MainDir,'\Data', dataTag]);
    addpath(LoadDataDir)

    %Figure path save
    Path_SaveFigure_Folder = ['C:\Users\coled\Notre Dame\Github\Peters-Lab-Work\AFOSR_HeatedCone\Measurments\PCB', dataTag, '_figs'];

%..........................................................................

%Run plot preferences
UseFontSizeGloabl = 20; font_interp_fontsize
%Load colormaps


%% LOAD: PCB data
close all; clc; cd(MainDir)
%--------------------------------------------------------------------------
%Choose Test.........
TestNumber ='001';
%....................
% Load file with PCB data
cd(LoadDataDir)
PCB_Struct = importdata(['alignment_feb2026_', '.mat']);
disp('PCB Data loaded successfully')
cd(MainDir)

%% PLOT: Traces
close all; clc; cd(MainDir)
%--------------------------------------------------------------------------p[k

%PCBS: Take out Channels C1, C2, C3, D1, D2, D5, D6, D7, D8
COLUMN_TITLES = Test.textdata(6);
headerStr = COLUMN_TITLES{1,1};

% Channels you want (cell array of char vectors)
ChSelect ={'Ch D01','Ch D02', 'Ch C01', 'Ch D05', 'Ch D08', 'Ch D07','Ch D06'};
colNames = strsplit(headerStr, '\t');
idx = zeros(size(ChSelect));
% Loop
for k = 1:numel(ChSelect)
    hit = find(strcmp(colNames, ChSelect{k}), 1);
    if isempty(hit)
        error('Channel "%s" not found.', ChSelect{k});
    end
    idx(k) = hit;
end

% Extract selected channels into matrix
PCB_MAT = Test.data(:, idx);
% Time vector
Time_array = Test.data(:, 1);

N = size(PCB_MAT,1);    %Number of data points (#)
fsamp = 2*10^6;         %Sample frequency (Hz)
total_time = N/fsamp;    %Total time with pr trigger (s)

%Driver tube calibration
driverp=[51.7 87.8*6.89476 61*6.89476 150*6.89476 14.6*6.89476 93*6.89476].*1000; %(Pa)
driverv=[-8.08 -0.73153 -3.3495 4.8098 -7.4776 -0.5246]; %(V)
driver_FIT = polyfit(driverv,driverp,1);

%Plot PCBs, Stagnation Kulite, Valve opening, 
sizethis = 25;
time_LINE = .72;

figure; tiledlayout('vertical'); 
    nexttile; hold on; grid on
    plot(Time_array,(PCB_MAT(:,1)))
    plot(Time_array,(PCB_MAT(:,2)))
    plot(Time_array,(PCB_MAT(:,3)))
    plot(Time_array,(PCB_MAT(:,4)))
    xline(time_LINE,'r')
    set(gca, 'TickDir', 'out', 'TickLength', [.01 .01],'XMinorTick', 'on','FontSize', sizethis)
    set(gca,'Box','on','linewidth',1.9,'fontsize',sizethis);
    
    nexttile; hold on; grid on
    plot(Time_array,Test.data(:,11))
    plot(Time_array,Test.data(:,12))
    plot(Time_array,Test.data(:,13))
    xline(time_LINE,'r')
    set(gca, 'TickDir', 'out', 'TickLength', [.01 .01],'XMinorTick', 'on','FontSize', sizethis)
    set(gca,'Box','on','linewidth',1.9,'fontsize',sizethis);
    
    nexttile; hold on; grid on
    plot(Time_array,Test.data(:,2).*driver_FIT(1)+driver_FIT(2))
    hold on
    xline(time_LINE,'r')
    set(gca, 'TickDir', 'out', 'TickLength', [.01 .01],'XMinorTick', 'on','FontSize', sizethis)
    set(gca,'Box','on','linewidth',1.9,'fontsize',sizethis);
    x0=10; y0=10; width=800*1.25; height=500*1.25; set(gcf,'position',[x0,y0,width,height])
    xlim([0 0.75])


%% PLOT: PSD
close all; clc; cd(MainDir)
%--------------------------------------------------------------------------

loop = 'loopIt' ;
noClick = 1 ;
switch loop
    case 'loopIt'
        onStart = 0.2 ;
        onEnd = 1 ;
        increment = 0.05 ;
    case 'noLoop'
        onStart = 0.65 ;
        increment = 0.05 ;
        onEnd = onStart+increment ;
end

for i = onStart:increment:(onEnd-increment)
    ON_time = [i i+increment];

    IncludeNoise = 0;
    GetPeaks = 0;
    saveFig = 1;

    %Order the columns
    cols = [1 2 3 4 5 6 7];
    Strings = {'D01 (2)', 'D02 (3)', 'D05 (4)', 'C05 (5)', 'D08 (6)', 'D07 (7)', 'D08 (8)'};

    %Calibration constant
    cons = [1 1 1 1 1 1 1];

    figure; hold on; grid on
    %Plot Noise------------------------------------------------------------------
    clear SavePCB_PSD_Noise\[].
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
    ON_numData = ON_time.*fsamp;
    PCB_MT = PCB_MAT(ON_numData(1):ON_numData(2), cols) .* cons;
    Time_array_ON = Time_array(ON_numData(1):ON_numData(2));
    for iii = 1:length(idx)
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
                plot(Freq_Ny_kHz,(Sxx),'LineWidth',2,'DisplayName',strcat(['PCB ',num2str(iii),' ',Strings{iii}])) ;
            case 'PSD_NoiseSubtracted'
                SavePCB_PSD_Noise_interp = interp1(Freq_Ny_kHz_noise, SavePCB_PSD_Noise(iii,:), Freq_Ny_kHz, 'linear', 'extrap');
                plot(Freq_Ny_kHz,(Sxx-SavePCB_PSD_Noise_interp),'LineWidth',2,'color',colormatrix(iii,:),'DisplayName',strcat(['PCB ',num2str(iii),' ',Strings{iii}]));
        end
        %......................................................................
    end

    xlabel('$f$ (kHz)','Interpreter','latex');
    ylabel('$S_{xx}(f)$ ([Pa]$^2$/Hz)','Interpreter','latex');

    set(gca, 'Box','on','FontName', 'Times','linewidth',1);
    xlim([0 800]); grid on
    set(gca, 'TickDir', 'in', 'TickLength', [.01 .01],'XMinorTick', 'on','FontSize', sizethis)
    set(gca,'Box','on','linewidth',1.9,'fontsize',sizethis);
    set(gca, 'YScale', 'log');
    x0=10; y0=10; width=450*1.25; height=450*1.25; set(gcf,'position',[x0,y0,width,height])
    legend('location','northeast')

    if saveFig
        if ~exist(Path_SaveFigure_Folder, 'dir')
            mkdir(Path_SaveFigure_Folder);
        end
        cd(Path_SaveFigure_Folder);
        fig=gcf;
        figTitle = strcat(dataTag(2:end),'_',num2str(ON_time(1)),'_', num2str(ON_time(2)), '.jpg') ;
        set(fig, 'Units', 'pixels');
        set(fig, 'Position', [100 100 1600 900]);  % width x height in px
        exportgraphics(fig, figTitle, 'Resolution', 300);
    end

    if noClick
        close all
        endvmgjn
    end
end
%....................................
% ..................................





