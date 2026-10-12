function out = systemCurve(n_elem, n_vess, R_set, J_design, cfg_name, show)
% SYSTEMCURVE  Required pressure vs feed flow for one RO plant, over a full year.
%
%   out = systemCurve(n_elem, n_vess)
%   out = systemCurve(n_elem, n_vess, R_set, J_design, cfg_name, show)
%
%   n_elem    elements per vessel (5, 6 or 7)
%   n_vess    vessels in parallel
%   R_set     recovery set point [-]        default 0.35
%   J_design  nominal design flux [LMH]     default 14
%   cfg_name  pretreatment configuration    default "Conventional pretreatment"
%   show      print report and plot         default false
%
%   Returns a struct with the system curve, feasibility masks, design point
%   and pump duty.

    if nargin < 3 || isempty(R_set),    R_set    = 0.35; end
    if nargin < 4 || isempty(J_design), J_design = 14;   end
    if nargin < 5 || isempty(cfg_name), cfg_name = "Conventional pretreatment"; end
    if nargin < 6 || isempty(show),     show     = false; end

    %% 1. Load upstream results (cached across calls)
    persistent D O Ad S
    if isempty(D)
        D  = load('design_data.mat');
        O  = load('osmotic_pressure_recovery.mat');
        Ad = load('A_temp_data.mat');
        S  = load('salinity_and_temp_mean.mat', 'T_daily_mean', 'dates');
    end
    dates = S.dates;

    %% 2. Resolve indices and pull the plant's parameters
    k  = find(D.config.Name == cfg_name);
    iE = find(D.N_elements  == n_elem);
    iV = find(D.N_vessels   == n_vess);
    iR = find(O.recovery    == R_set*100);

    assert(~isempty(k) && ~isempty(iE) && ~isempty(iV) && ~isempty(iR), ...
           'One of the selected values is not present in the stored grids.');

    A_mem  = D.total_A(iE, iV);
    J_lo   = min(D.config.J_design{k});
    J_hi   = max(D.config.J_design{k});
    J_elem = D.config.J_max(k);
    R_ceil = D.ceil_recovery(iE, k);

    pi_avg = O.osmotic_pressure_C_avg(iR, :);
    pi_b   = O.osmotic_pressure_C_brine(iR, :);
    A_T    = interp1(Ad.A_block(1,:), Ad.A_block(2,:), S.T_daily_mean);

    assert(~any(isnan(A_T)), ...
           'A(T) contains NaN: a daily temperature falls outside the A_block range.');
    assert(R_set <= R_ceil, ...
           'Recovery set point %.0f%% exceeds the vessel ceiling %.1f%%.', R_set*100, R_ceil*100);

    %% 3. Flux <-> flow conversion for this plant
    LMH_to_m3d = 24/1000;
    flux2Qf = @(J)  J  * A_mem * LMH_to_m3d / R_set;
    Qf2flux = @(Qf) Qf * R_set * 1000 / (24 * A_mem);

    %% 4. System curve
    J_sweep = (0 : 0.25 : J_elem)';
    Qf      = flux2Qf(J_sweep);
    nQ      = numel(Qf);
    Hsys    = pi_avg + (J_sweep ./ A_T);          % [nQ x 366] bar

    %% 5. Feasibility
    P_max       = 83;
    driving_ok  = Hsys > pi_b;
    pressure_ok = Hsys < P_max;
    feasible    = driving_ok & pressure_ok;

    J_min_day = A_T .* (pi_b - pi_avg);
    J_min_yr  = max(J_min_day);
    Qf_min_yr = flux2Qf(J_min_yr);

    if J_design < J_min_yr
        warning('J_design = %g LMH is below the minimum viable flux (%.1f LMH).', ...
                J_design, J_min_yr);
    end
    if J_design < J_lo || J_design > J_hi
        warning('J_design = %g LMH is outside the %g-%g LMH band for %s.', ...
                J_design, J_lo, J_hi, cfg_name);
    end

    %% 6. Design point
    Qp_des = J_design * A_mem * LMH_to_m3d;
    Qf_des = Qp_des / R_set;
    Qb_des = Qf_des - Qp_des;

    dP_des     = pi_avg + J_design ./ A_T;
    dP_des_min = min(dP_des);
    dP_des_max = max(dP_des);
    [~, jHot]  = max(dP_des);
    [~, jCold] = min(dP_des);

    Qf_vessel_h = Qf_des / n_vess / 24;
    P_hyd       = Qf_des/24/3600 * dP_des_max*1e5/1000;   % [kW]

    dP_env_max = max(Hsys, [], 2);
    dP_env_min = min(Hsys, [], 2);

    %% 7. Pack output
    out = struct( ...
        'n_elem', n_elem, 'n_vess', n_vess, 'R_set', R_set, ...
        'J_design', J_design, 'cfg_name', cfg_name, ...
        'A_mem', A_mem, 'R_ceil', R_ceil, ...
        'J_lo', J_lo, 'J_hi', J_hi, 'J_elem', J_elem, 'P_max', P_max, ...
        'J_sweep', J_sweep, 'Qf', Qf, 'Hsys', Hsys, ...
        'dP_env_max', dP_env_max, 'dP_env_min', dP_env_min, ...
        'feasible', feasible, 'driving_ok', driving_ok, 'pressure_ok', pressure_ok, ...
        'J_min_day', J_min_day, 'J_min_yr', J_min_yr, 'Qf_min_yr', Qf_min_yr, ...
        'Qp_des', Qp_des, 'Qf_des', Qf_des, 'Qb_des', Qb_des, ...
        'dP_des', dP_des, 'dP_des_min', dP_des_min, 'dP_des_max', dP_des_max, ...
        'jHot', jHot, 'jCold', jCold, 'Qf_vessel_h', Qf_vessel_h, 'P_hyd', P_hyd, ...
        'pi_avg', pi_avg, 'pi_b', pi_b, 'A_T', A_T, 'dates', dates, ...
        'flux2Qf', flux2Qf, 'Qf2flux', Qf2flux);

    if ~show, return; end

    %% 8. Report
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
    fprintf('    hardest day     : %s  (%.1f bar)\n', datestr(dates(jHot),  'dd mmm'), dP_des_max);
    fprintf('    easiest day     : %s  (%.1f bar)\n', datestr(dates(jCold), 'dd mmm'), dP_des_min);
    fprintf('  Hydraulic power   : %.1f kW at design point\n', P_hyd);

    fprintf('\n=== OPERATING RANGE ===\n');
    fprintf('  Min viable flux   : %.1f LMH (worst day) -> Q_f = %.2f m3/h\n', J_min_yr, Qf_min_yr/24);
    fprintf('  Design flux band  : %g - %g LMH          -> Q_f = %.2f - %.2f m3/h\n', ...
            J_lo, J_hi, flux2Qf(J_lo)/24, flux2Qf(J_hi)/24);
    fprintf('  Turndown below design point: %.0f%%\n', (1 - Qf_min_yr/Qf_des)*100);
    if J_min_yr > J_lo
        fprintf('  NOTE: min viable flux exceeds the bottom of the design band.\n');
    end

    %% 9. Plot
    figure('Name', sprintf('System curve - %d vessel(s)', n_vess));
    hold on; box on; grid on;

    Qf_h = Qf / 24;
    y_lo = floor(min(Hsys(:))/5)*5;
    y_hi = ceil(P_max/5)*5;

    xb = [flux2Qf(J_lo) flux2Qf(J_hi) flux2Qf(J_hi) flux2Qf(J_lo)]/24;
    hBand = fill(xb, [y_lo y_lo y_hi y_hi], [0.3 0.6 0.9], 'FaceAlpha', 0.15, 'EdgeColor', 'none');
    hAll  = plot(Qf_h, Hsys, '-', 'Color', [0.75 0.75 0.75], 'LineWidth', 0.3);
    hMax  = plot(Qf_h, dP_env_max, 'r-', 'LineWidth', 2.0);
    hMin  = plot(Qf_h, dP_env_min, 'b-', 'LineWidth', 2.0);
    hJmin = xline(Qf_min_yr/24, 'm-', 'LineWidth', 1.5);
    hPmax = yline(P_max, 'k-', 'LineWidth', 1.4);
    hDes  = plot(Qf_des/24, dP_des_max, 'ko', 'MarkerFaceColor', 'y', 'MarkerSize', 9);

    xlabel('Feed flow Q_f [m^3/h]', 'FontSize', 12);
    ylabel('Required pressure \DeltaP [bar]', 'FontSize', 12);
    title(sprintf('System curve, full year — %d x %d elements, %.0f m^2, R = %.0f%%', ...
          n_vess, n_elem, A_mem, R_set*100));
    legend([hMax hMin hAll(1) hJmin hPmax hBand hDes], ...
           {'Worst day at each flow', 'Best day at each flow', 'Individual days (366)', ...
            'Min viable flow (all days)', 'Element pressure limit', ...
            sprintf('Design band %g-%g LMH', J_lo, J_hi), 'Design point'}, ...
           'Location', 'southeast', 'FontSize', 9);
    xlim([0 ceil(max(Qf_h))]); ylim([y_lo y_hi]);
    hold off;
end