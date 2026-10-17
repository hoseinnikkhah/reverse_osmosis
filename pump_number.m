%% train_staging.m
%  Train staging and per-train pump duty for the WHOLE design selection:
%  every pretreatment configuration x every plant size, in one run.
%
%  A pressure vessel array is built as k identical TRAINS, each with its own
%  high-pressure pump.  Two mechanisms set the operating range:
%
%    within a train : the VFD modulates flux across the design band, a ratio
%                     of only J_hi/J_lo (1.24 to 1.42 by pretreatment)
%    between trains : trains switch on and off, so with j of k trains online
%                     the reachable feed flow is j * [Q_lo, Q_hi]
%
%  Stepping from j to j+1 trains leaves no gap only when
%      j*J_hi >= (j+1)*J_lo    ->    j >= J_lo/(J_hi - J_lo) = j*
%  The gaps BELOW j* stay in the reachable set however many trains are
%  built; they only shrink in absolute size.  They sit at LOW flow, i.e.
%  low power - exactly where PV output is partial - so this is the
%  hydraulic origin of curtailment, not an assumption.
%
%  WHAT DEPENDS ON WHAT
%    j*, Coverage_pct, Plant_turndown : configuration only.  They are
%        ratios, so plant size cannot change them.  Rows sharing a
%        configuration MUST repeat down the table - that is the check.
%    per-train duty (Qf, area, power), MaxGap_m3h : configuration AND size.
%
%  Inputs : design_data.mat, osmotic_pressure_recovery.mat,
%           A_temp_data.mat, salinity_and_temp_mean.mat
%  Output : train_staging.csv, train_staging.mat  (+ two figures)

clear; close all; clc;
fprintf('>>> running train_staging.m  (all configurations x all plant sizes)\n');

%% ====================== 1.  THE SELECTION  ============================
% ---- edit this block only ---------------------------------------------
CFGS = ["Conventional pretreatment"
        "Generic membrane filtration"
        "Well/open intake + UF"
        "UF + B-free"];

VESS     = [94 120 150];    % total vessels per plant
n_elem   = 7;               % elements per vessel
R_set    = 0.35;            % system recovery, fraction
K_MAX    = 12;              % sweep 1..K_MAX trains
A_elem   = 41;              % m2 per element (SW30HRLE-440)
REF_VESS = 120;             % plant size drawn in the staircase figure
% -----------------------------------------------------------------------

%% ====================== 2.  LOAD  =====================================
D  = load('design_data.mat');
O  = load('osmotic_pressure_recovery.mat');
Ad = load('A_temp_data.mat');
S  = load('salinity_and_temp_mean.mat','T_daily_mean','dates');

iR = find(abs(O.recovery - R_set*100) < 1e-9, 1);
assert(~isempty(iR), 'R_set = %.3f is not on the stored recovery grid.', R_set);
pi_avg = O.osmotic_pressure_C_avg(iR,:);
A_T    = interp1(Ad.A_block(1,:), Ad.A_block(2,:), S.T_daily_mean);

LMH_to_m3d = 24/1000;
nC = numel(CFGS);   nV = numel(VESS);

%% =========== 3.  PER-CONFIGURATION CONSTANTS (size independent) =======
J_lo = zeros(nC,1);  J_hi = zeros(nC,1);  J_des = zeros(nC,1);
dPhi = zeros(nC,1);  dPlo = zeros(nC,1);  jstar = zeros(nC,1);
bandR= zeros(nC,1);

for c = 1:nC
    k = find(D.config.Name == CFGS(c), 1);
    assert(~isempty(k), 'Unknown configuration "%s".', CFGS(c));

    band     = D.config.J_design{k};
    J_lo(c)  = min(band);
    J_hi(c)  = max(band);
    J_des(c) = round(((J_lo(c) + J_hi(c))/2)/0.5)*0.5;      % band midpoint

    dP       = pi_avg + J_des(c) ./ A_T;                    % bar [1 x 366]
    dPhi(c)  = max(dP);
    dPlo(c)  = min(dP);

    jstar(c) = ceil(J_lo(c)/(J_hi(c) - J_lo(c)));
    bandR(c) = J_hi(c)/J_lo(c);
end

fprintf('\n============ STAGING CONSTANTS (size independent) ============\n');
fprintf('%-30s %-11s %7s %6s %8s\n','configuration','band LMH','ratio','j*','dP max');
for c = 1:nC
    fprintf('%-30s %4.0f - %-4.0f %7.3f %6d %7.2f bar\n', ...
            CFGS(c), J_lo(c), J_hi(c), bandR(c), jstar(c), dPhi(c));
end
fprintf('j* = ceil(J_lo/(J_hi-J_lo)): trains needed before a step up\n');
fprintf('leaves no gap.  Gaps below j* never close, they only shrink.\n');
fprintf('==============================================================\n\n');

