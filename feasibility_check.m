% This file checks the feasibility of each (flux, day, recovery) combination:
%   1. Driving force: delta_P must exceed the brine osmotic pressure at the
%      vessel outlet, otherwise the last elements produce no permeate.
%   2. Element pressure: delta_P must stay below the element rating.

%% Load saved data
load('delta_P_avg.mat', 'delta_P_avg', 'J_w', 'recovery', 'dates');
load('osmotic_pressure_recovery.mat', 'osmotic_pressure_C_brine');

P_max = 83;            % Max element operating pressure [bar] (SW30HRLE-440, confirm on datasheet)

nJ = length(J_w);
nD = length(dates);
nR = length(recovery);

%% Reshape brine osmotic pressure to match delta_P_avg
% osmotic_pressure_C_brine is [recovery x day]; delta_P_avg is [flux x day x recovery]
pi_brine = permute(osmotic_pressure_C_brine, [3 2 1]);   % [1 x 366 x 31]

%% Feasibility checks
driving_ok  = delta_P_avg > pi_brine;    % [flux x day x recovery] logical
pressure_ok = delta_P_avg < P_max;       % [flux x day x recovery] logical
dP_feasible = driving_ok & pressure_ok;  % both conditions must hold

%% Minimum viable flux at each recovery (feasible on every day of the year)
J_min = nan(1, nR);                      % [LMH]
for k = 1:nR
    ok_all_days = all(driving_ok(:, :, k), 2);   % true where flux works on all 366 days
    idx = find(ok_all_days, 1, 'first');
    if ~isempty(idx)
        J_min(k) = J_w(idx);
    end
end

%% Maximum viable flux at each recovery (below the pressure limit on every day)
J_max_feasible = nan(1, nR);             % [LMH]
for k = 1:nR
    ok_all_days = all(pressure_ok(:, :, k), 2);
    idx = find(ok_all_days, 1, 'last');
    if ~isempty(idx)
        J_max_feasible(k) = J_w(idx);
    end
end

%% Report
fprintf('Recovery [%%]   J_min [LMH]   J_max [LMH]\n');
for k = 1:nR
    fprintf('    %2d            %5.1f         %5.1f\n', ...
            recovery(k), J_min(k), J_max_feasible(k));
end

save('feasibility_checks.mat', 'driving_ok', 'pressure_ok', 'dP_feasible', ...
     'J_min', 'J_max_feasible', 'J_w', 'recovery', 'dates', 'P_max');

%% Plot the feasible flux window against recovery
figure;
hold on; box on; grid on;
fill([recovery, fliplr(recovery)], [J_min, fliplr(J_max_feasible)], ...
     [0.3 0.6 0.9], 'FaceAlpha', 0.25, 'EdgeColor', 'none');
plot(recovery, J_min, 'b-', 'LineWidth', 1.5);
plot(recovery, J_max_feasible, 'r-', 'LineWidth', 1.5);
xlabel('Recovery [%]', 'FontSize', 12);
ylabel('Water flux [LMH]', 'FontSize', 12);
legend('Feasible window', 'Minimum flux (driving force)', ...
       'Maximum flux (element pressure)', 'Location', 'best');
hold off;