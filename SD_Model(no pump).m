%This section only contains SD Model with no pump

i = 2;                          % NaCl fracction
R = 8.314;                      % Gas constant [J/mol.K]
T_c = 25;                       % Temp [C]
T = T_c + 273.15;               % Temp [K]
C_f_gL = 35;                    % Feed Salinity [g/L]
Mw = 58.44;                     % Molecular weight
C_f = C_f_gL/Mw;                % Feed Salinity [mol/L]



delta_pi = i*R*T*C_f            % Osmotic Pressure [J/L] or [kPa]
delta_pi_bar = delta_pi/100;    % Osmotic Pressure [bar]

% A = (D_w*K_w*V_w*c_w)/(l*R*T)
% In above once at x=0 and once x=l calculation are carried

V_w = 18;                       % Partial molar volume of water [cm3/mol]
c_w = [0,0];                    % Water concentration in the membrane (at feed, after membrane)
l = 100;                        % Membrane thickness [nm]

% Data sheet data (DuPont FilmTec SW30HRLE-440)
