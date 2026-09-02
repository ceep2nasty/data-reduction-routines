function IR_clean = removeOscillation(IR_fixed, tempWindow, spatialSigma)
% IR_FIXED: registered frames (Nr x Nc x Nf)
% TEMPWINDOW: temporal smoothing window (frames), e.g., 5
% SPATIALSIGMA: optional spatial smoothing (pixels), e.g., 0.5
% returns IR_CLEAN: stabilized, smoothed frames

if nargin<2, tempWindow=5; end
if nargin<3, spatialSigma=0; end

[Nr,Nc,Nf] = size(IR_fixed);
IR_clean = zeros(Nr,Nc,Nf,'single');

% Temporal smoothing
disp('Running Temporal Smoothing')
for i = 1:Nr
    for j = 1:Nc
        IR_clean(i,j,:) = smoothdata(squeeze(IR_fixed(i,j,:)),'gaussian',tempWindow);
    end
    if mod(i,50)==0
        disp(['Iteration ', num2str(i)]);
    end
end

% Optional spatial smoothing
if spatialSigma>0
    disp('Running Spatial Filter')
    for k = 1:Nf
        IR_clean(:,:,k) = imgaussfilt(IR_clean(:,:,k),spatialSigma);
    end
    if mod(k,50)==0
        disp(['Iteration ', num2str(k)]);
    end
end
end