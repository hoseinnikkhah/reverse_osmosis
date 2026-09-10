load('osmotic_pressure.mat', 'delta_pi_bar');
load('salinity_and_temp_mean.mat', 'T_daily_mean', 'S_daily_mean', 'dates');
load('A_temp_data.mat', 'A_block');

%% Creating a water flux range for the STPi values
J_w = 12:0.01:30;  % Water flux range [LMH]

%% Creating a data block for the STPi values
%% S = Salinity, T = Temperature, Pi = Osmotic Pressure
STPi = [S_daily_mean; T_daily_mean; delta_pi_bar; A_block(2, :)];

%% Create a delta_P block for the STPi values
delta_P = zeros(length(J_w), 366);

for i = 1:length(J_w)
    for j = 1:366
        temp_T = T_daily_mean(j);
        temp_pi = delta_pi_bar(j);
        col = find(A_block(1, :) == temp_T);
        A_temp = A_block(2, col);
        delta_P(i, j) = (J_w(i)/A_temp) + temp_pi;
    end
end
