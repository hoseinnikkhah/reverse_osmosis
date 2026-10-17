
clear; close all; clc;
fprintf('>>> running design_map.m  (pretreatment x plant size, one figure)\n');

%% ====================== 1.  WHAT TO MAP  ==============================
% ---- edit this block only ---------------------------------------------
n_elem   = 7;                              % elements per vessel
VESSELS  = [94 120 150];        % plant sizes to mark
R_set    = 0.35;                           % system recovery, fraction
P_max    = 83;                             % element pressure rating, bar
% No pump efficiency here.  Everything this script reports is hydraulic:
% exact, and free of any assumption about equipment that has not been
% selected yet.  Electrical power and electrical SEC follow later from
% eta(Q,H) of the chosen pump, evaluated per operating point through the
% affinity laws, with the ERD credit subtracted.
DEMAND   = [100 1000 10000];               % optional capacity targets, m3/d ([] for none)
rho_sw   = 1025;  g = 9.81;
%% ====================== 2.  LOAD  =====================================
D  = load('design_data.mat');
O  = load('osmotic_pressure_recovery.mat');
Ad = load('A_temp_data.mat');
S  = load('salinity_and_temp_mean.mat','T_daily_mean','S_daily_mean','dates');
dates = S.dates;

iE = find(D.N_elements == n_elem, 1);
iR = find(abs(O.recovery - R_set*100) < 1e-9, 1);
assert(~isempty(iE), 'n_elem = %g not in the design grid.', n_elem);
assert(~isempty(iR), 'R_set = %.3f not on the stored recovery grid.', R_set);

pi_avg = O.osmotic_pressure_C_avg(iR,:);
A_T    = interp1(Ad.A_block(1,:), Ad.A_block(2,:), S.T_daily_mean);

LMH_to_m3d = 24/1000;
bar2m      = 1e5/(rho_sw*g);

nC = size(D.config,1);
nV = numel(VESSELS);
col = lines(nC);

%% ====================== 3.  BUILD THE MAP  ============================
Qp   = zeros(nC,nV);   Qf    = zeros(nC,nV);
Phyd = zeros(nC,nV);   Amem  = zeros(1,nV);
dPhi = zeros(nC,1);    dPlo  = zeros(nC,1);
SECh = zeros(nC,1);    Jdes  = zeros(nC,1);
Rcl  = zeros(nC,1);    Hard  = strings(nC,1);

for v = 1:nV
    iV = find(D.N_vessels == VESSELS(v), 1);
    assert(~isempty(iV), 'n_vess = %g not in the design grid.', VESSELS(v));
    Amem(v) = D.total_A(iE,iV);
end

for c = 1:nC
    band   = D.config.J_design{c};
    J_des  = round(((min(band) + max(band))/2)/0.5)*0.5;   % band midpoint
    dP_des = pi_avg + J_des ./ A_T;                        % bar [1 x 366]
    [dPmax, iHard] = max(dP_des);

    Jdes(c) = J_des;
    dPhi(c) = dPmax;
    dPlo(c) = min(dP_des);
    Rcl(c)  = 100*D.ceil_recovery(iE,c);
    Hard(c) = string(datestr(dates(iHard),'dd mmm'));

    % SEC_hyd = 0.0277778 * dP / R  -> exact, no membrane area, no pump.
    % This is the hydraulic work the membrane demands per m3 of permeate:
    % a floor that no pump selection can go below.
    SECh(c) = 1e5*dPmax/(3.6e6*R_set);                     % kWh/m3, hydraulic

    Qp(c,:)   = J_des * Amem * LMH_to_m3d;                 % m3/d
    Qf(c,:)   = Qp(c,:) / R_set;
    Phyd(c,:) = dPmax*1e5 .* (Qf(c,:)/86400) / 1000;       % kW, hydraulic
end

%% ====================== 4.  FIGURE  ===================================
figure('Name','design_map - capacity vs pressure','Color','w', ...
       'Position',[80 220 860 600]);
hold on; grid on; box on;

% optional capacity targets
for d = 1:numel(DEMAND)
    xline(DEMAND(d), ':', 'Color',[0.55 0.55 0.55], 'LineWidth',1.0, ...
          'Label',sprintf('%g m^3/d', DEMAND(d)), 'LabelOrientation','horizontal', ...
          'LabelVerticalAlignment','top', 'FontSize',8, 'HandleVisibility','off');
end

