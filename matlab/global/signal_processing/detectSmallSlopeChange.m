function idx = detectSmallSlopeChange(x,y,p)
    x = x(:); y = y(:);                % enforce column vectors
    dy_raw = gradient(y)./gradient(x);

    cands = 3:50;
    vars  = zeros(size(cands));

    for k = 1:length(cands)
        dy_s = movmedian(dy_raw, cands(k));     % always same length
        vars(k) = median(abs(diff(dy_s(:))));   % force vector
    end

    [~,best] = min(vars);
    w = cands(best);

    dy = movmedian(dy_raw,w);
    idx = NaN;

    for i = w+1:length(dy)
        s_now  = dy(i);
        s_base = median(abs(dy(i-w:i-1)));
        if s_base < 1e-6, s_base = 1e-6; end
        if abs(s_now - s_base)/s_base < p
            idx = i; return
        end
    end
end