load('salinity_and_temp_mean.mat')
recovery = 30:1:60;                                               % Recovery range [%]
C_brine = zeros(length(recovery), length(S_daily_mean));          % Preallocate brine concentration array
C_avg = zeros(length(recovery), length(S_daily_mean));            % Preallocate average brine concentration array

for i = 1:length(recovery)
    for j = 1:length(S_daily_mean)
        C_brine(i, j) = S_daily_mean(j) / (1 - recovery(i)/100);  % Calculate brine concentration
    end
end

for i = 1:length(recovery)
    for j = 1:length(S_daily_mean)
        C_avg(i, j) = (S_daily_mean(j) + C_brine(i, j)) / 2;      % Calculate average brine concentration
    end
end