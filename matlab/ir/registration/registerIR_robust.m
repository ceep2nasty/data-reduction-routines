function [IR_Mapped,x_shift,y_shift] = registerIR_robust(Frames,method,precision,Method_Cumulative)
%REGISTERIR_ROBUST Registers frames with cumulative shift removal and optional smoothing
% Inputs:
%   Frames           - 3D matrix (rows x cols x nFrames)
%   method           - 'original' or 'cumulative'
%   precision        - subpixel precision (1/precision of a pixel)
%   Method_Cumulative- 'none','smoothedshifts','rollingref','masked'
% Outputs:
%   IR_Mapped        - Registered frames
%   x_shift, y_shift - computed shifts for each frame

[nr,nc,nf] = size(Frames);
x_shift = zeros(1,nf); y_shift = zeros(1,nf);
IR_Mapped = Frames;

% Reference frame
refFrame = double(Frames(:,:,1));

for k = 2:nf
    curFrame = double(Frames(:,:,k));
    % Compute cross-correlation
    c = normxcorr2(refFrame, curFrame);
    [ypeak,xpeak] = find(c==max(c(:)));
    % Subpixel refinement
    x_shift(k) = (xpeak - size(refFrame,2)) / precision;
    y_shift(k) = (ypeak - size(refFrame,1)) / precision;
    
    % Apply cumulative shift
    if strcmp(method,'cumulative')
        xShiftTot = sum(x_shift(1:k));
        yShiftTot = sum(y_shift(1:k));
    else
        xShiftTot = x_shift(k);
        yShiftTot = y_shift(k);
    end
    IR_Mapped(:,:,k) = imtranslate(curFrame, [xShiftTot yShiftTot], 'linear','FillValues',0);
    
    % Update reference if rolling reference
    if strcmp(Method_Cumulative,'rollingref')
        refFrame = IR_Mapped(:,:,k);
    end

    if mod(k,50)==0
        disp(['Iteration ', num2str(k)]);
    end
end

% Optional smoothing of shifts
switch Method_Cumulative
    case 'smoothedshifts'
        x_shift = smooth(x_shift,5,'rloess');
        y_shift = smooth(y_shift,5,'rloess');
        for k=1:nf
            IR_Mapped(:,:,k) = imtranslate(double(Frames(:,:,k)), [sum(x_shift(1:k)) sum(y_shift(1:k))],'linear','FillValues',0);
            if mod(k,50)==0
                disp(['Iteration ', num2str(k)]);
            end
        end
    case 'masked'
        % Implement masked registration if required
end

% Remove slow drift
smoothfilt = 5;
IR_Mapped = fixCumulativeOscillation(IR_Mapped,x_shift,y_shift,smoothfilt);

% Remove residual high-frequency humming
tempWindow = 5; spatialSigma = 0.5;
IR_Mapped = removeOscillation(IR_Mapped,tempWindow,spatialSigma);

end