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
Rejection = 99.8;               % Salt rejection [%] R_salt = (1 - C_p/C_f)*100 
delta_P = 55;                   % Applied feed pressure [bar]
Recovery = 8;                   % Recovery [%] (test condition, not used below)

% User input data
Mw = 58.44;                     % Molecular weight [g/mol]

% Automated conversions
T = T_c + 273.15;               % Temp [K]
C_f_gL = ppm/1000;              % Feed Salinity [g/L]
C_f = (C_f_gL/Mw)*1000;         % Feed Salinity [mol/m3]

% Constant values
R = 8.314;                      % Gas constant [J/mol.K]

% Salt rejection calculation
C_p_gL = C_f_gL*(1 - Rejection/100);  % Permeate concentration [g/L]

deltac_c = C_f_gL - C_p_gL;           % Concentration difference [g/L] = [kg/m3]

% Formula for osmotic pressure calculation
delta_pi = i*R*T*C_f;                 % Osmotic pressure [Pa]
delta_pi_bar = delta_pi/1e5;          % Osmotic pressure [bar]

% Formula for flux calculation
J_w = (Q_p/A_mem);                    % Water flux [m/d]
J_s = J_w*C_p_gL;                     % Salt flux [kg/m2.d]

% Formula for water permeability calculation
A = J_w/(delta_P - delta_pi_bar);     % Water permeability [m/d.bar]
B = J_s/deltac_c;                     % Salt permeability [m/d]

% Sanity check against literature values (typical SWRO: A ~ 1.1, B ~ 0.06)
A_LMH = A*1000/24;                    % Water permeability [LMH/bar]
B_LMH = B*1000/24;                    % Salt permeability [LMH]

save('membrane_params.mat', 'A', 'B', 'A_LMH','B_LMH');