%% ============ 4.  SWEEP: configuration x size x train count ===========
Qlo = zeros(nC,nV,K_MAX);  Qde = zeros(nC,nV,K_MAX);
Qhi = zeros(nC,nV,K_MAX);  Atr = zeros(nC,nV,K_MAX);
Phy = zeros(nC,nV,K_MAX);  Cov = zeros(nC,nV,K_MAX);
Gap = zeros(nC,nV,K_MAX);  Tdn = zeros(nC,nV,K_MAX);

for c = 1:nC
    for v = 1:nV
        for kk = 1:K_MAX
            vpt = VESS(v)/kk;
            A   = A_elem * n_elem * vpt;                    % m2 per train

            Atr(c,v,kk) = A;
            Qlo(c,v,kk) = J_lo(c)  * A * LMH_to_m3d / R_set / 24;   % m3/h
            Qde(c,v,kk) = J_des(c) * A * LMH_to_m3d / R_set / 24;
            Qhi(c,v,kk) = J_hi(c)  * A * LMH_to_m3d / R_set / 24;
            Phy(c,v,kk) = dPhi(c)*1e5 * (Qde(c,v,kk)/3600) / 1000;  % kW, hydraulic

            % reachable total flow = union over j = 1..kk of j*[Qlo,Qhi]
            lo = Qlo(c,v,kk);  hi = Qhi(c,v,kk);
            grid  = linspace(lo, kk*hi, 20000);
            reach = false(size(grid));
            for j = 1:kk
                reach = reach | (grid >= j*lo & grid <= j*hi);
            end
            Cov(c,v,kk) = 100*sum(reach)/numel(reach);
            Tdn(c,v,kk) = kk*hi/lo;

            g = 0;                                           % widest gap
            for j = 1:kk-1
                g = max(g, (j+1)*lo - j*hi);
            end
            Gap(c,v,kk) = max(g, 0);
        end
    end
end

%% ============ 5.  RECOMMENDED TRAIN COUNT PER DESIGN ==================
% smallest k >= j* that divides the vessel count exactly; if none exists
% within K_MAX, fall back to j* itself and flag the inexact split.
k_rec = zeros(nC,nV);  exact_rec = strings(nC,nV);
for c = 1:nC
    for v = 1:nV
        cand = jstar(c):K_MAX;
        ok   = cand(mod(VESS(v), cand) == 0);
        if isempty(ok)
            k_rec(c,v) = jstar(c);   exact_rec(c,v) = "NO";
        else
            k_rec(c,v) = ok(1);      exact_rec(c,v) = "yes";
        end
    end
end

%% ====================== 6.  TABLES  ===================================
% --- full sweep, one row per (configuration, size, train count) ---------
nR = nC*nV*K_MAX;
Configuration=strings(nR,1); Vessels=zeros(nR,1); Trains=zeros(nR,1);
VessPerTrain=zeros(nR,1);    DividesEvenly=strings(nR,1);
Area_train_m2=zeros(nR,1);   Qf_min=zeros(nR,1); Qf_des=zeros(nR,1);
Qf_max=zeros(nR,1);          Phyd_kW=zeros(nR,1);
Coverage_pct=zeros(nR,1);    MaxGap_m3h=zeros(nR,1);
Plant_turndown=zeros(nR,1);  Jstar=zeros(nR,1);

r = 0;
for c = 1:nC
    for v = 1:nV
        for kk = 1:K_MAX
            r = r + 1;
            vpt = VESS(v)/kk;
            Configuration(r) = CFGS(c);
            Vessels(r)       = VESS(v);
            Trains(r)        = kk;
            VessPerTrain(r)  = vpt;
            DividesEvenly(r) = string(abs(vpt-round(vpt)) < 1e-9);
            Area_train_m2(r) = Atr(c,v,kk);
            Qf_min(r)        = Qlo(c,v,kk);
            Qf_des(r)        = Qde(c,v,kk);
            Qf_max(r)        = Qhi(c,v,kk);
            Phyd_kW(r)       = Phy(c,v,kk);
            Coverage_pct(r)  = Cov(c,v,kk);
            MaxGap_m3h(r)    = Gap(c,v,kk);
            Plant_turndown(r)= Tdn(c,v,kk);
            Jstar(r)         = jstar(c);
        end
    end
end

T = table(Configuration, Vessels, Trains, VessPerTrain, DividesEvenly, ...
          Area_train_m2, Qf_min, Qf_des, Qf_max, Phyd_kW, ...
          Coverage_pct, MaxGap_m3h, Plant_turndown, Jstar);
writetable(T,'train_staging.csv');

% --- the pump specification, one row per design at its recommended k ----
fprintf('=============== PUMP SPECIFICATION PER DESIGN ===============\n');
fprintf('%-30s %5s %6s %7s %9s %9s %9s %9s %6s\n', ...
        'configuration','vess','trains','v/train','Qf min','Qf des','Qf max','P_hyd','exact');
fprintf('%-30s %5s %6s %7s %9s %9s %9s %9s %6s\n', ...
        '','','','','m3/h','m3/h','m3/h','kW','');
