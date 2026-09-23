load('salinity_and_temp_mean.mat')
recovery = 30:1:60;                                                     % Recovery range [%]
C_brine = zeros(length(recovery), length(S_daily_mean));                % Preallocate brine concentration array [PSU]
C_avg = zeros(length(recovery), length(S_daily_mean));                  % Preallocate average brine concentration array [PSU]
osmotic_pressure_new = zeros(length(recovery), length(S_daily_mean));   % Preallocate osmotic pressure array [bar]

for i = 1:length(recovery)
    for j = 1:length(S_daily_mean)
        C_brine(i, j) = S_daily_mean(j) / (1 - recovery(i)/100);        % Calculate brine concentration [PSU]
    end
end

for i = 1:length(recovery)
    for j = 1:length(S_daily_mean)
        C_avg(i, j) = (S_daily_mean(j) + C_brine(i, j)) / 2;            % Calculate average brine concentration [PSU]
    end
end

for i = 1:length(recovery)
    for j = 1:length(S_daily_mean)
        T_c = T_daily_mean(j);                       % Temp [C]
        C_salt_gL = C_avg(i, j)*1.027;               % Average brine salinity [g/L]
        C_salt = (C_salt_gL/58.44)*1000;             % Average brine salinity [mol/m3]

        osmotic_pressure_new(i, j) = i*R*(T_c + 273.15)*C_salt;     % Osmotic pressure [Pa]
        osmotic_pressure_new(i, j) = osmotic_pressure_new(i, j)/1e5; % Osmotic pressure [bar]
    end
end