%% Reference design case (one plant, for building the pump layer)
D = load('design_data.mat');
O = load('osmotic_pressure_recovery.mat');
A = load('A_temp_data.mat');
S = load('salinity_and_temp_mean.mat', 'T_daily_mean', 'dates');

k_ref  = 4;                                      % conventional pretreatment
n_ref  = 7;                                      % elements per vessel
Nv_ref = 10;                                     % vessels
R_ref  = 0.35;                                   % recovery set point

iE = find(D.N_elements == n_ref);
iV = find(D.N_vessels  == Nv_ref);
iR = find(O.recovery   == R_ref*100);

A_mem = D.total_A(iE, iV);                       % 2870 m2
pi_avg = O.osmotic_pressure_C_avg(iR, :);        % [1 x 366] bar
pi_b   = O.osmotic_pressure_C_brine(iR, :);      % [1 x 366] bar
A_T    = interp1(A.A_block(1,:), A.A_block(2,:), S.T_daily_mean);   % [1 x 366] LMH/bar