%% This code is used to find ouut J_s based on 366 values of Salinity
%% This is indepdent of water temperature and water flux.

load('salinity_and_temp_mean.mat', 'S_daily_mean');
load('membrane_params.mat', 'B', 'B_LMH');
dates = datetime(2025, 7, 31) : datetime(2026, 7, 31);

S_daily_mean_mgL = S_daily_mean*1027;       % Salinity [mg/L]
J_s = B_LMH*S_daily_mean_mgL;               % Salt flux [mg/m2.h]

save('J_s_finder.mat', 'J_s', 'dates');
