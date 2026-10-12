%% train_staging.m
%  Split a plant into parallel trains and work out what it can actually
%  follow.
%
%  A pressure vessel array is built as k identical TRAINS, each with its
%  own high-pressure pump.  Two mechanisms set the operating range:
%
%    within a train : the VFD modulates flux across the design band, a
%                     ratio of only J_hi/J_lo (1.24 to 1.42 depending on
%                     pretreatment)
%    between trains : trains are switched on and off, so with j of k
%                     trains online the reachable feed flow is
%                     j * [Q_lo, Q_hi]
%
%  Stepping from j to j+1 trains leaves no gap only when
%      j*J_hi >= (j+1)*J_lo    ->    j >= J_lo/(J_hi - J_lo)
%  Below that threshold the reachable set has holes: flows the plant
%  cannot hold steadily.  Under PV those holes are where available solar
%  power has to be curtailed, so this is the hydraulic origin of the
%  curtailment term - not an assumption.
%
%  Inputs : design_data.mat, osmotic_pressure_recovery.mat,
%           A_temp_data.mat, salinity_and_temp_mean.mat
%  Output : train_staging.csv  (+ two figures)

clear; close all; clc;
fprintf('>>> running train_staging.m\n');

%% ====================== 1.  THE PLANT  ================================
% ---- edit this block only ---------------------------------------------
cfg_name = "Conventional pretreatment";
n_elem   = 7;           % elements per vessel
n_vess   = 94;          % TOTAL vessels in the plant
R_set    = 0.35;        % system recovery, fraction
K_SHOW   = 4;           % train count to draw the staircase for
K_MAX    = 12;          % sweep 1..K_MAX trains for the coverage study
A_elem   = 41;          % m2 per element (SW30HRLE-440)
% -----------------------------------------------------------------------

%% ====================== 2.  LOAD  =====================================
D  = load('design_data.mat');
O  = load('osmotic_pressure_recovery.mat');
Ad = load('A_temp_data.mat');
S  = load('salinity_and_temp_mean.mat','T_daily_mean','dates');

k   = find(D.config.Name == cfg_name, 1);
iR  = find(abs(O.recovery - R_set*100) < 1e-9, 1);
assert(~isempty(k) && ~isempty(iR), 'Configuration or recovery not on the stored grids.');

band   = D.config.J_design{k};
J_lo   = min(band);   J_hi = max(band);
J_des  = round(((J_lo + J_hi)/2)/0.5)*0.5;
pi_avg = O.osmotic_pressure_C_avg(iR,:);
A_T    = interp1(Ad.A_block(1,:), Ad.A_block(2,:), S.T_daily_mean);

dP_des = pi_avg + J_des ./ A_T;
dP_max = max(dP_des);   dP_min = min(dP_des);

LMH_to_m3d = 24/1000;

%% ============ 3.  THE CONTINUITY THRESHOLD (analytic) =================
j_star    = ceil(J_lo/(J_hi - J_lo));     % trains needed for no gaps
band_ratio = J_hi/J_lo;                   % single-train turndown ratio

fprintf('\n--- %s ---\n', cfg_name);
fprintf('design band      : %.1f - %.1f LMH   (ratio %.3f : 1)\n', J_lo, J_hi, band_ratio);
fprintf('design flux      : %.1f LMH\n', J_des);
fprintf('continuity needs : j* = ceil(%.0f/%.0f) = %d trains online\n', ...
        J_lo, J_hi-J_lo, j_star);
fprintf('                   below %d trains the reachable flow set has gaps\n\n', j_star);

%% ====================== 4.  SWEEP TRAIN COUNT  ========================
Trains     = (1:K_MAX)';
VessPerTr  = zeros(K_MAX,1);   A_train   = zeros(K_MAX,1);
Qf_tr_des  = zeros(K_MAX,1);   Qf_tr_lo  = zeros(K_MAX,1);
Qf_tr_hi   = zeros(K_MAX,1);   Phyd_tr   = zeros(K_MAX,1);
Coverage   = zeros(K_MAX,1);   TurndownOv= zeros(K_MAX,1);
Exact      = strings(K_MAX,1);

for kk = 1:K_MAX
    vpt = n_vess/kk;
    VessPerTr(kk) = vpt;
    Exact(kk)     = string(abs(vpt - round(vpt)) < 1e-9);   % divides evenly?

    A_train(kk)   = A_elem * n_elem * vpt;                  % m2 per train
    Qf_tr_des(kk) = J_des * A_train(kk) * LMH_to_m3d / R_set / 24;   % m3/h
    Qf_tr_lo(kk)  = J_lo  * A_train(kk) * LMH_to_m3d / R_set / 24;
    Qf_tr_hi(kk)  = J_hi  * A_train(kk) * LMH_to_m3d / R_set / 24;
    Phyd_tr(kk)   = dP_max*1e5 * (Qf_tr_des(kk)/3600) / 1000;        % kW per train

    % reachable total flow set = union over j = 1..kk of j*[Qlo, Qhi]
    hi   = kk*Qf_tr_hi(kk);
    grid = linspace(Qf_tr_lo(kk), hi, 20000);
    reach = false(size(grid));
    for j = 1:kk
        reach = reach | (grid >= j*Qf_tr_lo(kk) & grid <= j*Qf_tr_hi(kk));
    end
    Coverage(kk)   = 100*sum(reach)/numel(reach);
    TurndownOv(kk) = hi / Qf_tr_lo(kk);        % full-plant turndown ratio
