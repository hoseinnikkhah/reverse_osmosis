%% systemCurve.m
%  System curve for ONE PV-SWRO design point.
%
%  Run it directly to study one design interactively, or let
%  run_all_designs.m drive it in batch over a whole design list.
%
%  dP(J,t) = pi_avg(R,t) + J / A(T(t))                             [bar]
%  Q_f(J)  = J * A_mem * (24/1000) / R                             [m3/d]
%
%  dP carries no pretreatment term and no membrane-area term: it is set by
%  recovery, seawater salinity and seawater temperature alone.  The
%  pretreatment configuration fixes WHERE on that curve the plant may sit
%  (design flux band) and HOW FAR the curve extends (max element flux).
%  The vessel/element count rescales the Q_f axis only, through A_mem.
%
%  Inputs : design_data.mat, osmotic_pressure_recovery.mat,
%           A_temp_data.mat, salinity_and_temp_mean.mat
%  Output : system_curve_<config>_<e>e_<v>v_R<rr>.mat   (+ two figures)

%% ====================== 1.  DESIGN SELECTION  ==========================
if exist('BATCH_MODE','var') && BATCH_MODE
    % Driven by run_all_designs.m, which supplies cfg_name, n_elem,
    % n_vess, R_set, J_design and SHOW_FIGS.  Do not clear the workspace.
else
    clear; close all; clc;

    % ---- edit this block only -----------------------------------------
    cfg_name = "Conventional pretreatment";
    %          "UF + B-free"                   band 17-21,  J_max 38,  r_e 16%
    %          "Well/open intake + UF"         band 15-19,  J_max 36,  r_e 15%
    %          "Generic membrane filtration"   band 14-17,  J_max 34,  r_e 14%
    %          "Conventional pretreatment"     band 12-17,  J_max 32,  r_e 13%

    n_elem   = 7;      % elements per pressure vessel        5, 6 or 7
    n_vess   = 1;      % number of pressure vessels          1 ... 150
    R_set    = 0.35;   % system recovery, fraction
    J_design = [];     % design flux, LMH;  [] = midpoint of this config's band
    % -------------------------------------------------------------------

    SHOW_FIGS = true;
    fprintf('>>> running systemCurve.m  (ONE design, two figures)\n');
end

% ---- fixed for the whole study, not design inputs ----------------------
P_max  = 83;           % element / vessel pressure rating, bar  (datasheet)
rho_sw = 1025;         % seawater density, kg/m3   (bar -> m head)
g      = 9.81;         % m/s2
% -----------------------------------------------------------------------

%% ====================== 2.  LOAD INPUTS  ==============================
D  = load('design_data.mat');                 % config, ceil_recovery, N_elements, N_vessels, total_A
O  = load('osmotic_pressure_recovery.mat');   % recovery, osmotic_pressure_C_avg, osmotic_pressure_C_brine
Ad = load('A_temp_data.mat');                 % A_block = [T ; A(T) in LMH/bar]
S  = load('salinity_and_temp_mean.mat','T_daily_mean','S_daily_mean','dates');
dates = S.dates;                              % promote out of the struct

%% ====================== 3.  INDEX LOOKUPS  ============================
k  = find(D.config.Name == cfg_name, 1);
iE = find(D.N_elements  == n_elem,   1);
iV = find(D.N_vessels   == n_vess,   1);
iR = find(abs(O.recovery - R_set*100) < 1e-9, 1);

assert(~isempty(k),  'Unknown configuration "%s".', cfg_name);
assert(~isempty(iE), 'n_elem = %g not in design grid [%s].', n_elem, num2str(D.N_elements));
assert(~isempty(iV), 'n_vess = %g not in design grid 1..%d.', n_vess, max(D.N_vessels));
assert(~isempty(iR), 'R_set = %.3f not in the stored recovery grid (%g..%g %%).', ...
                     R_set, min(O.recovery), max(O.recovery));