for c = 1:nC
    for v = 1:nV
        kk = k_rec(c,v);
        fprintf('%-30s %5d %6d %7.1f %9.1f %9.1f %9.1f %9.1f %6s\n', ...
                CFGS(c), VESS(v), kk, VESS(v)/kk, ...
                Qlo(c,v,kk), Qde(c,v,kk), Qhi(c,v,kk), Phy(c,v,kk), exact_rec(c,v));
    end
end
fprintf('Head is the same for every row: %.0f - %.0f m.\n', ...
        min(dPlo)*1e5/(1025*9.81), max(dPhi)*1e5/(1025*9.81));
fprintf('Recommended trains = smallest k >= j* that divides the vessel\n');
fprintf('count exactly.  "exact = NO" means no such k exists up to %d.\n', K_MAX);
fprintf('=============================================================\n\n');

save('train_staging.mat','T','CFGS','VESS','n_elem','R_set', ...
     'J_lo','J_hi','J_des','dPhi','dPlo','jstar','bandR', ...
     'Qlo','Qde','Qhi','Atr','Phy','Cov','Gap','Tdn','k_rec');

%% ====== 7.  FIGURE 1 - STAIRCASES, ONE PANEL PER CONFIGURATION ========
v_ref = find(VESS == REF_VESS, 1);
assert(~isempty(v_ref), 'REF_VESS = %g is not in VESS.', REF_VESS);

figure('Name','train_staging 1/2 - reachable flow','Color','w', ...
       'Position',[60 200 1120 720]);
for c = 1:nC
    kk = min(K_MAX, jstar(c)+2);          % enough stages to show continuity
    lo = Qlo(c,v_ref,kk);  hi = Qhi(c,v_ref,kk);  de = Qde(c,v_ref,kk);

    ax = subplot(2,2,c);  hold(ax,'on');  grid(ax,'on');  box(ax,'on');
    cj = lines(kk);
    for j = 1:kk
        patch(ax, [j*lo j*hi j*hi j*lo], [j-0.32 j-0.32 j+0.32 j+0.32], ...
              cj(j,:), 'FaceAlpha',0.35, 'EdgeColor',cj(j,:), 'LineWidth',1.1);
        plot(ax, j*de, j, 'o', 'MarkerSize',6, 'MarkerFaceColor','k', ...
             'MarkerEdgeColor','k');
    end
    for j = 1:kk-1
        if j*hi < (j+1)*lo
            patch(ax, [j*hi (j+1)*lo (j+1)*lo j*hi], ...
                  [0.4 0.4 kk+0.6 kk+0.6], [0.85 0.25 0.25], ...
                  'FaceAlpha',0.12, 'EdgeColor','none');
        end
    end
    xlabel(ax,'Plant feed flow  Q_f  (m^3/h)');
    ylabel(ax,'Trains online');
    yticks(ax,1:kk);  ylim(ax,[0.4 kk+0.6]);  xlim(ax,[0 kk*hi*1.05]);
    title(ax, sprintf('%s\nband %.0f-%.0f LMH,  j* = %d,  %d vessels', ...
          CFGS(c), J_lo(c), J_hi(c), jstar(c), REF_VESS), 'FontSize',9);
end
sgtitle(sprintf(['Reachable operating flow - red bands are flows the plant ' ...
                 'cannot hold\n%d vessels, %d elements per vessel, R = %.0f %%'], ...
                 REF_VESS, n_elem, R_set*100));

%% ====== 8.  FIGURE 2 - COVERAGE AND TURNDOWN, ALL CONFIGURATIONS ======
% Both are ratios, so they do not depend on plant size: one curve per
% configuration covers all three sizes.
figure('Name','train_staging 2/2 - staging granularity','Color','w', ...
       'Position',[1200 200 720 720]);
col = lines(nC);

subplot(2,1,1); hold on; grid on; box on;
for c = 1:nC
    plot(1:K_MAX, squeeze(Cov(c,1,:)), 'o-', 'Color',col(c,:), 'LineWidth',1.7, ...
         'MarkerFaceColor',col(c,:), 'MarkerSize',5, ...
         'DisplayName',sprintf('%s  (j* = %d)', CFGS(c), jstar(c)));
    xline(jstar(c), ':', 'Color',col(c,:), 'LineWidth',1.2, 'HandleVisibility','off');
end
xlabel('Number of parallel trains');
ylabel('Reachable share of flow range  (%)');
ylim([0 105]);  xlim([1 K_MAX]);
title('Coverage - independent of plant size (it is a ratio)');
legend('Location','southeast','Box','off','FontSize',8);

subplot(2,1,2); hold on; grid on; box on;
for c = 1:nC
    plot(1:K_MAX, squeeze(Tdn(c,1,:)), 's--', 'Color',col(c,:), 'LineWidth',1.5, ...
         'DisplayName',sprintf('%s  (%.2f:1 per train)', CFGS(c), bandR(c)));
end
xlabel('Number of parallel trains');
ylabel('Plant turndown ratio  (max/min)');
xlim([1 K_MAX]);
title('Turndown - read together with coverage above');
legend('Location','northwest','Box','off','FontSize',8);

fprintf('Saved train_staging.csv and train_staging.mat\n');