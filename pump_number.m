clear; close all; clc;
fprintf('>>> running train_staging.m  (all configurations x all plant sizes)\n');

%% ====================== 1.  THE SELECTION  ============================
% ---- edit this block only ---------------------------------------------
CFGS = ["Conventional pretreatment"
        "Generic membrane filtration"
        "Well/open intake + UF"
        "UF + B-free"];

VESS      = [96 120 150];    % total vessels per plant
n_elem    = 7;               % elements per vessel
R_set     = 0.35;            % system recovery, fraction
K_MAX     = 16;              % sweep 1..K_MAX trains
A_elem    = 41;              % m2 per element (SW30HRLE-440)
rho_sw    = 1025;  g = 9.81; % seawater density, gravity (bar -> m head)
SAVE_FIGS = true;            % also write each figure as a PNG
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

bar2m = 1e5/(rho_sw*g);
nC = numel(CFGS);   nV = numel(VESS);

%% =========== 3.  PER-CONFIGURATION CONSTANTS (size independent) =======
J_lo = zeros(nC,1);  J_hi = zeros(nC,1);  J_des = zeros(nC,1);
dPhi = zeros(nC,1);  dPlo = zeros(nC,1);  jstar = zeros(nC,1);
bandR= zeros(nC,1);

for c = 1:nC
    kcfg = find(D.config.Name == CFGS(c), 1);
    assert(~isempty(kcfg), 'Unknown configuration "%s".', CFGS(c));

    band     = D.config.J_design{kcfg};
    J_lo(c)  = min(band);
    J_hi(c)  = max(band);
    J_des(c) = round(((J_lo(c) + J_hi(c))/2)/0.5)*0.5;      % band midpoint

    dP       = pi_avg + J_des(c) ./ A_T;                    % bar [1 x 366]
    dPhi(c)  = max(dP);                                     % worst day
    dPlo(c)  = min(dP);                                     % best day

    jstar(c) = ceil(J_lo(c)/(J_hi(c) - J_lo(c)));
    bandR(c) = J_hi(c)/J_lo(c);
end

fprintf('\n============ STAGING CONSTANTS (size independent) ============\n');
fprintf('%-30s %-11s %7s %6s %9s %9s\n', ...
        'configuration','band LMH','ratio','j*','dP max','head max');
for c = 1:nC
    fprintf('%-30s %4.0f - %-4.0f %7.3f %6d %7.2f b %7.0f m\n', ...
            CFGS(c), J_lo(c), J_hi(c), bandR(c), jstar(c), ...
            dPhi(c), dPhi(c)*bar2m);
end
fprintf('j* = ceil(J_lo/(J_hi-J_lo)): trains needed before a step up\n');
fprintf('leaves no gap.  Gaps below j* never close, they only shrink.\n');
fprintf('Head is the same for every train in a plant - flow divides,\n');
fprintf('pressure does not.\n');
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
            Qlo(c,v,kk) = J_lo(c)  * A / 1000 / R_set;      % m3/h  (LMH -> m3/h)
            Qde(c,v,kk) = J_des(c) * A / 1000 / R_set;
            Qhi(c,v,kk) = J_hi(c)  * A / 1000 / R_set;
            Phy(c,v,kk) = dPhi(c)*1e5 * (Qde(c,v,kk)/3600) / 1000;  % kW, hydraulic

            % reachable total flow = union over j = 1..kk of j*[Qlo,Qhi]
            lo = Qlo(c,v,kk);  hi = Qhi(c,v,kk);
            qgrid = linspace(lo, kk*hi, 20000);
            reach = false(size(qgrid));
            for j = 1:kk
                reach = reach | (qgrid >= j*lo & qgrid <= j*hi);
            end
            Cov(c,v,kk) = 100*sum(reach)/numel(reach);
            Tdn(c,v,kk) = kk*hi/lo;

            gmax = 0;                                        % widest gap
            for j = 1:kk-1
                gmax = max(gmax, (j+1)*lo - j*hi);
            end
            Gap(c,v,kk) = max(gmax, 0);
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
Head_max_m=zeros(nR,1);      Recommended=strings(nR,1);

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
            Head_max_m(r)    = dPhi(c)*bar2m;
            Recommended(r)   = string(kk == k_rec(c,v));
        end
    end
