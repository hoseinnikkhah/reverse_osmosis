%% optimizeDesign.m
%  Techno-economic optimisation of the PV-SWRO plant: PV capacity, SWRO
%  capacity and operating strategy, evaluated on an hourly dispatch for
%  every candidate design.
%
%  DECISION VARIABLES
%    P        installed PV capacity, kWp                       (P_GRID)
%    k        number of identical SWRO trains, each 32 vessels x 7 elements
%             with its own HP pump and PX.  k = 3 is the 96-vessel base design.
%             Valid because every operating constraint is intensive (see
%             design-space.md, "Scale invariance"): Pel, okSpd and Qp per
%             train do not depend on how many trains are installed.
%    strategy hourly operating rule                             (STRAT)
%      max water   : any train count, any flux, most permeate each hour
%      min run T h : as above, but a train level may only be used inside a
%                    window where it can be held for at least T hours
%                    (fewer start/stop cycles, less membrane and pump wear)
%      fixed flux  : trains switch on/off at the design flux only - the
%                    plant without flux modulation, to show what the VFD buys
%    recovery R becomes an hourly control variable automatically when
%    ERDFILES lists erdOperating results for the same train at several R.
%
%  OBJECTIVES
%    LCOW            (Qudah et al. 2025 Eq. 4, costs from lcowEconomics.m)
%    PV utilisation  used / generated - the second objective of the study
%    Delivered LCOW  annual cost / min(production, demand).  With no storage
%                    and no water sales, production above demand has no
%                    value, so this is the metric that sizes the plant for a
%                    given water demand.  Without it, more trains always win.
%
%  SEARCH
%    Exhaustive over the grid.  The dispatch is vectorised over the 8760
%    hours, so the full grid runs in well under a minute and cannot miss
%    the optimum the way a gradient search on integer k could.
%
%  Inputs : erd_operating_*.mat, pv_generation.mat, lcow_<tag>.mat
%  Output : optimize_<tag>.mat, optimize_grid_<tag>.csv, report, six figures

clear; close all; clc;
fprintf('>>> running optimizeDesign.m\n');

%% ====================== 1.  SETTINGS  =================================
% ---- edit this block only ---------------------------------------------
ERDFILES = {'erd_operating_Conv_7e_96v_R35_k3.mat'};
           % one file per recovery set point, all for the SAME train.
           % With several files the dispatch chooses R hour by hour.
PVFILE   = 'pv_generation.mat';
LCOWFILE = 'lcow_Conv_7e_96v_R35_k3.mat';    % run lcowEconomics.m first

BASE_YEAR = 2021;               % year for maps, Pareto front, strategies
YEARS     = [2020 2021 2022];   % robustness and demand sizing

P_GRID = 250:250:10000;         % kWp
K_SET  = 1:6;                   % trains

STRAT = struct( ...
    'name',   {'max water', 'min run 3 h', 'fixed flux'}, ...
    'T_on',   {1,           3,             1}, ...
    'fixedJ', {false,       false,         true});
BASE_STRAT = 1;

DEMAND  = [0.5 1.0 1.5 2.0 2.5] * 1e6;   % m3/yr delivered-water targets
A_SCALE = 1.0;     % SWRO CAPEX ~ capacity^A_SCALE.  1 = linear, no economy
                   % of scale [EST] -> fit from Caldera & Breyer 2017
% -----------------------------------------------------------------------

%% ====================== 2.  LOAD  =====================================
L = load(LCOWFILE, 'p', 'C_RO', 'Cap', 'COST_YEAR', 'OPEX_METHOD');
p = L.p;

