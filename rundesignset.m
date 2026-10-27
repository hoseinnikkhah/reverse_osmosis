
clear; close all; clc;

%% ---- fixed hardware and operating point ------------------------------
n_elem = 7;        % elements per vessel
n_vess = 96;        % vessels
R_set  = 0.35;     % system recovery, fraction
P_max  = 83;       % element pressure rating, bar
rho_sw = 1025;  g = 9.81;

%% ---- load ------------------------------------------------------------
D  = load('design_data.mat');
O  = load('osmotic_pressure_recovery.mat');
Ad = load('A_temp_data.mat');
S  = load('salinity_and_temp_mean.mat','T_daily_mean','S_daily_mean','dates');
dates = S.dates;

iE = find(D.N_elements == n_elem, 1);
iV = find(D.N_vessels  == n_vess, 1);
iR = find(abs(O.recovery - R_set*100) < 1e-9, 1);
assert(~isempty(iE) && ~isempty(iV) && ~isempty(iR), 'Design point not on the stored grids.');

A_mem  = D.total_A(iE,iV);
pi_avg = O.osmotic_pressure_C_avg(iR,:);
pi_b   = O.osmotic_pressure_C_brine(iR,:);
A_T    = interp1(Ad.A_block(1,:), Ad.A_block(2,:), S.T_daily_mean);

LMH_to_m3d = 24/1000;
bar2m      = 1e5/(rho_sw*g);

%% ---- the single shared curve, swept to the largest J_max -------------
J_top   = max(D.config.J_max);                  % 38 LMH
J_sweep = (0 : 0.25 : J_top)';
Hsys    = pi_avg + (J_sweep ./ A_T);
dP_env_max = max(Hsys, [], 2);
dP_env_min = min(Hsys, [], 2);

%% ---- per-configuration design point ----------------------------------
nC  = size(D.config,1);
col = lines(nC);

Configuration = strings(nC,1);  Band_LMH   = strings(nC,1);
J_design_LMH  = zeros(nC,1);    J_max_LMH  = zeros(nC,1);
Rceil_pct     = zeros(nC,1);    Qp_m3d     = zeros(nC,1);
Qf_m3h        = zeros(nC,1);    dP_min_bar = zeros(nC,1);
dP_max_bar    = zeros(nC,1);    Head_max_m = zeros(nC,1);
Phyd_max_kW   = zeros(nC,1);    HardestDay = strings(nC,1);
Feasible      = strings(nC,1);

figure('Name','Pretreatment comparison','Color','w','Position',[80 300 760 560]);
hold on; grid on; box on;

plot(J_sweep, Hsys, '-', 'Color',[0.82 0.86 0.91], 'LineWidth',0.3, ...
     'HandleVisibility','off');
hMax = plot(J_sweep, dP_env_max, '-', 'Color',[0.75 0.10 0.10], 'LineWidth',2.2, ...
            'DisplayName','Annual worst day  (upper envelope)');
hMin = plot(J_sweep, dP_env_min, '-', 'Color',[0.10 0.35 0.75], 'LineWidth',2.2, ...
            'DisplayName','Annual best day  (lower envelope)');
yline(P_max,'k--','LineWidth',1.1,'Label','element rating 83 bar', ...
      'LabelHorizontalAlignment','left','HandleVisibility','off');

y_lo = max(0, floor(min(dP_env_min)/5)*5 - 5);
y_hi = ceil(P_max/5)*5;
hBand = gobjects(nC,1);