end

T = table(Configuration, Vessels, Trains, VessPerTrain, DividesEvenly, ...
          Area_train_m2, Qf_min, Qf_des, Qf_max, Head_max_m, Phyd_kW, ...
          Coverage_pct, MaxGap_m3h, Plant_turndown, Jstar, Recommended);
writetable(T,'train_staging.csv');

% --- the pump specification, one row per design at its recommended k ----
Spec = T(T.Recommended == "true", ...
         {'Configuration','Vessels','Trains','VessPerTrain', ...
          'Qf_min','Qf_des','Qf_max','Head_max_m','Phyd_kW', ...
          'Coverage_pct','MaxGap_m3h','DividesEvenly'});
writetable(Spec,'train_staging_spec.csv');

fprintf('=============== PUMP SPECIFICATION PER DESIGN ===============\n');
fprintf('%-30s %5s %6s %7s %8s %8s %8s %8s %7s\n', ...
        'configuration','vess','trains','v/train','Qf min','Qf des','Qf max','P_hyd','exact');
fprintf('%-30s %5s %6s %7s %8s %8s %8s %8s %7s\n', ...
        '','','','','m3/h','m3/h','m3/h','kW','');
for c = 1:nC
    for v = 1:nV
        kk = k_rec(c,v);
        fprintf('%-30s %5d %6d %7.2f %8.1f %8.1f %8.1f %8.1f %7s\n', ...
                CFGS(c), VESS(v), kk, VESS(v)/kk, ...
                Qlo(c,v,kk), Qde(c,v,kk), Qhi(c,v,kk), Phy(c,v,kk), exact_rec(c,v));
    end
end
fprintf('Head for every row: %.0f - %.0f m  (%.2f - %.2f bar).\n', ...
        min(dPlo)*bar2m, max(dPhi)*bar2m, min(dPlo), max(dPhi));
fprintf('Recommended trains = smallest k >= j* that divides the vessel\n');
fprintf('count exactly, searched up to k = %d.\n', K_MAX);
fprintf('=============================================================\n\n');

save('train_staging.mat','T','Spec','CFGS','VESS','n_elem','R_set', ...
     'J_lo','J_hi','J_des','dPhi','dPlo','jstar','bandR','bar2m', ...
     'Qlo','Qde','Qhi','Atr','Phy','Cov','Gap','Tdn','k_rec','K_MAX');

%% ====== 7.  STAIRCASE FIGURES - ONE PER PLANT SIZE ====================
% Each figure: 2 x 2 panels, one per pretreatment configuration.
figH = gobjects(nV,1);
for v = 1:nV
    figH(v) = figure('Name',sprintf('train_staging - reachable flow, %d vessels',VESS(v)), ...
                     'Color','w','Position',[60 120 1120 740]);
    for c = 1:nC
        % show enough stages to see both the gaps and the continuous region
        kk = min(K_MAX, max(k_rec(c,v), jstar(c)+2));
        lo = Qlo(c,v,kk);  hi = Qhi(c,v,kk);  de = Qde(c,v,kk);

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
        % mark the recommended train count
        yline(ax, k_rec(c,v), 'k--', 'LineWidth',1.2, ...
              'Label',sprintf('recommended k = %d', k_rec(c,v)), ...
              'LabelHorizontalAlignment','left', 'FontSize',7);

        xlabel(ax,'Plant feed flow  Q_f  (m^3/h)');
        ylabel(ax,'Trains online');
        yticks(ax,1:kk);  ylim(ax,[0.4 kk+0.6]);  xlim(ax,[0 kk*hi*1.05]);
        title(ax, sprintf('%s\nband %.0f-%.0f LMH,  j* = %d,  %.1f v/train at k=%d', ...
              CFGS(c), J_lo(c), J_hi(c), jstar(c), ...
              VESS(v)/k_rec(c,v), k_rec(c,v)), 'FontSize',9);
    end
    sgtitle(sprintf(['Reachable operating flow - red bands cannot be held\n' ...
                     '%d vessels, %d elements per vessel, R = %.0f %%, head %.0f m'], ...
                     VESS(v), n_elem, R_set*100, max(dPhi)*bar2m));
