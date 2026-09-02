function [Reinfty,rho_infty,a,T_infty,u_infty] = ReCalc(P0,T0,M)
    % Inputs:
    %   P0 - stagnation pressure [Pa], scalar or vector
    %   T0 - stagnation temperature [K], scalar or vector (same length as P0 or scalar)
    %   M  - freestream Mach number, scalar

    gamma = 1.4; 
    R = 287.058; 

    % Make T0 broadcastable: if scalar, expand to match size of P0
    if isscalar(T0)
        T0 = T0 * ones(size(P0));
    end

    % Stagnation density
    rho0 = P0 ./ (R .* T0);

    % Isentropic relations
    T_infty = T0 ./ (1 + (gamma-1)/2 .* M.^2); 
    rho_infty = rho0 ./ (1 + (gamma-1)/2 .* M.^2).^(1/(gamma-1));

    % Velocity
    a = sqrt(gamma .* R .* T_infty); 
    u_infty = M .* a;


    % Viscosity (Sutherland's law)
    muref = 1.716e-5;     % Pa·s
    Tref  = 273.15;       % K
    S     = 110.4;        % K
    mu = muref .* (T_infty./Tref).^(3/2) .* ((Tref+S) ./ (T_infty+S));

    % Freestream unit Reynolds (per meter, scaled to millions)
    Reinfty = rho_infty .* u_infty ./ mu ./ 1e6;
end