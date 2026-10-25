%% pvDispatch.m
%  Hour by hour, decide how many trains run and at what flux, given the PV
%  power available that hour and the seawater conditions that day.
%
%  THE DECISION
%    Each hour the plant may run m = 0..k_trains trains, all at a common
%    commanded flux J.  The choice must satisfy
%        m * Pel(J,d)  <=  P_available(h)        power constraint
%        okSpd(J,d)                              the pump can hold that flux
%    and among the feasible choices we take the one that makes the most
%    permeate, m * Qp(J).
%
%  WHY THERE ARE GAPS
%    m is an integer and J is bounded, so the plant can only absorb power in
%    discrete windows.  Between them, PV power exists that the plant cannot
%    use at any setting - it runs the lower configuration flat out and the
%    rest is curtailed.  This is structural: no PV size removes it.
%
%  NO STORAGE
%    PV only.  Power not used in the hour it is generated is lost.  This is
%    what makes "renewable utilisation" and "curtailment" meaningful metrics.
%
%  TIME ALIGNMENT
%    Solar and seawater records cover different calendar years, so they are
%    joined by DAY-OF-YEAR: January seawater with January sun.  Individual
%    weather events are uncorrelated between the datasets and carry no joint
%    information, so matching them would be meaningless even if possible.
%
%  Inputs : pv_generation.mat, erd_operating_<tag>_k<k>.mat
%  Output : pv_dispatch_<tag>.mat, a report, four figures

clear; close all; clc;
fprintf('>>> running pvDispatch.m\n');

%% ====================== 1.  SETTINGS  =================================
% ---- edit this block only ---------------------------------------------
ERDFILE = 'erd_operating_Conv_7e_96v_R35_k3.mat';
PVFILE  = 'pv_generation.mat';

PV_YEAR = 2021;            % which solar year to dispatch against
                           % (rerun with 2020 and 2022 for the spread)

P_SWEEP = [500 750 1000 1250 1500 1750 2000 2500 3000 4000 5000];   % kWp
P_BASE  = 1500;            % the capacity shown hour-by-hour in the figures
% -----------------------------------------------------------------------

%% ====================== 2.  LOAD  =====================================
E = load(ERDFILE);
V = load(PVFILE);   pv = V.pv;

Jset   = E.Jset(:);            % commanded flux values, LMH
Qp_set = E.Qp_set(:);          % permeate per train at each flux, m3/h
Pel    = E.Pel;                % electrical power per train, nJ x nD, kW
okSpd  = E.okSpd;              % nJ x nD, can the pump hold that flux
kt     = E.k_trains;
sw_dates = E.dates(:).';
nJ = numel(Jset);

fprintf('plant : %s, %d x %d vessels, R = %.0f %%, %d trains\n', ...
        E.d.cfg_name, E.d.n_elem, E.d.n_vess, E.d.R_set*100, kt);
if isfield(E,'PUMP_MODEL'), fprintf('pump  : %s\n', E.PUMP_MODEL); end
if isfield(E,'CURVE_CAVEAT') && strlength(E.CURVE_CAVEAT) > 0
    fprintf('*** CAVEAT: %s ***\n', E.CURVE_CAVEAT);
end

%% ============ 3.  DAY-OF-YEAR JOIN  ===================================
keep  = year(pv.time) == PV_YEAR;
t_pv  = pv.time(keep);
p_pu  = pv.p_unit(keep);                      % kW_ac per kWp
nH    = numel(t_pv);
assert(nH > 8000, 'pvDispatch: %d is not a complete year in %s', PV_YEAR, PVFILE);

doy_sw = day(sw_dates, 'dayofyear');
doy_pv = day(t_pv,     'dayofyear');
doy_pv(doy_pv == 366) = 365;                  % leap safety

map = nan(365,1);
for dd = 1:365
    k = find(doy_sw == dd, 1, 'first');       % 212 appears twice; take the first
    if ~isempty(k), map(dd) = k; end