%% ============ 4.  CONFIGURATION LIMITS  (what cfg_name controls) ======
J_band = D.config.J_design{k};
J_lo   = min(J_band);                  % bottom of design band,   LMH
J_hi   = max(J_band);                  % top of design band,      LMH
J_elem = D.config.J_max(k);            % max element flux,        LMH
r_e    = D.config.rec_max(k)/100;      % max element recovery,    fraction
R_ceil = D.ceil_recovery(iE,k);        % 1-(1-r_e)^n_elem,        fraction

if isempty(J_design)
    J_design = round(((J_lo + J_hi)/2)/0.5)*0.5;     % band midpoint
end
inBand = (J_design >= J_lo) && (J_design <= J_hi);
if ~inBand
    warning('J_design = %.2f LMH is outside the "%s" band (%.1f-%.1f LMH).', ...
            J_design, cfg_name, J_lo, J_hi);
end
if R_set >= R_ceil
    warning('R_set = %.1f %% is at or above the staging ceiling %.1f %%.', ...
            R_set*100, R_ceil*100);
end

%% ====================== 5.  STATE VARIABLES  ==========================
A_mem  = D.total_A(iE,iV);                      % installed membrane area, m2
pi_avg = O.osmotic_pressure_C_avg(iR,:);        % bar  [1 x 366]
pi_b   = O.osmotic_pressure_C_brine(iR,:);      % bar  [1 x 366]
A_T    = interp1(Ad.A_block(1,:), Ad.A_block(2,:), S.T_daily_mean);   % LMH/bar

LMH_to_m3d = 24/1000;
flux2Qf = @(J)  J  * A_mem * LMH_to_m3d / R_set;        % LMH  -> m3/d
Qf2flux = @(Qf) Qf * R_set * 1000 / (24 * A_mem);       % m3/d -> LMH
bar2m   = 1e5/(rho_sw*g);                               % bar  -> m head

%% ====================== 6.  THE SYSTEM CURVE  =========================
J_sweep = (0 : 0.25 : J_elem)';                 % from 0 so the intercept is pi(C_avg)
Qf_swp  = flux2Qf(J_sweep);                     % m3/d
Hsys    = pi_avg + (J_sweep ./ A_T);            % bar  [nQ x 366]

dP_env_max = max(Hsys, [], 2);                  % annual upper envelope, per flux
dP_env_min = min(Hsys, [], 2);                  % annual lower envelope, per flux

%% ====================== 7.  FEASIBILITY  ==============================
driving_ok  = Hsys >  pi_b;                     % net driving force positive
pressure_ok = Hsys <  P_max;                    % within the pressure rating
feasible    = driving_ok & pressure_ok;

%% ================= 8.  DESIGN POINT AND PUMP DUTY  ====================
Q_p = J_design * A_mem * LMH_to_m3d;            % permeate, m3/d
Q_f = Q_p / R_set;                              % feed,     m3/d
Q_b = Q_f - Q_p;                                % brine,    m3/d

dP_des = pi_avg + J_design ./ A_T;              % required pressure, bar  [1 x 366]
[dP_des_max, iHard] = max(dP_des);              % hardest day = highest pressure
[dP_des_min, iEasy] = min(dP_des);
dP_des_mean = mean(dP_des);

H_des     = dP_des * bar2m;                     % equivalent pump head, m
P_hyd     = dP_des * 1e5 .* (Q_f/86400) / 1000; % hydraulic power, kW
P_hyd_max = max(P_hyd);
P_hyd_min = min(P_hyd);

%% ====================== 9.  REPORT  ===================================
if ~SHOW_FIGS
    fprintf('  %-30s %de x %3dv  A %7.0f m2  Q_p %9.1f m3/d  dP %5.2f-%5.2f bar  P %8.2f kW\n', ...
            cfg_name, n_elem, n_vess, A_mem, Q_p, dP_des_min, dP_des_max, P_hyd_max);
