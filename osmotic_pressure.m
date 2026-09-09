% This file finds osmotic pressure based on founded A at different salinity and temperature values.

R = 8.314;                      % Gas constant [J/mol.K]
i = 2;                          % NaCl fraction

%% Load saved data
load('temperature_surface.mat');   % brings in T_surf (8×12×366) and dates
load('salinity_surface.mat');      % brings in S_surf (8×12×366) and dates_sal

%% Daily spatial mean (omit NaNs over land)
T_daily_mean = mean(reshape(T_surf, 96, 366), 1, 'omitnan');
S_daily_mean = mean(reshape(S_surf, 96, 366), 1, 'omitnan');

%% Fixed date range: 31 July 2025 to 31 July 2026 (366 daily points)
dates = datetime(2025, 7, 31) : datetime(2026, 7, 31);

delta_pi = zeros(1, 366);   % Preallocate osmotic pressure array
delta_pi_bar = zeros(1, 366); % Preallocate osmotic pressure in bar array

for j=1:366
    T_c = T_daily_mean(j);                       % Temp [C]
    C_salt_gL = S_daily_mean(j)*1.027;           % Feed Salinity [g/L]
    C_salt = (C_salt_gL/58.44)*1000;             % Feed Salinity [mol/m3]

    delta_pi(j) = i*R*(T_c + 273.15)*C_salt;     % Osmotic pressure [Pa]
    delta_pi_bar(j) = delta_pi(j)/1e5;           % Osmotic pressure [bar]
end

figure;
plot(dates, delta_pi_bar, 'LineWidth', 1.5);

xlabel('Date', 'FontSize', 12);
ylabel('Osmotic Pressure (bar)', 'FontSize', 12);
legend('Osmotic Pressure', 'Location', 'best');
grid on;