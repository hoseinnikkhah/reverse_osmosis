%  SYSTEM CURVE — required pressure vs feed flow, for one selected plant
clear; clc;

%  1. Load upstream results

D = load('design_data.mat');                 % config, N_elements, N_vessels, total_A
O = load('osmotic_pressure_recovery.mat');   % osmotic_pressure_C_avg / _C_brine, recovery
Ad = load('A_temp_data.mat');                % A_block = [T_grid; A(T)]
S = load('salinity_and_temp_mean.mat', 'T_daily_mean', 'dates');

dates = S.dates;          % promote from struct so save() can find it

%  2. DESIGN SELECTION
%  Available designs (7 elements/vessel, 14 LMH):
%    Vessels   A_mem(m2)   Q_p(m3/d)   Scale
%        1        287          96      Single vessel      <-- selected
%        5       1435         482      Small
%       10       2870         964      Small
%       25       7175        2411      Small
%       50      14350        4821      Medium
%       94      26978        9065      Medium-to-large
%      120      34440       11572      Medium-to-large
%      150      43050       14465      Grid maximum
% ---------------------------------------------------------------
cfg_name = "Conventional pretreatment";
n_elem   = 7;        % elements per vessel
n_vess   = 1;        % vessels in parallel
R_set    = 0.35;     % recovery set point [-]
J_design = 14;       % nominal design flux [LMH], for the design point

%  3. Resolve indices and pull the plant's parameters
k  = find(D.config.Name == cfg_name);
iE = find(D.N_elements  == n_elem);
iV = find(D.N_vessels   == n_vess);
iR = find(O.recovery    == R_set*100);

assert(~isempty(k)  && ~isempty(iE) && ~isempty(iV) && ~isempty(iR), 'One of the selected values is not present in the stored grids.');

A_mem   = D.total_A(iE, iV);                        % total active area [m2]
J_lo    = min(D.config.J_design{k});                % design flux band, low  [LMH]
J_hi    = max(D.config.J_design{k});                % design flux band, high [LMH]
J_elem  = D.config.J_max(k);                        % max element flux [LMH]
R_ceil  = D.ceil_recovery(iE, k);                   % max vessel recovery [-]

pi_avg  = O.osmotic_pressure_C_avg(iR, :);          % [1 x 366] bar
pi_b    = O.osmotic_pressure_C_brine(iR, :);        % [1 x 366] bar
A_T     = interp1(Ad.A_block(1,:), Ad.A_block(2,:), S.T_daily_mean);   % [1 x 366] LMH/bar

nD = numel(S.T_daily_mean);

assert(~any(isnan(A_T)), 'A(T) contains NaN: a daily temperature falls outside the A_block range.');
assert(R_set <= R_ceil, 'Recovery set point %.0f%% exceeds the vessel ceiling %.1f%%.',R_set*100, R_ceil*100);

%  4. Flux <-> flow conversion for this plant

LMH_to_m3d = 24/1000;
flux2Qf    = @(J) J * A_mem * LMH_to_m3d / R_set;   % [LMH]   -> [m3/d]
Qf2flux    = @(Qf) Qf * R_set * 1000 / (24 * A_mem);% [m3/d]  -> [LMH]

%  5. System curve:  dP(Q_f, day) = pi(C_avg) + J_w / A(T)

J_sweep = (0 : 0.25 : J_elem)';                     % flux sweep [LMH]
Qf      = flux2Qf(J_sweep);                         % [nQ x 1] m3/d
nQ      = numel(Qf);

% [nQ x 366]: rows = feed flow, columns = day
Hsys = pi_avg + (J_sweep ./ A_T);                   % [bar], implicit expansion


%  6. Feasibility of each (flow, day) point

P_max = 83;                                          % element max pressure [bar]

driving_ok  = Hsys > pi_b;                           % [nQ x 366]
pressure_ok = Hsys < P_max;
feasible    = driving_ok & pressure_ok;

% Minimum viable flux per day:  dP = pi(C_b)  =>  J_min = A(T)*(pi_b - pi_avg)
J_min_day = A_T .* (pi_b - pi_avg);                  % [1 x 366] LMH
J_min_yr  = max(J_min_day);                          % worst day
Qf_min_yr = flux2Qf(J_min_yr);                       % [m3/d]

if J_design < J_min_yr
    warning('J_design = %g LMH is below the minimum viable flux (%.1f LMH).', J_design, J_min_yr);
end
if J_design < J_lo || J_design > J_hi
    warning('J_design = %g LMH is outside the %g-%g LMH band for %s.', J_design, J_lo, J_hi, cfg_name);
end

%  7. Design point

Qp_des = J_design * A_mem * LMH_to_m3d;              % permeate   [m3/d]
Qf_des = Qp_des / R_set;                             % feed       [m3/d]
Qb_des = Qf_des - Qp_des;                            % brine      [m3/d]

dP_des      = pi_avg + J_design ./ A_T;              % [1 x 366] bar
dP_des_min  = min(dP_des);
dP_des_max  = max(dP_des);
[~, jHot]   = max(dP_des);
[~, jCold]  = min(dP_des);

Qf_vessel_h = Qf_des / n_vess / 24;                  % per-vessel feed [m3/h]

