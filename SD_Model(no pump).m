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

A_mem = 41;                     % Active area [m2] A_mem
Q_p = 30.2;                     % Permeate flow rate [m3/d]
R_salt = 99.8;                  % Salt rejection [%] R_salt = 1 - (C_p/C_f)*100 
delta_P = 55;                   % Pressure drop across the membrane [bar]
Recovery = 8;                   % Recovery [%]

% User input data
Mw = 58.44;                     % Molecular weight

% Automated conversions
T = T_c + 273.15;               % Temp [K]
C_f_gL = ppm/1000;              % Feed Salinity [g/L]
C_f = C_f_gL/Mw;                % Feed Salinity [mol/L]

% Constant values
R = 8.314;                      % Gas constant [J/mol.K]

% Formula for osmotic pressure calculation
delta_pi = i*R*T*C_f;           % Osmotic pressure [Pa]

% Formula for water flux calculation
J_w = (Q_p/A_mem);              % Water flux [m3/m2.d] or [LMH]

% Formula for water permeability calculation
A = J_w/(delta_P - delta_pi);   % Water permeability [m3/m2.d.bar] or [LMH/bar]