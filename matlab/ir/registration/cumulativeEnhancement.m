function [IR_new, ref_new, x_shift_out, y_shift_out] = cumulativeEnhancement(Frames, i, ref, x_shift, y_shift, method, precision, mask)
% Frames      : full frame stack
% i           : current frame index
% ref         : current reference frame
% x_shift,y_shift : cumulative shifts
% method      : 'none','smoothedShifts','rollingRef','masked'
% precision   : DFT registration precision
% mask        : logical mask (for 'masked' option)
% IR_new     : registered frame
% ref_new    : updated reference frame
% x_shift_out,y_shift_out : updated shifts

moving = Frames(:,:,i);
[out,fft_shift] = dftregistration(fft2(ref), fft2(moving), precision);
dx = out(4); dy = out(3);

switch lower(method)
    case 'none'
        % Original cumulative: simply registers the frame against ref
        % without any smoothing or enhancements.        
        x_shift_out = dx;
        y_shift_out = dy;
        IR_new = abs(ifft2(fft_shift));
        ref_new = IR_new;
        
    case 'smoothedshifts'
        % Smooths cumulative shifts using exponential moving average
        % Reduces frame-to-frame jitter while still updating reference each frame
        x_shift_out = dx; y_shift_out = dy;
        alpha = 0.1; % smoothing factor
        if i>2
            x_shift_out = alpha*dx + (1-alpha)*x_shift(i-1);
            y_shift_out = alpha*dy + (1-alpha)*y_shift(i-1);
        end
        IR_new = imtranslate(Frames(:,:,i), [-x_shift_out -y_shift_out],'linear','FillValues',0);
        ref_new = IR_new;
        
    case 'rollingref'
        % Uses a rolling mean of previous frames as reference instead of
        % the last frame. Reduces oscillation caused by tiny variations in last frame.
        x_shift_out = dx; y_shift_out = dy;
        nRef = 3;
        if i>nRef
            ref_new = mean(Frames(:,:,i-nRef:i-1),3);
        else
            ref_new = ref;
        end
        IR_new = imtranslate(Frames(:,:,i), [-x_shift_out -y_shift_out],'linear','FillValues',0);
        
    case 'masked'
        % Registers only the pixels inside a provided mask.
        % Ignores irrelevant background to prevent drift caused by intensity changes.
        if nargin<8 || isempty(mask)
            mask = true(size(ref));
        end
        refMasked = ref; refMasked(~mask)=0;
        movingMasked = moving; movingMasked(~mask)=0;
        [out,~] = dftregistration(fft2(refMasked), fft2(movingMasked), precision);
        dx = out(4); dy = out(3);
        x_shift_out = dx; y_shift_out = dy;
        IR_new = imtranslate(Frames(:,:,i), [-dx -dy],'linear','FillValues',0);
        ref_new = IR_new;
        
    otherwise
        error('Unknown enhancement method');
end
end