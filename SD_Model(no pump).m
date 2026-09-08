%{ 
This code is essential part of the SD model. It calculates the osmotic pressure
and water permeability of the membrane. This is based on commercial data sheet of
DuPont FilmTec SW30HRLE-440. The code is used in the SD model to calculate the 
water flux through the membrane. Based on the water flux, A and B coeffecients
are calculated.
%}

% Note NaCl fraction is 2 for NaCl, 3 for CaCl2 and 4 for MgCl2

% Data driven from the data sheet of DuPont FilmTec SW30HRLE-440
i = 2;                          % NaCl fracction 
T_c = 25;                       % Temp [C]
ppm = 32000;                    % Feed Salinity [ppm]

% User input data
Mw = 58.44;                     % Molecular weight

% Automated conversions
T = T_c + 273.15;               % Temp [K]
C_f_gL = ppm/1000;              % Feed Salinity [g/L]
C_f = C_f_gL/Mw;                % Feed Salinity [mol/L]

% Constant values
R = 8.314;                      % Gas constant [J/mol.K]

% Formula for osmotic pressure calculation
delta_pi = i*R*T*C_f            % Osmotic Pressure [J/L] or [kPa]
delta_pi_bar = delta_pi/100;    % Osmotic Pressure [bar]


% In above once at x=0 and once x=l calculation are carried

V_w = 18;                       % Partial molar volume of water [cm3/mol]
c_w = [0,0];                    % Water concentration in the membrane (at feed, after membrane)
l = 100;                        % Membrane thickness [nm]

% Data sheet data (DuPont FilmTec SW30HRLE-440)
A_mem = 41;                     % Active area [m2] A_mem
