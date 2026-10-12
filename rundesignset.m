%% runDesignSet.m
%  Overlay several PV-SWRO design points on one system-curve figure and
%  tabulate their duty.  Each row of DESIGNS is one call to systemCurve.
%
%  Column order:  n_elem | n_vess | R_set | J_design | cfg_name
%  Leave J_design as [] to take the midpoint of that configuration's
%  design flux band (14.5 / 15.5 / 17 / 19 LMH).

clear; close all; clc;

%% ---- CASE A: the four pretreatment configurations, same hardware ------
% Same 7-element / 1-vessel train, same recovery.  The only thing that
% changes is the allowed flux band and the maximum element flux, so this
% figure isolates what pretreatment does and does not control.

DESIGNS = { ...
     7,   1, 0.35, [], "Conventional pretreatment"   ; ...
     7,   1, 0.35, [], "Generic membrane filtration" ; ...
     7,   1, 0.35, [], "Well/open intake + UF"       ; ...
     7,   1, 0.35, [], "UF + B-free"                 };

% ---- CASE B: one configuration across the vessel range ----------------
% Uncomment to see the scale effect instead (identical curve in flux
% space, three decades apart in pump duty).
%
% DESIGNS = { ...
%      7,   1, 0.35, [], "Conventional pretreatment" ; ...
%      7,  25, 0.35, [], "Conventional pretreatment" ; ...
%      7, 100, 0.35, [], "Conventional pretreatment" ; ...
%      7, 150, 0.35, [], "Conventional pretreatment" };

%% ---- run ------------------------------------------------------------
nD  = size(DESIGNS,1);
res = cell(nD,1);

for d = 1:nD
    mode   = "add";  if d == 1, mode = "new"; end
    res{d} = systemCurve(DESIGNS{d,1}, DESIGNS{d,2}, DESIGNS{d,3}, ...
                         DESIGNS{d,4}, DESIGNS{d,5}, mode);
end

%% ---- comparison table ------------------------------------------------
Configuration = strings(nD,1);
Elements      = zeros(nD,1);   Vessels      = zeros(nD,1);
Area_m2       = zeros(nD,1);   Band_LMH     = strings(nD,1);
J_design_LMH  = zeros(nD,1);   Rceil_pct    = zeros(nD,1);
Qp_m3d        = zeros(nD,1);   Qf_m3h       = zeros(nD,1);
dP_min_bar    = zeros(nD,1);   dP_max_bar   = zeros(nD,1);
Phyd_max_kW   = zeros(nD,1);   Feasible     = strings(nD,1);

for d = 1:nD
    o = res{d};
    Configuration(d) = o.cfg_name;
    Elements(d)      = o.n_elem;
    Vessels(d)       = o.n_vess;
    Area_m2(d)       = o.A_mem;
    Band_LMH(d)      = sprintf('%.0f-%.0f', o.J_lo, o.J_hi);
    J_design_LMH(d)  = o.J_design;
    Rceil_pct(d)     = 100*o.R_ceil;
    Qp_m3d(d)        = o.Q_p;
    Qf_m3h(d)        = o.Q_f/24;
    dP_min_bar(d)    = o.dP_des_min;
    dP_max_bar(d)    = o.dP_des_max;
    Phyd_max_kW(d)   = o.P_hyd_max;

    ok = o.inBand && (o.dP_des_max < o.P_max) && (o.R_set < o.R_ceil);
    if ok, Feasible(d) = "yes"; else, Feasible(d) = "NO"; end
end

T = table(Configuration, Elements, Vessels, Area_m2, Band_LMH, ...
          J_design_LMH, Rceil_pct, Qp_m3d, Qf_m3h, ...
          dP_min_bar, dP_max_bar, Phyd_max_kW, Feasible);

fprintf('\n======================= DESIGN SET =======================\n');
disp(T);
fprintf('Hardest day %s  |  easiest day %s  (by required pressure)\n', ...
        datestr(res{1}.date_hard,'dd mmm'), datestr(res{1}.date_easy,'dd mmm'));
fprintf('=========================================================\n\n');

save('design_set_results.mat','T','res','DESIGNS');