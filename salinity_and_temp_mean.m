%% Load saved data
load('temperature_surface.mat');   % brings in T_surf (8×12×366) and dates
load('salinity_surface.mat');      % brings in S_surf (8×12×366) and dates_sal

%% Daily spatial mean (omit NaNs over land)
T_daily_mean = mean(reshape(T_surf, 96, 366), 1, 'omitnan');
S_daily_mean = mean(reshape(S_surf, 96, 366), 1, 'omitnan');

%% Fixed date range: 31 July 2025 to 31 July 2026 (366 daily points)
dates = datetime(2025, 7, 31) : datetime(2026, 7, 31);

%% Plot (rest unchanged)
figure;
yyaxis left
plot(dates, T_daily_mean, 'b-', 'LineWidth', 1.5);
ylabel('Temperature (°C)');

yyaxis right
plot(dates, S_daily_mean, 'r-', 'LineWidth', 1.5);
ylabel('Salinity (psu)');

xlabel('Date');
legend('Temperature', 'Salinity', 'Location', 'best');
grid on;