end
assert(~any(isnan(map)), ['pvDispatch: day-of-year %s has no seawater data. ' ...
    'The seawater record must cover a full year.'], mat2str(find(isnan(map))'));
sw_for_hour = map(doy_pv);                    % nH x 1, index into the Pel columns

fprintf('joined %d solar hours (%d) to %d seawater days by day-of-year\n', ...
        nH, PV_YEAR, numel(sw_dates));

%% ============ 4.  THE DISPATCH  =======================================
% Enumerate every (trains, flux) pair rather than assuming which wins.  It
% is 3 x 21 options, so exhaustive search costs nothing and cannot be wrong.
mList = (1:kt)';
Qout  = mList * Qp_set';                      % kt x nJ, m3/h produced

nP = numel(P_SWEEP);
res = struct('P_peak',num2cell(P_SWEEP(:)));

for s = 1:nP
    Ppk = P_SWEEP(s);
    Pav = Ppk * p_pu;                         % kW available each hour

    water = zeros(nH,1);  used = zeros(nH,1);
    mrun  = zeros(nH,1);  jrun = zeros(nH,1);

    for h = 1:nH
        if Pav(h) <= 0, continue; end
        d = sw_for_hour(h);
        Pneed = mList * Pel(:,d)';            % kt x nJ, kW required
        feas  = Pneed <= Pav(h) & repmat(okSpd(:,d)', kt, 1);
        if ~any(feas(:)), continue; end
        q = Qout;  q(~feas) = -Inf;
        [best, idx] = max(q(:));
        [mi, ji] = ind2sub(size(q), idx);
        water(h) = best;                      % m3 in this hour
        used(h)  = Pneed(mi,ji);
        mrun(h)  = mi;  jrun(h) = ji;
    end

    gen  = sum(Pav);                          % kWh generated
    usd  = sum(used);                         % kWh used
    res(s).water   = sum(water);              % m3/yr
    res(s).gen     = gen;
    res(s).used    = usd;
    res(s).curt    = gen - usd;
    res(s).util    = usd/gen;
    res(s).SEC     = usd/max(sum(water),eps);
    res(s).hours   = sum(mrun > 0);
    res(s).hrs_m   = arrayfun(@(m) sum(mrun==m), 1:kt);
    res(s).meanJ   = sum(Jset(jrun(jrun>0)).*water(jrun>0))/max(sum(water(jrun>0)),eps);
    if Ppk == P_BASE
        base = struct('Pav',Pav,'used',used,'water',water,'mrun',mrun, ...
                      'jrun',jrun,'t',t_pv);
    end
end
if ~exist('base','var')
    warning('P_BASE = %g is not in P_SWEEP; figures 1 and 3 skipped.', P_BASE);
end

%% ============ 5.  REPORT  =============================================
Qmax = kt*max(Qp_set)*8760;                   % m3/yr if it never stopped
fprintf('\n%s\n', repmat('=',1,78));
fprintf('PV DISPATCH, solar year %d, no storage\n', PV_YEAR);
fprintf('%s\n', repmat('-',1,78));
fprintf('%7s %10s %9s %8s %8s %7s %7s %6s\n', ...
        'kWp','water m3','util %','curt %','SEC','hours','CF %','mean J');
for s = 1:nP
    fprintf('%7d %10.0f %9.1f %8.1f %8.3f %7d %7.1f %6.2f\n', ...
            res(s).P_peak, res(s).water, 100*res(s).util, ...
            100*(1-res(s).util), res(s).SEC, res(s).hours, ...
            100*res(s).water/Qmax, res(s).meanJ);
end
fprintf('%s\n', repmat('-',1,78));
[~, iU] = max([res.util]);
fprintf('highest PV utilisation at %d kWp (%.1f %%)\n', ...
        res(iU).P_peak, 100*res(iU).util);
fprintf('NOTE utilisation peaks where the array fits the plant, but water\n');
fprintf('     keeps rising with capacity.  Which point is best is an\n');
fprintf('     ECONOMIC question - it needs the LCOW layer, not this one.\n');
fprintf('%s\n\n', repmat('=',1,78));

if exist('base','var')
    fprintf('--- how the plant spends its year at %d kWp ---\n', P_BASE);
    s = find([res.P_peak] == P_BASE, 1);
    fprintf('idle (PV below the one-train threshold) : %d h (%.0f %%)\n', ...
            8760-res(s).hours, 100*(8760-res(s).hours)/8760);
    for m = 1:kt
        fprintf('%d train(s) running : %5d h (%.0f %%)\n', ...
                m, res(s).hrs_m(m), 100*res(s).hrs_m(m)/8760);
    end
    fprintf('curtailed energy : %.0f MWh of %.0f MWh generated\n\n', ...
            res(s).curt/1000, res(s).gen/1000);
end

%% ====================== 6.  FIGURES  ==================================
if exist('base','var')
figure('Name','pvDispatch 1/4 - two days','Color','w','Position',[60 300 980 560]);
[~,iS] = max(splitapply(@sum, base.Pav, findgroups(dateshift(base.t,'start','day'))));
dl = unique(dateshift(base.t,'start','day'));
for sp = 1:2
    if sp==1, d0 = dl(iS); ttl = 'best solar day';
    else,     d0 = dl(max(1,iS-182)); ttl = 'opposite season'; end
    subplot(2,1,sp); hold on; grid on; box on;
    k = dateshift(base.t,'start','day') == d0;
    area(base.t(k), base.Pav(k), 'FaceColor',[0.98 0.85 0.4], 'EdgeColor','none');
    area(base.t(k), base.used(k), 'FaceColor',[0.2 0.45 0.75], 'EdgeColor','none');
    yline(min(Pel(:))  , 'k:',  'one train minimum');
    ylabel('kW');  title(sprintf('%s - %s  (gold = PV, blue = used)', ttl, datestr(d0,'dd mmm')));
end

figure('Name','pvDispatch 2/4 - the design map','Color','w','Position',[1060 300 700 560]);
subplot(2,1,1); hold on; grid on; box on;
plot([res.P_peak], [res.water]/1000, 'o-', 'LineWidth',1.8, 'Color',[0.1 0.4 0.7]);
ylabel('annual permeate  (10^3 m^3)');
title('More PV always makes more water - but with falling returns');
subplot(2,1,2); hold on; grid on; box on;
plot([res.P_peak], 100*[res.util], 'o-', 'LineWidth',1.8, 'Color',[0.75 0.3 0.1]);
plot([res.P_peak], 100*(1-[res.util]), 's--', 'LineWidth',1.4, 'Color',[0.4 0.4 0.4]);
xlabel('installed PV capacity  (kWp)');  ylabel('%');
legend('PV utilised','curtailed','Location','best','Box','off');
title('...while utilisation falls.  The optimum is economic, not technical');

figure('Name','pvDispatch 3/4 - where the hours go','Color','w','Position',[60 100 700 420]);
hrs = reshape([res.hrs_m], kt, nP)';
bar([res.P_peak], [8760-[res.hours]' hrs], 'stacked');
xlabel('installed PV capacity  (kWp)');  ylabel('hours per year');
legend(['idle', arrayfun(@(m) sprintf('%d train(s)',m), 1:kt, 'uni',0)], ...
       'Location','eastoutside','Box','off');
title('Integer train count: the plant lives in discrete states');

figure('Name','pvDispatch 4/4 - the duration curve','Color','w','Position',[800 100 700 420]);
hold on; grid on; box on;
plot(sort(base.Pav,'descend'), 'LineWidth',1.6, 'Color',[0.85 0.6 0.1]);
plot(sort(base.used,'descend'), 'LineWidth',1.6, 'Color',[0.2 0.45 0.75]);
yline(min(Pel(:)), 'k:', 'one-train floor');
yline(kt*max(Pel(:)), 'k--', 'plant maximum');
xlabel('hours of the year, sorted');  ylabel('kW');
legend('PV available','PV used','Location','northeast','Box','off');
title(sprintf('Load duration, %d kWp - the gap between the curves is curtailment', P_BASE));
end

%% ====================== 7.  SAVE  =====================================
[~, tag] = fileparts(ERDFILE);
out = sprintf('pv_dispatch_%s_%d.mat', erase(tag,'erd_operating_'), PV_YEAR);
save(out, 'res', 'P_SWEEP', 'PV_YEAR', 'ERDFILE', 'PVFILE', 'Qmax', ...
     'sw_for_hour', 'Jset', 'Qp_set', 'kt');
fprintf('Saved %s\n', out);