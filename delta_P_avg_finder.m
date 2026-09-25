% This file finds the osmotic pressure at the brine and average concentrations,
% and the required pressure difference based on the average concentration.
% C_brine and C_avg are in PSU (from the recovery block).

R = 8.314;                      % Gas constant [J/mol.K]
i = 2;                          % NaCl fraction

%% Load saved data
load('salinity_and_temp_mean.mat', 'T_daily_mean', 'dates');
load('C_brine_avg.mat', 'C_brine', 'C_avg', 'recovery');   % [31 x 366] PSU, recovery [%]
load('A_temp_data.mat', 'A_block');

%% Water flux range
J_w = 0:0.1:30;                 % Water flux range [LMH]

nR = length(recovery);          % 31 recovery values
nD = 366;                       % 366 days
nJ = length(J_w);               % flux values

%% Preallocate
delta_pi_brine     = zeros(nR, nD);   % Osmotic pressure at brine concentration [bar]
delta_pi_avg       = zeros(nR, nD);   % Osmotic pressure at average concentration [bar]
delta_P_avg        = zeros(nJ, nD, nR);  % Required pressure [bar]

%% Osmotic pressure at brine and average concentration
for k = 1:nR
    for j = 1:nD
        T_c = T_daily_mean(j);                          % Temp [C]

        % Brine concentration
        C_salt_gL = C_brine(k, j)*1.027;                % Brine salinity [g/L]
        C_salt    = (C_salt_gL/58.44)*1000;             % Brine salinity [mol/m3]
        delta_pi_brine(k, j) = i*R*(T_c + 273.15)*C_salt / 1e5;   % [bar]

        % Average concentration
        C_salt_gL = C_avg(k, j)*1.027;                  % Average salinity [g/L]
        C_salt    = (C_salt_gL/58.44)*1000;             % Average salinity [mol/m3]
        delta_pi_avg(k, j) = i*R*(T_c + 273.15)*C_salt / 1e5;     % [bar]
    end
end

save('osmotic_pressure_brine_avg.mat', 'delta_pi_brine', 'delta_pi_avg', ...
     'recovery', 'dates');

%% Required pressure using the average concentration
for iJ = 1:nJ
    J_w_i = J_w(iJ);
    for j = 1:nD
        temp_T = T_daily_mean(j);
        A_temp = interp1(A_block(1, :), A_block(2, :), temp_T);   % A at this temperature
        for k = 1:nR
            delta_P_avg(iJ, j, k) = (J_w_i / A_temp) + delta_pi_avg(k, j);   % [bar]
        end
    end
end

save('delta_P_avg.mat', 'delta_P_avg', 'J_w', 'recovery', 'dates');