for c = 1:nC
    name   = D.config.Name(c);
    band   = D.config.J_design{c};
    J_lo   = min(band);   J_hi = max(band);
    J_elem = D.config.J_max(c);
    R_ceil = D.ceil_recovery(iE,c);
    J_des  = round(((J_lo + J_hi)/2)/0.5)*0.5;        % band midpoint

    % ---- duty at this configuration's design flux --------------------
    dP_des = pi_avg + J_des ./ A_T;
    [dPmax, iHard] = max(dP_des);
    dPmin          = min(dP_des);
    Q_p = J_des * A_mem * LMH_to_m3d;
    Q_f = Q_p / R_set;
    Phd = max(dP_des * 1e5 .* (Q_f/86400) / 1000);

    % ---- band, extent and design point on the shared curve -----------
    % The band patch carries the legend entry, so the colour swatch the
    % reader sees in the legend is the shaded band itself.
    hBand(c) = patch([J_lo J_hi J_hi J_lo], [y_lo y_lo y_hi y_hi], col(c,:), ...
          'FaceAlpha',0.10, 'EdgeColor',col(c,:), 'LineStyle',':', ...
          'DisplayName', sprintf('%s   band %.0f-%.0f,  J_d = %.1f,  J_{max} = %.0f LMH', ...
                                 name, J_lo, J_hi, J_des, J_elem));
    xline(J_elem, '-', 'Color',col(c,:), 'LineWidth',1.4, 'Alpha',0.6, ...
          'HandleVisibility','off');                       % labelled in the legend instead
    plot(J_des, dPmax, 'o', 'MarkerSize',9, ...
         'MarkerFaceColor',col(c,:), 'MarkerEdgeColor','k', 'HandleVisibility','off');
    plot(J_des, dPmin, 'o', 'MarkerSize',9, 'MarkerFaceColor','w', ...
         'MarkerEdgeColor',col(c,:), 'LineWidth',1.4, 'HandleVisibility','off');
    plot([J_des J_des], [dPmin dPmax], '-', 'Color',col(c,:), 'LineWidth',1.6, ...
         'HandleVisibility','off');

    % ---- table row ----------------------------------------------------
    Configuration(c) = name;
    Band_LMH(c)      = sprintf('%.0f-%.0f', J_lo, J_hi);
    J_design_LMH(c)  = J_des;
    J_max_LMH(c)     = J_elem;
    Rceil_pct(c)     = 100*R_ceil;
    Qp_m3d(c)        = Q_p;
    Qf_m3h(c)        = Q_f/24;
    dP_min_bar(c)    = dPmin;
    dP_max_bar(c)    = dPmax;
    Head_max_m(c)    = dPmax*bar2m;
    Phyd_max_kW(c)   = Phd;
    HardestDay(c)    = string(datestr(dates(iHard),'dd mmm'));
    ok = (dPmax < P_max) && (R_set < R_ceil);
    if ok, Feasible(c) = "yes"; else, Feasible(c) = "NO"; end
end

% ---- proxy handles so the marker convention is explained in the legend --
hDesHi = plot(NaN, NaN, 'o', 'MarkerSize',9, 'MarkerFaceColor',[0.35 0.35 0.35], ...
              'MarkerEdgeColor','k', 'LineStyle','none', ...
              'DisplayName','Design point, worst day   (filled)');
hDesLo = plot(NaN, NaN, 'o', 'MarkerSize',9, 'MarkerFaceColor','w', ...
              'MarkerEdgeColor',[0.35 0.35 0.35], 'LineWidth',1.4, 'LineStyle','none', ...
              'DisplayName','Design point, best day    (open)');
hJmax  = plot(NaN, NaN, '-', 'Color',[0.35 0.35 0.35], 'LineWidth',1.4, ...
              'DisplayName','J_{max,element} cut-off   (vertical line)');

xlim([0 J_top*1.03]);  ylim([y_lo y_hi]);
xlabel('Permeate flux  J_w  (LMH)');
ylabel('Required pressure  \DeltaP  (bar)');
title(sprintf(['One system curve, four pretreatment configurations\n' ...
               '%de x %dv, A_{mem} = %.0f m^2, R = %.0f %%'], ...
               n_elem, n_vess, A_mem, R_set*100));
legend([hMax; hMin; hBand; hDesHi; hDesLo; hJmax], ...
       'Location','northwest','Box','off','FontSize',8);

%% ---- table -----------------------------------------------------------
T = table(Configuration, Band_LMH, J_design_LMH, J_max_LMH, Rceil_pct, ...
          Qp_m3d, Qf_m3h, dP_min_bar, dP_max_bar, Head_max_m, ...
          Phyd_max_kW, HardestDay, Feasible);

fprintf('\n================ PRETREATMENT COMPARISON ================\n');
fprintf('%de x %dv, A_mem = %.0f m2, R = %.0f %%\n\n', n_elem, n_vess, A_mem, R_set*100);
disp(T);
fprintf('All four share one system curve; only the band, the J_max\n');
fprintf('cut-off and the staging ceiling differ.\n');
fprintf('=========================================================\n\n');

writetable(T,'pretreatment_comparison.csv');
fprintf('Saved pretreatment_comparison.csv\n');