end

%% ====== 8.  COVERAGE AND TURNDOWN (size independent) ==================
figCov = figure('Name','train_staging - staging granularity','Color','w', ...
                'Position',[1200 120 760 740]);
col = lines(nC);

subplot(2,1,1); hold on; grid on; box on;
for c = 1:nC
    plot(1:K_MAX, squeeze(Cov(c,1,:)), 'o-', 'Color',col(c,:), 'LineWidth',1.7, ...
         'MarkerFaceColor',col(c,:), 'MarkerSize',4.5, ...
         'DisplayName',sprintf('%s  (j* = %d)', CFGS(c), jstar(c)));
    xline(jstar(c), ':', 'Color',col(c,:), 'LineWidth',1.2, 'HandleVisibility','off');
end
xlabel('Number of parallel trains  k');
ylabel('Reachable share of flow range  (%)');
ylim([0 105]);  xlim([1 K_MAX]);
title(['Coverage - a ratio, so identical for 96, 120 and 150 vessels' newline ...
       '(k = 1 reads 100 % only because its span is one band)']);
legend('Location','southeast','Box','off','FontSize',8);

subplot(2,1,2); hold on; grid on; box on;
for c = 1:nC
    plot(1:K_MAX, squeeze(Tdn(c,1,:)), 's--', 'Color',col(c,:), 'LineWidth',1.5, ...
         'DisplayName',sprintf('%s  (%.2f:1 per train)', CFGS(c), bandR(c)));
end
xlabel('Number of parallel trains  k');
ylabel('Plant turndown ratio  (max/min)');
xlim([1 K_MAX]);
title('Turndown - read together with coverage above');
legend('Location','northwest','Box','off','FontSize',8);

%% ====== 9.  WIDEST GAP - THE SIZE-DEPENDENT GRANULARITY ==============
% Coverage is a ratio; the gap in m3/h is not.  This is the figure that
% differs between plant sizes, and it is what feeds curtailment.
figGap = figure('Name','train_staging - widest unreachable flow band','Color','w', ...
                'Position',[200 60 1120 420]);
for v = 1:nV
    ax = subplot(1,nV,v);  hold(ax,'on');  grid(ax,'on');  box(ax,'on');
    for c = 1:nC
        plot(ax, 1:K_MAX, squeeze(Gap(c,v,:)), 'o-', 'Color',col(c,:), ...
             'LineWidth',1.5, 'MarkerSize',4, 'MarkerFaceColor',col(c,:), ...
             'DisplayName',CFGS(c));
        plot(ax, k_rec(c,v), Gap(c,v,k_rec(c,v)), 'p', 'MarkerSize',13, ...
             'MarkerFaceColor',col(c,:), 'MarkerEdgeColor','k', ...
             'HandleVisibility','off');
    end
    xlabel(ax,'Number of parallel trains  k');
    ylabel(ax,'Widest unreachable band  (m^3/h)');
    xlim(ax,[1 K_MAX]);
    title(ax, sprintf('%d vessels', VESS(v)));
    if v == 1
        legend(ax,'Location','northeast','Box','off','FontSize',7);
    end
end
sgtitle('Widest gap in reachable flow - stars mark the recommended train count');

%% ====================== 10.  SAVE FIGURES  ============================
if SAVE_FIGS
    allF  = [figH(:); figCov; figGap];
    names = [arrayfun(@(x) sprintf('train_staging_%dv.png',x), VESS(:), ...
                      'UniformOutput',false)
             {'train_staging_coverage.png'}
             {'train_staging_maxgap.png'}];
    for f = 1:numel(allF)
        if exist('exportgraphics','file')
            exportgraphics(allF(f), names{f}, 'Resolution', 200);
        else
            saveas(allF(f), names{f});
        end
    end
    fprintf('Saved %d figures as PNG.\n', numel(allF));
end

fprintf('Saved train_staging.csv, train_staging_spec.csv, train_staging.mat\n');