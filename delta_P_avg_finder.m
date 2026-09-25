
%% Load saved data
load('salinity_and_temp_mean.mat', 'T_daily_mean', 'dates');
load('osmotic_pressure_recovery.mat', 'osmotic_pressure_C_avg', 'recovery');
load('A_temp_data.mat', 'A_block');

%% Water flux range
J_w = 0:0.1:30;                 % Water flux range [LMH]

nR = length(recovery);          % Number of recovery values
nD = length(T_daily_mean);      % Number of days
nJ = length(J_w);               % Number of flux values

%% Preallocate
delta_P_avg = zeros(nJ, nD, nR);   % Required pressure [bar]

%% Required pressure using the average concentration
for iJ = 1:nJ
    J_w_i = J_w(iJ);
    for j = 1:nD
        temp_T = T_daily_mean(j);
        A_temp = interp1(A_block(1, :), A_block(2, :), temp_T);   % A at this temperature [LMH/bar]
        for k = 1:nR
            delta_P_avg(iJ, j, k) = (J_w_i / A_temp) + osmotic_pressure_C_avg(k, j);   % [bar]
        end
    end
end

save('delta_P_avg.mat', 'delta_P_avg', 'J_w', 'recovery', 'dates');