else
fprintf('\n=============== PV-SWRO DESIGN POINT ===============\n');
fprintf('Pretreatment      : %s\n', cfg_name);
fprintf('Train             : %d elements x %d vessels = %.0f m2\n', n_elem, n_vess, A_mem);
fprintf('Design flux band  : %.1f - %.1f LMH   (J_max,element = %.0f LMH)\n', J_lo, J_hi, J_elem);
fprintf('Design flux       : %.2f LMH          (in band: %s)\n', J_design, string(inBand));
fprintf('Recovery          : %.1f %%            (staging ceiling %.1f %%)\n', R_set*100, R_ceil*100);
fprintf('----------------------------------------------------\n');
fprintf('Permeate   Q_p    : %9.1f m3/d  (%7.2f m3/h)\n', Q_p, Q_p/24);
fprintf('Feed       Q_f    : %9.1f m3/d  (%7.2f m3/h)\n', Q_f, Q_f/24);
fprintf('Brine      Q_b    : %9.1f m3/d  (%7.2f m3/h)\n', Q_b, Q_b/24);
fprintf('----------------------------------------------------\n');
fprintf('Required dP       : %.2f - %.2f bar  (mean %.2f bar)\n', dP_des_min, dP_des_max, dP_des_mean);
fprintf('Equivalent head   : %.0f - %.0f m\n', min(H_des), max(H_des));
fprintf('Hydraulic power   : %.2f - %.2f kW\n', P_hyd_min, P_hyd_max);
fprintf('Hardest day       : %s  (%.2f bar)\n', datestr(dates(iHard),'dd mmm yyyy'), dP_des_max);
fprintf('Easiest day       : %s  (%.2f bar)\n', datestr(dates(iEasy),'dd mmm yyyy'), dP_des_min);
fprintf('Days feasible     : %d / %d at the design flux\n', ...
        sum(interp1(J_sweep, double(feasible), J_design) > 0.5), numel(dates));
fprintf('====================================================\n\n');
end

%% ================= 10.  FIGURE 1 - FLUX SPACE  ========================
if SHOW_FIGS
figure('Name','systemCurve 1/2 - flux space','Color','w','Position',[80 420 640 500]);
hold on; grid on; box on;

plot(J_sweep, Hsys, '-', 'Color',[0.80 0.84 0.90], 'LineWidth',0.3, ...
     'HandleVisibility','off');                               % all 366 days
hBand = patch([J_lo J_hi J_hi J_lo], [0 0 P_max P_max], [0.20 0.45 0.80], ...
              'FaceAlpha',0.10, 'EdgeColor',[0.20 0.45 0.80], 'LineStyle',':');
hMax  = plot(J_sweep, dP_env_max, '-',  'Color',[0.75 0.10 0.10], 'LineWidth',2.0);
hMin  = plot(J_sweep, dP_env_min, '-',  'Color',[0.10 0.35 0.75], 'LineWidth',2.0);
hDes  = plot(J_design, dP_des_max, 'o', 'MarkerSize',8, ...
             'MarkerFaceColor','k', 'MarkerEdgeColor','k');
plot(J_design, dP_des_min, 'o', 'MarkerSize',8, 'MarkerFaceColor','w', ...
     'MarkerEdgeColor','k', 'HandleVisibility','off');
yline(P_max, 'k--', 'LineWidth',1.1, 'Label','element rating 83 bar', ...
      'LabelHorizontalAlignment','left', 'HandleVisibility','off');

y_lo = max(0, floor(min(dP_env_min)/5)*5 - 5);
xlim([0 J_elem]);  ylim([y_lo ceil(P_max/5)*5]);
xlabel('Permeate flux  J_w  (LMH)');
ylabel('Required pressure  \DeltaP  (bar)');
title(sprintf('Design point - system curve in flux space\n%s, %de x %dv, A_{mem} = %.0f m^2, R = %.0f %%', ...
      cfg_name, n_elem, n_vess, A_mem, R_set*100));
legend([hMax hMin hBand hDes], ...
       {'annual worst day','annual best day','design flux band','design point'}, ...
       'Location','northwest','Box','off');

