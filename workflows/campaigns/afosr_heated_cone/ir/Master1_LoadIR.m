close all; clear all; clc; restoredefaultpath;

%Working directory
MainDir = 'C:\Users\coled\Notre Dame\Github\Peters-Lab-PC\AFOSR_HeatedCone\IR_Reduction_Routines';
cd(MainDir); cd ..; addpath(genpath('IR_Reduction_Routines'))
%Load IR data directory path
IRDir = "C:\Users\coled\Notre Dame\Peters_Local_Lab_Work\AFOSR_Heated_Cone_Feb2026\";
IRFolder = "Iso_90psi";
LoadDir = IRDir;

frame_rate = 355;   % (Hz) camera's frame rate
total_frames = 500; % total number of frames
num_rows = 512; % row camera resolution
num_columns = 640;  % column camera resolution

%% 2) Load IR data
close all;clc; cd(MainDir)
%--------------------------------------------------------------------------

%SUBROUTINE:.............................................
Frames = loadIRasc(IRDir,IRFolder,total_frames);
%........................................................

FrameView = 440;
figure; surf(Frames(:,:,FrameView)); view(2); shading interp; axis equal tight
colormap(turbo);colorbar

%% 3) COMPUTE: Register Images (Resolve shaking)
close all;clc; cd(MainDir)
%--------------------------------------------------------------------------
RegisterFrames = 'Yes';

clear IR_Mapped
switch RegisterFrames
    case 'Yes'
%SUBROUTINE: cumulative registration.......................................
method = 'original'; precision = 20; %1/precision-th of a pixel
Method_Cumulative = 'none'; % Options: [none, smoothedshifts rollingref masked]
[IR_Mapped,x_shift,y_shift] = registerIR(Frames,method,precision,Method_Cumulative);
%..........................................................................
    case 'No'
        IR_Mapped = Frames;
end
IR_Mapped = permute(IR_Mapped,[2 1 3]);

%% Check Registration
close all;clc; cd(MainDir)
%--------------------------------------------------------------------------
WantMovie = 1;
if WantMovie == 1
    figure;
    colormap(turbo);colorbar
    for i = 100:total_frames
        surf(IR_Mapped(:,:,i)); view(2); shading interp; axis equal tight
        title(num2str(i)); colorbar
        drawnow
    end
end
%If memory problems uncomment so you delete the variable 'Frames'
% clear Frames

%% 12 mm fisheye distortion correction
close all;clc; cd(MainDir)
%--------------------------------------------------------------------------

%SUBROUTINE: distortion correction.......................................
load('CalibrationInstance2');
Data_Distort_Corrected = undistortImageStack(IR_Mapped, cameraParams);
%..........................................................................

FrameView = 1;
figure; surf(Data_Distort_Corrected(:,:,FrameView)-IR_Mapped(:,:,FrameView)); view(2); shading interp; axis equal tight
colormap(turbo);colorbar

%Check results
figure; surf(Data_Distort_Corrected(:,:,FrameView)-IR_Mapped(:,:,FrameView)); view(2); shading interp; axis equal tight
colormap(turbo);colorbar

figure; tiledlayout('flow')
nexttile;
surf(IR_Mapped(:,:,FrameView)); view(2); shading interp; axis equal tight
colormap(turbo);colorbar; title('distorted')

nexttile
surf(Data_Distort_Corrected(:,:,FrameView)); view(2); shading interp; axis equal tight
colormap(turbo);colorbar; title('corrected')

Data_Distort_Corrected = permute(Data_Distort_Corrected,[2 1 3]);

%%

FrameView = 1;
figure; surf(Data_Distort_Corrected(:,:,FrameView)); view(2); shading interp; axis equal tight
colormap(gray);colorbar

% shake correction off iso 2mm
% tic
% 
% for i = 1:size(allh2_2_corrected,3)-1
%     offallh2_2 = allh2_2_corrected(:,:,i);
%     onallh2_2 = jump2_2_corrected(:,:,i+1);
%     precision = 1000; % 1/100 pixel precision
%     [output, fft_on_shift] = dftregistration(fft2(offallh2_2),fft2(onallh2_2),precision);
%     x_shift(i)=output(4);
%     y_shift(i)=output(3);
% 
%     shiftallh2_2(:,:,i) = abs(ifft2(fft_on_shift)); %this is the shifted wind-on image
%     if mod(i, 50) == 0
%         disp(['Iteration ', num2str(i)]);
%     end
% end
% 
% toc