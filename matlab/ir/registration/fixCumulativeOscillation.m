function IR_fixed = fixCumulativeOscillation(Frames,xs,ys,smoothfilt)

[Nr,Nc,Nf] = size(Frames);
IR_fixed = zeros(Nr,Nc,Nf,'single');

xs = smoothdata(xs,'gaussian',smoothfilt);
ys = smoothdata(ys,'gaussian',smoothfilt);

disp('Running Slow Varying Registration')
for i = 1:Nf
    IR_fixed(:,:,i) = imtranslate(Frames(:,:,i),[-xs(i) -ys(i)], ...
        'linear','FillValues',0);
    if mod(i,50)==0
        disp(['Iteration ', num2str(i)]);
    end
end