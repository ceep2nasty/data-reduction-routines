function T0_time = computeT0_insentropic(P0_time, P0_initial, T0_initial, gamma)
% compute T0(t) from isentropic relation
if nargin<4, gamma = 1.4; end
expn = (gamma-1)/gamma;
T0_time = T0_initial .* (P0_time./P0_initial).^expn;
end