end

T = table(Trains, VessPerTr, Exact, A_train, Qf_tr_lo, Qf_tr_des, Qf_tr_hi, ...
          Phyd_tr, Coverage, TurndownOv);
T.Properties.VariableNames = {'Trains','VesselsPerTrain','DividesEvenly', ...
    'Area_per_train_m2','Qf_train_min_m3h','Qf_train_des_m3h','Qf_train_max_m3h', ...
    'Phyd_per_train_kW','Coverage_pct','Plant_turndown'};

fprintf('================== TRAIN STAGING: %d vessels ==================\n', n_vess);
disp(T);
fprintf('Coverage_pct = share of the plant flow range the staging can hold\n');
fprintf('steadily.  It reaches 100 %% once k >= j* = %d.\n', j_star);
fprintf('Plant_turndown = k*Qf_max / Qf_min: one train gives %.2f:1,\n', band_ratio);
fprintf('k trains give k times that.\n');
fprintf('==============================================================\n\n');

writetable(T,'train_staging.csv');

%% ============== 5.  FIGURE 1 - THE STAIRCASE  =========================
kk  = K_SHOW;
Qlo = Qf_tr_lo(kk);  Qhi = Qf_tr_hi(kk);  Qde = Qf_tr_des(kk);

figure('Name','train_staging 1/2 - reachable flow','Color','w', ...
       'Position',[80 380 720 520]);
hold on; grid on; box on;

cj = lines(kk);
for j = 1:kk
    % the band this many trains can hold, drawn as a horizontal bar
    patch([j*Qlo j*Qhi j*Qhi j*Qlo], [j-0.32 j-0.32 j+0.32 j+0.32], cj(j,:), ...
          'FaceAlpha',0.35, 'EdgeColor',cj(j,:), 'LineWidth',1.2, ...
          'HandleVisibility','off');
    plot(j*Qde, j, 'o', 'MarkerSize',7, 'MarkerFaceColor','k', ...
         'MarkerEdgeColor','k', 'HandleVisibility','off');
end

% mark the gaps between consecutive stages
for j = 1:kk-1
    if j*Qhi < (j+1)*Qlo
        patch([j*Qhi (j+1)*Qlo (j+1)*Qlo j*Qhi], [0.4 0.4 kk+0.6 kk+0.6], ...
              [0.85 0.25 0.25], 'FaceAlpha',0.12, 'EdgeColor','none', ...
              'HandleVisibility','off');
        text((j*Qhi + (j+1)*Qlo)/2, kk+0.35, 'gap', 'Color',[0.65 0.15 0.15], ...
             'FontSize',8, 'HorizontalAlignment','center');
    end
end

xlabel('Plant feed flow  Q_f  (m^3/h)');
ylabel('Trains online');
yticks(1:kk);  ylim([0.4 kk+0.6]);
xlim([0 kk*Qhi*1.05]);
title(sprintf(['Reachable operating flow - %s\n%d vessels in %d trains ' ...
               '(%.0f vessels each), band %.0f-%.0f LMH, j* = %d'], ...
               cfg_name, n_vess, kk, VessPerTr(kk), J_lo, J_hi, j_star));

%% ============== 6.  FIGURE 2 - COVERAGE vs TRAIN COUNT ================
figure('Name','train_staging 2/2 - coverage','Color','w', ...
       'Position',[830 380 640 520]);
yyaxis left
plot(Trains, Coverage, 'o-', 'LineWidth',1.8, 'MarkerFaceColor','auto');
ylabel('Reachable share of the flow range  (%)');
ylim([0 105]);
yyaxis right
plot(Trains, TurndownOv, 's--', 'LineWidth',1.4);
ylabel('Plant turndown ratio  (max/min)');
grid on; box on;
xline(j_star, 'k:', 'LineWidth',1.4, 'Label',sprintf('j* = %d', j_star), ...
      'LabelOrientation','horizontal');
xlabel('Number of parallel trains');
title(sprintf(['Staging granularity - %s\nband %.0f-%.0f LMH ' ...
               '(single-train turndown %.2f:1)'], ...
               cfg_name, J_lo, J_hi, band_ratio));

fprintf('Saved train_staging.csv\n');