%% Load saved data
load('temperature_surface.mat');   % brings in T_surf (8×12×366) and dates
load('salinity_surface.mat');      % brings in S_surf (8×12×366) and dates_sal

%% Daily spatial mean (omit NaNs over land)
T_daily_mean = mean(reshape(T_surf, 96, 366), 1, 'omitnan');
S_daily_mean = mean(reshape(S_surf, 96, 366), 1, 'omitnan');

%% Plot
figure;
yyaxis left
plot(dates, T_daily_mean, 'b-', 'LineWidth', 1.5);
ylabel('Temperature (°C)');

yyaxis right
plot(dates_sal, S_daily_mean, 'r-', 'LineWidth', 1.5);
ylabel('Salinity (psu)');

xlabel('Date');
legend('Temperature', 'Salinity', 'Location', 'best');
grid on;