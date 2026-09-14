%% This code is used to find ouut J_s based on 366 values of Salinity
%% This is indepdent of water temperature and water flux.

load('salinity_and_temp_mean.mat', 'S_daily_mean');
load('membrane_params.mat', 'B', 'B_LMH');
dates = datetime(2025, 7, 31) : datetime(2026, 7, 31);