hC = gobjects(nC,1);
for c = 1:nC
    % the worst-day row: constant pressure across every plant size
    plot(Qp(c,:), dPhi(c)*ones(1,nV), '-', 'Color',col(c,:), 'LineWidth',1.4, ...
         'HandleVisibility','off');
    % best-day row, dashed
    plot(Qp(c,:), dPlo(c)*ones(1,nV), '--', 'Color',col(c,:), 'LineWidth',1.0, ...
         'HandleVisibility','off');
    hC(c) = plot(Qp(c,:), dPhi(c)*ones(1,nV), 'o', 'MarkerSize',8, ...
         'MarkerFaceColor',col(c,:), 'MarkerEdgeColor','k', 'LineStyle','none', ...
         'DisplayName', sprintf('%s   J_d %.1f LMH,  \\DeltaP %.1f bar,  SEC_{hyd} %.2f kWh/m^3', ...
                                D.config.Name(c), Jdes(c), dPhi(c), SECh(c)));
    plot(Qp(c,:), dPlo(c)*ones(1,nV), 'o', 'MarkerSize',6, ...
         'MarkerFaceColor','w', 'MarkerEdgeColor',col(c,:), 'LineWidth',1.1, ...
         'LineStyle','none', 'HandleVisibility','off');
end

% vessel-count annotation along the top row
for v = 1:nV
    text(Qp(1,v), dPhi(1)+0.9, sprintf('%dv', VESSELS(v)), ...
         'FontSize',7, 'HorizontalAlignment','center', 'Color',[0.35 0.35 0.35]);
end

set(gca,'XScale','log');
xlim([min(Qp(:))/1.8  max(Qp(:))*1.8]);
ylim([floor(min(dPlo))-3  ceil(max(dPhi))+3]);
xlabel('Permeate capacity  Q_p  (m^3/d)');
ylabel('Required pressure  \DeltaP  (bar)');
title(sprintf(['Design map - %d elements per vessel, R = %.0f %%\n' ...
               'filled = worst day, open = best day;  rows are flat because ' ...
               '\\DeltaP and SEC_{hyd} do not scale with plant size\n' ...
               'all quantities hydraulic - electrical values follow pump selection and ERD'], ...
               n_elem, R_set*100));
legend(hC,'Location','southoutside','Box','off','FontSize',8);

yyaxis right
ylim([floor(min(dPlo))-3  ceil(max(dPhi))+3] * bar2m);
ylabel('Equivalent head  H  (m)');
set(gca,'YColor',[0.35 0.35 0.35]);
yyaxis left

%% ====================== 5.  TABLE  ====================================
nR = nC*nV;
Configuration = strings(nR,1);  Vessels    = zeros(nR,1);
Area_m2       = zeros(nR,1);    Jd_LMH     = zeros(nR,1);
Qp_m3d        = zeros(nR,1);    Qf_m3h     = zeros(nR,1);
dPmin_bar     = zeros(nR,1);    dPmax_bar  = zeros(nR,1);
Phyd_max_kW   = zeros(nR,1);    SEChyd_kWhm3 = zeros(nR,1);
Rceil_pct     = zeros(nR,1);
HardestDay    = strings(nR,1);  Feasible   = strings(nR,1);

r = 0;
for c = 1:nC
    for v = 1:nV
        r = r + 1;
        Configuration(r) = D.config.Name(c);
        Vessels(r)   = VESSELS(v);
        Area_m2(r)   = Amem(v);
        Jd_LMH(r)    = Jdes(c);
        Qp_m3d(r)    = Qp(c,v);
        Qf_m3h(r)    = Qf(c,v)/24;
        dPmin_bar(r) = dPlo(c);
        dPmax_bar(r) = dPhi(c);
        Phyd_max_kW(r)  = Phyd(c,v);
        SEChyd_kWhm3(r) = Phyd(c,v)*24/Qp(c,v);            % recomputed per row
        Rceil_pct(r) = Rcl(c);
        HardestDay(r)= Hard(c);
        ok = (dPhi(c) < P_max) && (R_set < Rcl(c)/100);
        if ok, Feasible(r) = "yes"; else, Feasible(r) = "NO"; end
    end
end

T = table(Configuration, Vessels, Area_m2, Jd_LMH, Qp_m3d, Qf_m3h, ...
          dPmin_bar, dPmax_bar, Phyd_max_kW, SEChyd_kWhm3, ...
          Rceil_pct, HardestDay, Feasible);

fprintf('\n========================= DESIGN MAP =========================\n');
disp(T);
fprintf('Every column is hydraulic and exact - nothing here assumes a pump.\n');
fprintf('SEChyd_kWhm3 follows from dP and R alone: it varies with\n');
fprintf('pretreatment (through J_d) and NOT with plant size.\n');
fprintf('Electrical power and electrical SEC are computed in the pump layer\n');
fprintf('from eta(Q,H), then reduced by the ERD credit.  They must come out\n');
fprintf('ABOVE these hydraulic values - that is the check.\n');
fprintf('==============================================================\n\n');

writetable(T,'design_map.csv');
save('design_map.mat','T','Qp','Qf','Phyd','SECh','dPhi','dPlo','Jdes', ...
     'Amem','VESSELS','n_elem','R_set','Rcl','Hard');
fprintf('Saved design_map.csv and design_map.mat\n');