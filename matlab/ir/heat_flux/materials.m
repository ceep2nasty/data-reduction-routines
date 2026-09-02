% Thomas Juliano
% 10-11-12
% materials.m translated from qcalc96.for
% called by qcalc.m
% provides material properties

function [cp, k, rho] = materials(materialID)

if materialID == 1 % 17-4PH
    CP=.11;
    XK=2.39E-4 * 12.;
    RHO=489.;
elseif materialID == 2 % CHROMEL-P
    CP=.107;
    %        XK=2.42E-4 * 12.;
    XK=2.017E-4 * 12.;
    RHO=544.;
elseif materialID == 3 % Copper
    CP=.095;
    XK=5.07E-3 * 12.;
    RHO=.322 * 144. * 12.;
elseif materialID == 4 % Aluminum (seems to be 2024-T6)
    CP=.209; % 874.9893 J/kg/K
    XK=0.0284; % 176.9404 W/m/K
    RHO=172.93; % 2770 kg/m**3
elseif materialID == 5 % Adamczak Aluminum
    CP=0.248;
%     CP=0.2300;
    XK = 0.023;
%     XK = 0.0213954;
	RHO = 168.56;
elseif materialID == 6 % (6) AISI 1045 Steel
    CP=0.12171;
	XK = 0.0064202;
	RHO = 490.06;
elseif materialID == 304 % AISI 304 stainless steel from Incropera DeWitt Table A.1
    cp = 477; % (J/kg/K)
	k = 14.9; % (W/m/K)
	rho = 7900; % (kg/m^3)
elseif materialID == 6061 % Aluminum 6061-T6 (asm.matweb.com)
    cp = 896; % (J/kg/K)
	k = 167; % (W/m/K)
	rho = 2700; % (kg/m^3)
elseif strcmp(materialID, 'PEEK') % Unfilled PEEK plastic (MakeItFrom.com)
    cp = 1026; % (J/kg/K)
	k = 0.29; % (W/m/K)
	rho = 1.3e3; % (kg/m^3)
elseif strcmp(materialID, '1080_wrap') % 3M 1080 Wrap-Film experimentally measured
    cp = 2076; % (J/kg/K)
	k = 0.23; % (W/m/K)
	rho = 1240; % (kg/m^3) 
elseif strcmp(materialID, 'ClearV4')
    cp = 1000;%2880; % (J/kg/K)
    k = 0.283; % (W/m/K)
    rho = 1140; % (kg/m^3)
end

if not(exist('cp', 'var'))
    cp = CP * 4186.552; % (J/kg/K) specific heat capacity
    k = XK * 6230.296; % (W/m/K) thermal conductivity
    rho = RHO * 16.01845; % (kg/m^3) density
end