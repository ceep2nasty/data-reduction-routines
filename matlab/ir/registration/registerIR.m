function [IR_Mapped,x_shift,y_shift] = registerIR(Frames,method, precision,Method_Cumulative)
% method = 'original' or 'cumulative'
[Nr,Nc,Nf] = size(Frames);
IR_Mapped = zeros(Nr,Nc,Nf,'single');
x_shift = zeros(1,Nf);
y_shift = zeros(1,Nf);

ref = Frames(:,:,1);
IR_Mapped(:,:,1) = ref;

switch lower(method)
    case 'original'
        disp('Running original Registration')
        for i = 2:Nf
            moving = Frames(:,:,i);
            [out,fft_shift] = dftregistration(fft2(ref),fft2(moving),precision);
            x_shift(i)=out(4);
            y_shift(i)=out(3);
            IR_Mapped(:,:,i) = abs(ifft2(fft_shift));
            if mod(i,50)==0
                disp(['Iteration ', num2str(i)]);
            end
        end

    case 'cumulative'
        disp('Running Cumulative Registration')
        for i = 2:Nf
            [IR_Mapped(:,:,i), ref, x_shift(i), y_shift(i)] = ...
                cumulativeEnhancement(Frames, i, ref, x_shift, y_shift, Method_Cumulative, precision);
            if mod(i,50)==0
                disp(['Iteration ', num2str(i)]);
            end
        end
    otherwise
        error('Unknown registration method. Use ''original'' or ''cumulative''.');
end
end