%% ============== 11.  FIGURE 2 - PUMP DUTY SPACE  ======================
% Same curve, x-axis converted from flux to real feed flow.  This is the
% plane in which a pump is selected: lay the manufacturer's H(Q) curve on
% top, and the intersection with the system curve is the operating point.
figure('Name','systemCurve 2/2 - pump duty space','Color','w','Position',[740 420 640 500]);
hold on; grid on; box on;

Qh = Qf_swp/24;                                              % m3/h
plot(Qh, Hsys, '-', 'Color',[0.80 0.84 0.90], 'LineWidth',0.3, ...
     'HandleVisibility','off');
gMax = plot(Qh, dP_env_max, '-', 'Color',[0.75 0.10 0.10], 'LineWidth',2.0);
gMin = plot(Qh, dP_env_min, '-', 'Color',[0.10 0.35 0.75], 'LineWidth',2.0);
gDes = plot(Q_f/24, dP_des_max, 'o', 'MarkerSize',8, ...
            'MarkerFaceColor','k', 'MarkerEdgeColor','k');
plot(Q_f/24, dP_des_min, 'o', 'MarkerSize',8, 'MarkerFaceColor','w', ...
     'MarkerEdgeColor','k', 'HandleVisibility','off');
yline(P_max, 'k--', 'LineWidth',1.1, 'HandleVisibility','off');
xline(Q_f/24, ':', 'Color',[0.3 0.3 0.3], 'LineWidth',1.1, ...
      'Label',sprintf('Q_f = %.1f m^3/h', Q_f/24), 'HandleVisibility','off');

xlim([0 max(Qh)*1.02]);  ylim([y_lo ceil(P_max/5)*5]);
xlabel('Feed flow  Q_f  (m^3/h)');
ylabel('Required pressure  \DeltaP  (bar)');
title(sprintf('Design point - pump duty space\n%s, %de x %dv, Q_f = %.1f m^3/h, head %.0f - %.0f m', ...
      cfg_name, n_elem, n_vess, Q_f/24, min(H_des), max(H_des)));
legend([gMax gMin gDes], {'annual worst day','annual best day','duty point'}, ...
       'Location','northwest','Box','off');

yyaxis right                                                  % head axis for pump curves
ylim([y_lo ceil(P_max/5)*5] * bar2m);
ylabel('Equivalent head  H  (m)');
set(gca,'YColor',[0.35 0.35 0.35]);
yyaxis left
end

%% ====================== 12.  SAVE  ====================================
% Everything the PV / energy layer needs downstream, nothing more.
% The filename carries the design identity, so running several designs
% accumulates files instead of overwriting one.
tagMap = ["UF + B-free"                 "UFBfree" ; ...
          "Well/open intake + UF"       "WellUF"  ; ...
          "Generic membrane filtration" "GenMF"   ; ...
          "Conventional pretreatment"   "Conv"    ];
cfgTag  = tagMap(tagMap(:,1) == cfg_name, 2);
outfile = sprintf('system_curve_%s_%de_%dv_R%02.0f.mat', ...
                  cfgTag, n_elem, n_vess, R_set*100);

design = struct('cfg_name',cfg_name, 'n_elem',n_elem, 'n_vess',n_vess, ...
                'R_set',R_set, 'J_design',J_design, 'A_mem',A_mem, ...
                'J_lo',J_lo, 'J_hi',J_hi, 'J_elem',J_elem, 'R_ceil',R_ceil, ...
                'tag',string(cfgTag), 'file',string(outfile));

save(outfile, ...
     'design', 'dates', ...            % design definition + calendar
     'dP_des', 'H_des', 'P_hyd', ...   % daily duty time series  [1 x 366]
     'Q_p', 'Q_f', 'Q_b', ...          % design flows, m3/d
     'J_sweep', 'Qf_swp', 'Hsys', ...  % full curve, for pump matching
     'dP_env_max', 'dP_env_min', ...
     'feasible', 'pi_avg', 'pi_b', 'A_T', 'P_max', 'bar2m');

if SHOW_FIGS, fprintf('Saved %s\n', outfile); end