nF = numel(ERDFILES);
tr = struct('J',[],'R',[],'Qp',[],'Pel',[],'ok',[],'isDesign',[]);
for f = 1:nF
    E = load(ERDFILES{f});
    if f == 1
        E1 = E;
    else
        assert(isequal(double([E.d.n_elem E.d.n_vess E.k_trains]), ...
                       double([E1.d.n_elem E1.d.n_vess E1.k_trains])) && ...
               isequal(size(E.Pel), size(E1.Pel)), ...
               'optimizeDesign: %s is not the same train as %s', ERDFILES{f}, ERDFILES{1});
    end
    J  = double(E.Jset(:));
    nJ = numel(J);
    [~, jd] = min(abs(J - double(E.d.J_design)));
    tr.J        = [tr.J;   J];
    tr.R        = [tr.R;   repmat(double(E.d.R_set), nJ, 1)];
    tr.Qp       = [tr.Qp;  double(E.Qp_set(:))];
    tr.Pel      = [tr.Pel; double(E.Pel)];
    tr.ok       = [tr.ok;  logical(E.okSpd)];
    tr.isDesign = [tr.isDesign; (1:nJ)' == jd];
end

kb     = double(E1.k_trains);
nEl_tr = double(E1.d.n_elem) * double(E1.d.n_vess) / kb;
Cap_tr = interp1(double(E1.Jset(:)), double(E1.Qp_set(:)), double(E1.d.J_design)) * 24;
Cap_k  = K_SET * Cap_tr;                                  % m3/d
C_RO_k = L.C_RO * (Cap_k / L.Cap) .^ A_SCALE;             % USD
nEl_k  = K_SET * nEl_tr;

V  = load(PVFILE);  pv = V.pv;
pu_max = max(pv.p_unit);

%% ============ 3.  DAY-OF-YEAR JOIN  (as pvDispatch.m)  ================
doy_sw = day(E1.dates(:), 'dayofyear');
map = nan(365,1);
for dd = 1:365
    kk = find(doy_sw == dd, 1, 'first');
    if ~isempty(kk), map(dd) = kk; end
end
assert(~any(isnan(map)), 'optimizeDesign: seawater record misses days %s', ...
       mat2str(find(isnan(map))'));

nYr = numel(YEARS);
PU  = cell(nYr,1);  SWI = cell(nYr,1);
for y = 1:nYr
    keep = year(pv.time) == YEARS(y);
    assert(sum(keep) > 8000, 'optimizeDesign: %d is not a full year in %s', YEARS(y), PVFILE);
    doy = day(pv.time(keep), 'dayofyear');
    doy(doy == 366) = 365;
    PU{y}  = pv.p_unit(keep);
    SWI{y} = map(doy);
end
yb = find(YEARS == BASE_YEAR);
assert(~isempty(yb), 'optimizeDesign: BASE_YEAR must be one of YEARS');

%% ============ 4.  GRID: ALL STRATEGIES, BASE YEAR  ====================
nS = numel(STRAT);  nK = numel(K_SET);  nP = numel(P_GRID);
G = struct();
fl = {'LCOW','water','feed','used','gen','util','SEC','starts','hours','Rmean'};
for q = 1:numel(fl), G.(fl{q}) = nan(nS, nK, nP); end

t0 = tic;
for s = 1:nS
    sel = true(size(tr.J));
    if STRAT(s).fixedJ, sel = tr.isDesign; end
    for ik = 1:nK
        for ip = 1:nP
            S = dispatchYear(P_GRID(ip), K_SET(ik), tr, sel, PU{yb}, SWI{yb}, STRAT(s).T_on);
            G.LCOW(s,ik,ip) = lcowDesign(p, P_GRID(ip), Cap_k(ik), C_RO_k(ik), nEl_k(ik), ...
                                         S, pu_max, L.OPEX_METHOD);
            for q = 2:numel(fl), G.(fl{q})(s,ik,ip) = S.(fl{q}); end
        end
    end
    fprintf('strategy "%s" done (%.0f s)\n', STRAT(s).name, toc(t0));
end

%% ============ 5.  ALL YEARS, BASE STRATEGY  ===========================
WY = nan(nYr, nK, nP);  CY = WY;  LY = WY;  UY = WY;
sel = true(size(tr.J));
if STRAT(BASE_STRAT).fixedJ, sel = tr.isDesign; end
for y = 1:nYr
    for ik = 1:nK
        for ip = 1:nP
            if y == yb
                S.water = G.water(BASE_STRAT,ik,ip);  S.feed = G.feed(BASE_STRAT,ik,ip);
                S.util  = G.util(BASE_STRAT,ik,ip);
            else
                S = dispatchYear(P_GRID(ip), K_SET(ik), tr, sel, PU{y}, SWI{y}, ...
                                 STRAT(BASE_STRAT).T_on);
            end
            [LY(y,ik,ip), CY(y,ik,ip)] = lcowDesign(p, P_GRID(ip), Cap_k(ik), C_RO_k(ik), ...
                                         nEl_k(ik), S, pu_max, L.OPEX_METHOD);
            WY(y,ik,ip) = S.water;  UY(y,ik,ip) = S.util;
        end
    end
end
fprintf('robustness years done (%.0f s)\n', toc(t0));

%% ============ 6.  OPTIMA  =============================================
Lb = squeeze(G.LCOW(BASE_STRAT,:,:));  Ub = squeeze(G.util(BASE_STRAT,:,:));
Wb = squeeze(G.water(BASE_STRAT,:,:));
Lb = reshape(Lb, nK, nP);  Ub = reshape(Ub, nK, nP);  Wb = reshape(Wb, nK, nP);

[~, ipk] = min(Lb, [], 2);                       % best PV size for each k
PoptK = P_GRID(ipk)';
LoptK = Lb(sub2ind(size(Lb), (1:nK)', ipk));
UoptK = Ub(sub2ind(size(Ub), (1:nK)', ipk));
ratioK = PoptK ./ (Cap_k(:)/24);                 % kWp per m3/h of capacity

nD = numel(DEMAND);
Dopt = struct('D', num2cell(DEMAND(:)));
for iD = 1:nD
    Ldel = reshape(mean(CY ./ min(WY, DEMAND(iD)), 1), nK, nP);
    Ldel(reshape(any(WY <= 0, 1), nK, nP)) = Inf;
    [Lmin, idx] = min(Ldel(:));
    [ik, ip] = ind2sub(size(Ldel), idx);
    Dopt(iD).k = K_SET(ik);  Dopt(iD).P = P_GRID(ip);  Dopt(iD).LCOWdel = Lmin;
    Dopt(iD).Wmin  = min(WY(:,ik,ip));
    Dopt(iD).util  = Ub(ik,ip);
    Dopt(iD).ratio = P_GRID(ip) / (Cap_k(ik)/24);
    Dopt(iD).edge  = ip == nP || ik == nK;
    Dopt(iD).unmet = Dopt(iD).Wmin < DEMAND(iD);
end

x = Lb(:);  u = Ub(:);
nd = isfinite(x);
for ii = find(nd)'
    nd(ii) = ~any((x <= x(ii) & u >= u(ii)) & (x < x(ii) | u > u(ii)));
end
[ikP, ipP] = ind2sub(size(Lb), find(nd));

ik3 = find(K_SET == kb, 1);
assert(~isempty(ik3), 'optimizeDesign: K_SET must contain the base train count %d', kb);
stratTab = zeros(nS, 6);
for s = 1:nS
    Ls = reshape(G.LCOW(s,ik3,:), 1, nP);
    [Lm, ip] = min(Ls);
    stratTab(s,:) = [P_GRID(ip) Lm G.water(s,ik3,ip) G.util(s,ik3,ip) ...
                     G.starts(s,ik3,ip) G.SEC(s,ik3,ip)];
end

%% ====================== 7.  REPORT  ===================================
sep = repmat('=',1,82);  dash = repmat('-',1,82);
fprintf('\n%s\nOPTIMISATION, solar year %d, costs USD %d, OPEX %s, A_SCALE = %.2f\n%s\n', ...
        sep, BASE_YEAR, L.COST_YEAR, L.OPEX_METHOD, A_SCALE, dash);
fprintf('train : %d vessels x %d elements, %.0f m3/d design;  recovery set(s): %s\n', ...
        double(E1.d.n_vess)/kb, double(E1.d.n_elem), Cap_tr, mat2str(unique(tr.R)'));

fprintf('\n[1] best PV size for each SWRO size  (strategy "%s")\n', STRAT(BASE_STRAT).name);
fprintf('%4s %9s %9s %10s %7s %8s %10s\n', 'k', 'm3/d', 'P kWp', 'kWp/(m3/h)', 'LCOW', 'util %', 'water m3');
for ik = 1:nK
    fprintf('%4d %9.0f %9d %10.1f %7.3f %8.1f %10.0f%s\n', K_SET(ik), Cap_k(ik), PoptK(ik), ...
            ratioK(ik), LoptK(ik), 100*UoptK(ik), Wb(ik,ipk(ik)), ...
            repmat('  <- P at grid edge', 1, double(ipk(ik)==1 || ipk(ik)==nP)));
end
fprintf('=> the optimal PV/SWRO ratio is %.1f - %.1f kWp per m3/h of capacity\n', ...
        min(ratioK), max(ratioK));
fprintf('   With A_SCALE = 1 LCOW falls slowly with k only because more trains\n');
fprintf('   absorb PV in finer power steps.  SWRO size is set by demand, below.\n');

fprintf('\n[2] demand-driven design  (delivered LCOW, mean of %s, demand met in worst year)\n', ...
        mat2str(YEARS));
fprintf('%10s %4s %8s %10s %9s %12s %8s\n', 'demand m3', 'k', 'P kWp', 'kWp/(m3/h)', ...
        'LCOW del', 'worst yr m3', 'util %');
for iD = 1:nD
    fprintf('%10.0f %4d %8d %10.1f %9.3f %12.0f %8.1f%s%s\n', Dopt(iD).D, Dopt(iD).k, Dopt(iD).P, ...
            Dopt(iD).ratio, Dopt(iD).LCOWdel, Dopt(iD).Wmin, 100*Dopt(iD).util, ...
            repmat('  <- at grid edge', 1, double(Dopt(iD).edge)), ...
            repmat('  <- demand not met', 1, double(Dopt(iD).unmet)));
end

fprintf('\n[3] operating strategy at k = %d (each with its own best PV size)\n', kb);
fprintf('%-14s %8s %7s %11s %7s %9s %7s\n', 'strategy', 'P kWp', 'LCOW', 'water m3', ...
        'util %', 'starts/yr', 'SEC');
for s = 1:nS
    fprintf('%-14s %8d %7.3f %11.0f %7.1f %9d %7.3f\n', STRAT(s).name, stratTab(s,1), ...
            stratTab(s,2), stratTab(s,3), 100*stratTab(s,4), round(stratTab(s,5)), stratTab(s,6));
end
fprintf('   LCOW change against "%s":', STRAT(BASE_STRAT).name);
for s = setdiff(1:nS, BASE_STRAT)
    fprintf('  %s %+.1f %%;', STRAT(s).name, 100*(stratTab(s,2)/stratTab(BASE_STRAT,2) - 1));
end
fprintf('\n');

fprintf('\n[4] robustness at k = %d\n', kb);
for y = 1:nYr
    Ly3 = reshape(LY(y,ik3,:), 1, nP);
    [Lm, ip] = min(Ly3);
    fprintf('   solar %d : best P %5d kWp, LCOW %.3f USD/m3\n', YEARS(y), P_GRID(ip), Lm);
end

fprintf('\n[5] Pareto front, LCOW vs PV utilisation: %d non-dominated designs\n', nnz(nd));
[~, o] = sort(x(nd));
xs = x(nd);  us = u(nd);
for ii = o(1:min(8, numel(o)))'
    fprintf('   k = %d, P = %5d kWp : LCOW %.3f, utilisation %.1f %%\n', ...
            K_SET(ikP(ii)), P_GRID(ipP(ii)), xs(ii), 100*us(ii));
end
fprintf('%s\n\n', sep);

%% ====================== 8.  FIGURES  ==================================
Lmin = min(Lb(:));
figure('Name','opt 1/6 - LCOW design map','Color','w','Position',[40 420 820 500]);
Lc = Lb;  Lc(~isfinite(Lc)) = NaN;  Lc = min(Lc, 2*Lmin);
contourf(P_GRID, K_SET, Lc, 24, 'LineColor', 'none');  hold on;
cb = colorbar;  cb.Label.String = sprintf('LCOW  (USD_{%d}/m^3), capped at 2x min', L.COST_YEAR);
lev = DEMAND;  if numel(lev) == 1, lev = [lev lev]; end
[cc, hc] = contour(P_GRID, K_SET, Wb, lev, 'w--', 'LineWidth', 1.1);
clabel(cc, hc, 'Color', 'w', 'FontSize', 8);
h2 = plot(PoptK, K_SET, 'k-o', 'LineWidth', 1.6, 'MarkerFaceColor', 'k');
h3 = plot([Dopt.P], [Dopt.k], 'p', 'MarkerSize', 13, 'MarkerFaceColor', 'y', 'MarkerEdgeColor', 'k');
xlabel('installed PV capacity  (kWp)');  ylabel('SWRO trains  k');  yticks(K_SET);
legend([hc h2 h3], {'annual permeate (m^3)', 'best P for each k', 'demand-driven optimum'}, ...
       'Location', 'southeast', 'Box', 'off');
title('LCOW over PV and SWRO capacity');

figure('Name','opt 2/6 - utilisation map','Color','w','Position',[880 420 820 500]);
contourf(P_GRID, K_SET, 100*Ub, 20, 'LineColor', 'none');  hold on;
cb = colorbar;  cb.Label.String = 'PV utilisation  (%)';
plot(PoptK, K_SET, 'k-o', 'LineWidth', 1.6, 'MarkerFaceColor', 'k');
xlabel('installed PV capacity  (kWp)');  ylabel('SWRO trains  k');  yticks(K_SET);
title('Utilisation falls as PV outgrows the plant');

figure('Name','opt 3/6 - Pareto front','Color','w','Position',[40 40 620 460]);
hold on;  grid on;  box on;
cols = lines(nK);
for ik = 1:nK
    ok_ = isfinite(Lb(ik,:)) & Lb(ik,:) < 2*Lmin;
    scatter(100*Ub(ik,ok_), Lb(ik,ok_), 14, cols(ik,:), 'filled', 'MarkerFaceAlpha', 0.5);
end
[us2, o2] = sort(100*us);  xs2 = xs(o2);
plot(us2, xs2, 'k-', 'LineWidth', 1.8);
xlabel('PV utilisation  (%)');  ylabel(sprintf('LCOW  (USD_{%d}/m^3)', L.COST_YEAR));
legend([arrayfun(@(k) sprintf('k = %d', k), K_SET, 'uni', 0), {'Pareto front'}], ...
       'Location', 'northwest', 'Box', 'off');
title('Cheapest water and best use of PV are not the same design');

figure('Name','opt 4/6 - one design ratio','Color','w','Position',[680 40 620 460]);
hold on;  grid on;  box on;
for ik = 1:nK
    plot(P_GRID / (Cap_k(ik)/24), Lb(ik,:), '-', 'LineWidth', 1.5, 'Color', cols(ik,:));
end
ylim([0.95*Lmin 2*Lmin]);
xlabel('PV / SWRO ratio  (kWp per m^3/h of capacity)');
ylabel(sprintf('LCOW  (USD_{%d}/m^3)', L.COST_YEAR));
legend(arrayfun(@(k) sprintf('k = %d', k), K_SET, 'uni', 0), 'Location', 'northeast', 'Box', 'off');
title('Curves collapse: the ratio, not the size, sets LCOW');

figure('Name','opt 5/6 - operating strategy','Color','w','Position',[1320 40 620 460]);
subplot(2,1,1);  hold on;  grid on;  box on;
for s = 1:nS
    plot(P_GRID, reshape(G.LCOW(s,ik3,:), 1, nP), '-', 'LineWidth', 1.6);
end
ylim([0.95*Lmin 2*Lmin]);  ylabel('LCOW  (USD/m^3)');
legend({STRAT.name}, 'Location', 'northeast', 'Box', 'off');
title(sprintf('Operating strategy, k = %d', kb));
subplot(2,1,2);  hold on;  grid on;  box on;
for s = 1:nS
    plot(P_GRID, reshape(G.starts(s,ik3,:), 1, nP), '-', 'LineWidth', 1.6);
end
xlabel('installed PV capacity  (kWp)');  ylabel('train starts per year');

figure('Name','opt 6/6 - solar-year robustness','Color','w','Position',[1320 520 620 420]);
hold on;  grid on;  box on;
for y = 1:nYr
    plot(P_GRID, reshape(LY(y,ik3,:), 1, nP), '-', 'LineWidth', 1.6);
end
ylim([0.95*Lmin 2*Lmin]);
xlabel('installed PV capacity  (kWp)');  ylabel('LCOW  (USD/m^3)');
legend(arrayfun(@(v) sprintf('solar %d', v), YEARS, 'uni', 0), 'Location', 'northeast', 'Box', 'off');
title(sprintf('Inter-annual spread, k = %d', kb));

%% ====================== 9.  SAVE  =====================================
[~, tag] = fileparts(ERDFILES{1});
tag = erase(tag, 'erd_operating_');
save(sprintf('optimize_%s.mat', tag), 'G', 'STRAT', 'P_GRID', 'K_SET', 'Cap_k', 'C_RO_k', ...
     'YEARS', 'BASE_YEAR', 'WY', 'LY', 'UY', 'CY', 'Dopt', 'PoptK', 'LoptK', 'ratioK', ...
     'stratTab', 'nd', 'A_SCALE', 'ERDFILES', 'LCOWFILE');

[sI, kI, pI] = ndgrid(1:nS, K_SET, P_GRID);
T = table(string({STRAT(sI(:)).name})', kI(:), pI(:), G.water(:), G.util(:), G.SEC(:), ...
          G.starts(:), G.Rmean(:), G.LCOW(:), 'VariableNames', ...
          {'strategy','k','P_kWp','water_m3','util','SEC_kWh_m3','starts','R_mean','LCOW'});
writetable(T, sprintf('optimize_grid_%s.csv', tag));
fprintf('Saved optimize_%s.mat and optimize_grid_%s.csv\n', tag, tag);

%% ====================== LOCAL FUNCTIONS  ==============================
function S = dispatchYear(P, k, tr, sel, pu, swIdx, T_on)
%  One year of hourly dispatch for k trains and P kWp.  Each hour all
%  running trains share one setting (flux, and recovery if several files),
%  chosen to give the most permeate the PV power allows.
    o    = find(sel);
    nO   = numel(o);
    nH   = numel(pu);
    mVec = kron((1:k)', ones(nO,1));            % trains running, per option
    oVec = repmat(o, k, 1);                     % per-train setting, per option
    Pn   = mVec .* tr.Pel(oVec, swIdx);         % kW, options x hours
    Pav  = P * reshape(pu, 1, nH);              % kW
    feas = tr.ok(oVec, swIdx) & (Pn <= Pav);

    if T_on > 1
        mmax = max(feas .* mVec, [], 1);
        mcap = zeros(1, nH);
        for m = 1:k
            mcap(keepLongRuns(mmax >= m, T_on)) = m;
        end
        feas = feas & (mVec <= mcap);
    end

    q     = mVec .* tr.Qp(oVec);                % m3/h per option
    score = q - 1e-6 * Pn;                      % ties: least power
    score(~feas) = -Inf;
    [best, ib] = max(score, [], 1);
    on = isfinite(best);

    water = zeros(1, nH);  used = water;  feed = water;  mrun = water;
    ii = ib(on);
    water(on) = reshape(q(ii), 1, []);
    used(on)  = reshape(Pn(sub2ind(size(Pn), ii, find(on))), 1, []);
    feed(on)  = water(on) ./ reshape(tr.R(oVec(ii)), 1, []);
    mrun(on)  = reshape(mVec(ii), 1, []);

    S.water  = sum(water);                      % m3/yr
    S.feed   = sum(feed);                       % m3/yr
    S.used   = sum(used);                       % kWh/yr
    S.gen    = sum(Pav);                        % kWh/yr
    S.util   = S.used / max(S.gen, eps);
    S.SEC    = S.used / max(S.water, eps);      % kWh/m3
    S.starts = sum(max(diff([0 mrun]), 0));     % train starts per year
    S.hours  = sum(on);
    S.Rmean  = S.water / max(S.feed, eps);
end

function out = keepLongRuns(mask, T)
%  Clear every run of true values shorter than T.
    d  = diff([false mask false]);
    st = find(d == 1);
    en = find(d == -1) - 1;
    out = mask;
    for r = find(en - st + 1 < T)
        out(st(r):en(r)) = false;
    end
end

function [LCOW, total] = lcowDesign(p, P, Cap, C_RO, nEl, S, pu_max, opexMode)
%  Qudah et al. 2025 Eq. 4 without wind and storage terms.  USD/m3, USD/yr.
    a     = p.i*(1+p.i)^p.N / ((1+p.i)^p.N - 1);
    P_ac  = pu_max * P;
    pvRep = sum((1+p.i).^(-(p.L_inv : p.L_inv : p.N-1)));
    total = C_RO*a + (p.c_PV*P + p.c_inv*P_ac)*a ...
          + (p.om_fix_plant + p.om_fix_infra)*C_RO + p.c_labour*Cap*365 ...
          + p.om_PV*P + p.c_inv_rep*P_ac*pvRep*a;
    if string(opexMode) == "lumped"
        total = total + p.c_var*S.water;
    else
        total = total + p.c_var_other*S.water + p.c_chem*S.feed ...
              + p.mem_rate*nEl*p.c_element_07*p.CEPCI_base/p.CEPCI_2007;
    end
    if S.water > 0
        LCOW = total / S.water;
    else
        LCOW = Inf;
    end
end