%  8. Report

fprintf('\n=== PLANT ===\n');
fprintf('  Pretreatment      : %s (%g-%g LMH design, %g LMH max)\n', cfg_name, J_lo, J_hi, J_elem);
fprintf('  Vessels x elements: %d x %d = %d elements\n', n_vess, n_elem, n_vess*n_elem);
fprintf('  Active area       : %.0f m2\n', A_mem);
fprintf('  Recovery set point: %.0f%%  (vessel ceiling %.1f%%)\n', R_set*100, R_ceil*100);

fprintf('\n=== DESIGN POINT (%g LMH) ===\n', J_design);
fprintf('  Permeate   Q_p    : %8.1f m3/d  (%6.2f m3/h)\n', Qp_des, Qp_des/24);
fprintf('  Feed       Q_f    : %8.1f m3/d  (%6.2f m3/h)\n', Qf_des, Qf_des/24);
fprintf('  Brine      Q_b    : %8.1f m3/d  (%6.2f m3/h)\n', Qb_des, Qb_des/24);
fprintf('  Feed per vessel   : %8.2f m3/h  (limit ~16)\n', Qf_vessel_h);

fprintf('\n=== PUMP DUTY ===\n');
fprintf('  Flow at design    : %.2f m3/h\n', Qf_des/24);
fprintf('  Required pressure : %.1f - %.1f bar over the year\n', dP_des_min, dP_des_max);
fprintf('    hardest day     : %s  (%.1f bar)\n', datestr(S.dates(jHot),  'dd mmm'), dP_des_max);
fprintf('    easiest day     : %s  (%.1f bar)\n', datestr(S.dates(jCold), 'dd mmm'), dP_des_min);
fprintf('  Hydraulic power   : %.1f kW at design point\n', Qf_des/24/3600*dP_des_max*1e5/1000);

fprintf('\n=== OPERATING RANGE ===\n');
fprintf('  Min viable flux   : %.1f LMH (worst day) -> Q_f = %.2f m3/h\n', J_min_yr, Qf_min_yr/24);
fprintf('  Design flux band  : %g - %g LMH          -> Q_f = %.2f - %.2f m3/h\n', ...
        J_lo, J_hi, flux2Qf(J_lo)/24, flux2Qf(J_hi)/24);
fprintf('  Turndown below design point: %.0f%%\n', (1 - Qf_min_yr/Qf_des)*100);
if J_min_yr > J_lo
    fprintf('  NOTE: min viable flux exceeds the bottom of the design band.\n');
end

%% ---------------------------------------------------------------
%  9. Plot
% ---------------------------------------------------------------
figure('Name', sprintf('System curve - %d vessel(s)', n_vess));
hold on; box on; grid on;

Qf_h = Qf / 24;                                      % x-axis in m3/h

% design flux band
xb = [flux2Qf(J_lo) flux2Qf(J_hi) flux2Qf(J_hi) flux2Qf(J_lo)]/24;
yb = [0 0 P_max P_max];
hBand = fill(xb, yb, [0.3 0.6 0.9], 'FaceAlpha', 0.15, 'EdgeColor', 'none');

hHot  = plot(Qf_h, Hsys(:, jHot),  'r-', 'LineWidth', 1.6);
hCold = plot(Qf_h, Hsys(:, jCold), 'b-', 'LineWidth', 1.6);
hPiB  = plot(Qf_h, pi_b(jHot)*ones(nQ,1), 'k--', 'LineWidth', 1.2);
hPmax = yline(P_max, 'k-', 'LineWidth', 1.2);
hDes  = plot(Qf_des/24, dP_des_max, 'ko', 'MarkerFaceColor', 'y', 'MarkerSize', 9);

xlabel('Feed flow Q_f [m^3/h]', 'FontSize', 12);
ylabel('Required pressure \DeltaP [bar]', 'FontSize', 12);
title(sprintf('System curve — %d vessel(s) x %d elements, %.0f m^2, R = %.0f%%', ...
      n_vess, n_elem, A_mem, R_set*100));
legend([hHot hCold hPiB hPmax hBand hDes], ...
       {sprintf('Hardest day (%s)', datestr(S.dates(jHot),'dd mmm')), ...
        sprintf('Easiest day (%s)', datestr(S.dates(jCold),'dd mmm')), ...
        '\pi(C_b) — driving-force floor', ...
        'Element pressure limit', ...
        sprintf('Design flux band %g-%g LMH', J_lo, J_hi), ...
        'Design point'}, ...
       'Location', 'northwest');
ylim([0 P_max*1.05]);
hold off;

%% ---------------------------------------------------------------
%  10. Save
% ---------------------------------------------------------------
save('system_curve.mat', 'Hsys', 'Qf', 'J_sweep', 'feasible', ...
     'A_mem', 'R_set', 'n_elem', 'n_vess', 'cfg_name', ...
     'pi_avg', 'pi_b', 'A_T', 'flux2Qf', 'Qf2flux', ...
     'Qp_des', 'Qf_des', 'Qb_des', 'dP_des', 'dP_des_min', 'dP_des_max', ...
     'J_min_day', 'J_min_yr', 'J_lo', 'J_hi', 'J_elem', 'P_max', 'dates');