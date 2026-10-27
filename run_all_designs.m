%% run_all_designs.m
%  Drive systemCurve.m over a whole design list and keep every result.
%
%  systemCurve.m saves one .mat per design, named
%     system_curve_<config>_<e>e_<v>v_R<rr>.mat
%  so nothing is overwritten.  The pump / PV layer later loads whichever
%  design it needs by that name, or reads the summary table written here.
%
%  Figures are suppressed in batch.  To study one design in detail, run
%  systemCurve.m on its own with that design in its edit block.

clear; close all; clc;
fprintf('>>> running run_all_designs.m  (batch over the design list)\n\n');

%% ====================== 1.  THE DESIGN LIST  ==========================
% ---- edit this block only ---------------------------------------------
% Columns:  cfg_name | n_elem | n_vess
% Put ONE row per design you want carried forward.  J_design is left to
% the band midpoint of whichever configuration the row names.

DESIGNS = { ...
    "Conventional pretreatment"   , 7,  96 ; ...
    "Conventional pretreatment"   , 7, 120 ; ...
    "Conventional pretreatment"   , 7, 150 ; ...
    "Generic membrane filtration" , 7,  96 ; ...
    "Generic membrane filtration" , 7, 120 ; ...
    "Generic membrane filtration" , 7, 150 ; ...
    "Well/open intake + UF"       , 7,  96 ; ...
    "Well/open intake + UF"       , 7, 120 ; ...
    "Well/open intake + UF"       , 7, 150 ; ...
    "UF + B-free"                 , 7,  96 ; ...
    "UF + B-free"                 , 7, 120 ; ...
    "UF + B-free"                 , 7, 150 };

R_SET  = 0.45;        % system recovery for the whole batch
J_FIX  = [];          % [] = band midpoint per configuration (recommended)
% -----------------------------------------------------------------------

%% ====================== 2.  RUN  ======================================
BATCH_MODE = true;             %#ok<NASGU>  read by systemCurve.m
SHOW_FIGS  = false;            %#ok<NASGU>

nD = size(DESIGNS,1);

Configuration = strings(nD,1);  Elements   = zeros(nD,1);
Vessels       = zeros(nD,1);    Area_m2    = zeros(nD,1);
Jd_LMH        = zeros(nD,1);    Qp_m3d     = zeros(nD,1);
Qf_m3h        = zeros(nD,1);    Qb_m3h     = zeros(nD,1);
dPmin_bar     = zeros(nD,1);    dPmax_bar  = zeros(nD,1);
Head_max_m    = zeros(nD,1);    Phyd_max_kW= zeros(nD,1);
SEC_hyd       = zeros(nD,1);    Rceil_pct  = zeros(nD,1);
InBand        = strings(nD,1);  File       = strings(nD,1);

fprintf('design                         train        area      capacity        pressure        power\n');
fprintf('-------------------------------------------------------------------------------------------\n');

for d = 1:nD
    cfg_name = DESIGNS{d,1};
    n_elem   = DESIGNS{d,2};
    n_vess   = DESIGNS{d,3};
    R_set    = R_SET;
    J_design = J_FIX;

    run('systemCurve.m');       % computes, saves its own .mat, prints one line

    Configuration(d) = cfg_name;
    Elements(d)      = n_elem;
    Vessels(d)       = n_vess;
    Area_m2(d)       = A_mem;
    Jd_LMH(d)        = J_design;
    Qp_m3d(d)        = Q_p;
    Qf_m3h(d)        = Q_f/24;
    Qb_m3h(d)        = Q_b/24;
    dPmin_bar(d)     = dP_des_min;
    dPmax_bar(d)     = dP_des_max;
    Head_max_m(d)    = max(H_des);
    Phyd_max_kW(d)   = P_hyd_max;
    SEC_hyd(d)       = P_hyd_max*24/Q_p;        % kWh/m3, hydraulic
    Rceil_pct(d)     = 100*R_ceil;
    InBand(d)        = string(inBand);
    File(d)          = design.file;

    % the batch supplies these fresh each pass; clear so a failed lookup
    % cannot silently reuse the previous design's value
    clearvars -except DESIGNS R_SET J_FIX BATCH_MODE SHOW_FIGS nD d ...
        Configuration Elements Vessels Area_m2 Jd_LMH Qp_m3d Qf_m3h Qb_m3h ...
        dPmin_bar dPmax_bar Head_max_m Phyd_max_kW SEC_hyd Rceil_pct InBand File
end

%% ====================== 3.  SUMMARY  ==================================
T = table(Configuration, Elements, Vessels, Area_m2, Jd_LMH, ...
          Qp_m3d, Qf_m3h, Qb_m3h, dPmin_bar, dPmax_bar, Head_max_m, ...
          Phyd_max_kW, SEC_hyd, Rceil_pct, InBand, File);

fprintf('\n===================== BATCH SUMMARY =====================\n');
disp(T);
fprintf('One .mat per design was written; see the File column.\n');
fprintf('dPmax_bar and SEC_hyd depend on the CONFIGURATION only -\n');
fprintf('rows sharing a configuration must show identical values.\n');
fprintf('=========================================================\n\n');

writetable(T,'design_runs.csv');
save('design_runs.mat','T','DESIGNS','R_SET');
fprintf('Saved design_runs.csv and design_runs.mat\n');