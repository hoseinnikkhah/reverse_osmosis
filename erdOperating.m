%% erdOperating.m
%  The ERD branch.  Same plant, same membranes, same system curve, same
%  staging as pumpOperating.m - only the way the feed is pressurised changes.
%
%  WITHOUT ERD                        WITH ISOBARIC ERD
%    HP pump handles Q_f                HP pump handles Q_p
%    brine energy is throttled away     PX pressurises Q_b from the brine
%                                       booster makes up the residual
%
%    seawater --+--> HP pump --------------------+
%               |    Q_p @ full head             +--> membranes --> permeate
%               +--> PX --> booster -------------+         |
%                    Q_b @ residual head                   |
%                     ^                                    |
%                     +---------- brine Q_b <--------------+
%
%  ENERGY
%    P_HP    = rho g Q_p H / eta_HP
%    P_boost = rho g Q_b H_boost / eta_boost
%    H_boost = H - eta_PX * (H - H_vessel)
%  where H_vessel is the pressure drop along the vessel, so the brine
%  leaves at (H - H_vessel) and the PX returns eta_PX of that to the feed.
%
%  MIXING
%    A rotary PX returns a small volume of brine into the feed.  With a
%    mixing fraction m, feed salinity at the membranes rises by roughly
%        (Q_b/Q_f) * m * (C_b/C_f - 1)
%  which raises osmotic pressure and therefore the head.  Switch it on to
%  see the size of the effect; it is of order 1 %.
%
%  NOTHING UPSTREAM CHANGES.  systemCurve.m, run_all_designs.m and
%  train_staging.m are shared with the no-ERD branch untouched.
%
%  Inputs : system_curve_<cfg>_<e>e_<v>v_R<rr>.mat
%           HP pump curve  (sized for Q_p, NOT Q_f)
%           booster pump efficiency or curve
%           PX efficiency and mixing, from the manufacturer catalogue
%  Output : erd_operating_<tag>.mat, a report, three figures

clear; close all; clc;
fprintf('>>> running erdOperating.m  (ERD branch)\n');

%% ====================== 1.  THE DESIGN  ===============================
% ---- edit this block only ---------------------------------------------
SYSFILE  = 'system_curve_Conv_7e_96v_R35.mat';
k_trains = 3;

eta_motor = 0.96;          % motor efficiency
eta_vfd   = 0.98;          % drive efficiency
n_min     = 0.817;         % HP pump min speed = sqrt(pi_avg/shutoff)
                           %   = sqrt(447/670.4) for this curve.  Below it
                           %   the pump deadheads against osmotic pressure.
n_max     = 1.00;

% ---- ENERGY RECOVERY DEVICE -------------------------------------------
% PROVENANCE OF EVERY NUMBER IN THIS BLOCK.
%   [CAT] printed in the Energy Recovery Inc. 2024 Water Products Catalog,
%         PX PowerTrain and high-pressure PX pages.
%   [EST] engineering estimate, NOT published.  Swept in section 5b, so the
%         paper reports a band instead of a single invented value.
ERD_MODEL  = "PX PowerTrain";
PX_Qmin    = 182;          % [CAT] m3/h  (800 gpm)
PX_Qmax    = 682;          % [CAT] m3/h  (3,000 gpm)
PX_Pmax    = 83;           % [CAT] bar   ("up to 83 bar / 1,200 psi")
eta_PX     = 0.97;         % [CAT] catalogue states 97-98 % PEAK efficiency.
                           %       Peak is near BEP only, so 0.97 is the
                           %       base case, 0.98 the optimistic bound.
mix_frac   = 0.03;         % [CAT] "<3 % volumetric mixing", printed for the
                           %       PX Q400.  Used here as an upper bound.
APPLY_MIXING = true;       % include the salinity feedback

dP_vessel  = 1.5;          % [EST] bar, drop along one 7-element vessel.
                           %       Replace with the element dP from the
                           %       membrane design guide at your feed flow.
dP_pipe    = 0.5;          % [EST] bar, ERD and piping losses, booster leg

% ---- HP PUMP (sized for Q_p, roughly a third of the no-ERD flow) -------
% From fitPumpCurve.m, BRANCH = "ERD", duty Q_p = 133.2 m3/h at 584 m.
CURVE_SOURCE = "DATASHEET";
pH    = [-5.606349e-03, +4.635956e-01, +6.704273e+02];
pEta  = [-2.121827e-05, +8.544103e-03, +7.276717e-02];
Q_FIT = [30 331];          % m3/h range the curve was digitised over.
                           % Outside it a falling parabola returns negative
                           % head and the speed solve is meaningless.

% Honest health warning that travels with the saved results.  The fitted
% curve gives eta_BEP = 0.933, which no pump of this size achieves; since
% eta = QH/(367P), the digitised POWER is ~4.5 % low.  Head is sound
% (R2 = 0.99924), so heads, speeds and flows are trustworthy and the
% efficiency-derived quantities are optimistic by about that margin.
CURVE_CAVEAT = "eta_BEP = 0.933 > 0.92: power axis ~4.5% low, SEC optimistic";

% ---- BOOSTER PUMP (low head, high flow) -------------------------------
% Contributes ~7 % of total power, so a datasheet efficiency is adequate.
% Set BOOST_CURVE = true and fill pEtaB to use a digitised curve instead.
BOOST_CURVE = false;
eta_boost   = 0.82;        % single-stage centrifugal, datasheet range
pEtaB       = [];          % used only if BOOST_CURVE is true
% -----------------------------------------------------------------------

assert(pH(1) < 0, 'pH(1) must be NEGATIVE - a pump curve falls with flow.');

%% ====================== 2.  LOAD  =====================================
L = load(SYSFILE);
d = L.design;
A_train = d.A_mem / k_trains;
R       = d.R_set;
bar2m   = L.bar2m;
pi_avg  = L.pi_avg;
A_T     = L.A_T;
dates   = L.dates(:).';

nDchk = numel(pi_avg);
if ~isdatetime(dates) || numel(dates) ~= nDchk || ...
        year(dates(1)) < 1900 || year(dates(1)) > 2100
    dates = datetime(2025,7,31) + caldays(0:nDchk-1);
end

%% ============ 3.  MIXING: FEED SALINITY RISES =========================
% C_b/C_f = 1/(1-R).  The PX returns mix_frac of the brine it handles into
% the feed, and that feed is the fraction Q_b/Q_f of the total.
if APPLY_MIXING
    salt_rise = (1-R) * mix_frac * (1/(1-R) - 1);   % = mix_frac * R
    pi_fac    = 1 + salt_rise;
else
    salt_rise = 0;   pi_fac = 1;
end
pi_avg_eff = pi_avg * pi_fac;

%% ============ 4.  SYSTEM CURVE (membrane side, unchanged) =============
flux = @(Q) Q * R * 1000 / A_train;
Qof  = @(J) J * A_train / (R*1000);
Hsys = @(Q,t) (pi_avg_eff(t) + flux(Q)./A_T(t)) * bar2m;

Jset = (d.J_lo : 0.25 : d.J_hi)';
nJ   = numel(Jset);   nD = numel(dates);

Qf_set = Qof(Jset);                       % feed per train,     m3/h
Qp_set = Jset * A_train / 1000;           % permeate per train, m3/h
Qb_set = Qf_set - Qp_set;                 % brine per train,    m3/h

% ---- the HP pump sees Q_p: does the curve actually cover it? ----------
if min(Qp_set) < Q_FIT(1) || max(Qp_set) > Q_FIT(2)
    fprintf('\n*** CURVE RANGE ERROR ***\n');
    fprintf('HP pump must pass Q_p = %.0f - %.0f m3/h, but the curve was\n', ...
            min(Qp_set), max(Qp_set));
    fprintf('digitised over only %.0f - %.0f m3/h.\n', Q_FIT(1), Q_FIT(2));
    error('erdOperating: pump curve does not cover the required flow range.');
end

Qf_des = Qof(d.J_design);
Qp_des = d.J_design * A_train / 1000;
Qb_des = Qf_des - Qp_des;

fprintf('\n%s\n', repmat('=',1,66));
fprintf('%s, %d x %d vessels, R = %.0f %%, %d trains\n', ...
        d.cfg_name, d.n_elem, d.n_vess, R*100, k_trains);
fprintf('per train at design flux:  Q_f %.1f   Q_p %.1f   Q_b %.1f  m3/h\n', ...
        Qf_des, Qp_des, Qb_des);
fprintf('HP pump now sees Q_p = %.1f m3/h, not Q_f = %.1f m3/h\n', Qp_des, Qf_des);
if APPLY_MIXING
    fprintf('mixing %.0f %% raises feed salinity %.2f %% -> osmotic pressure x %.4f\n', ...
            100*mix_frac, 100*salt_rise, pi_fac);
end
if CURVE_SOURCE ~= "DATASHEET"
    fprintf('\n*** HP PUMP CURVE IS A PLACEHOLDER - RESULTS NOT REAL ***\n');
elseif strlength(CURVE_CAVEAT) > 0
    fprintf('\n*** CURVE CAVEAT: %s ***\n', CURVE_CAVEAT);
end
fprintf('%s\n\n', repmat('=',1,66));

%% ============ 5.  ERD SELECTION CHECK  ================================
fprintf('--- ERD selection, %s ---\n', ERD_MODEL);
fprintf('brine flow per train     : %.1f m3/h   (model range %.0f - %.0f)\n', ...
        Qb_des, PX_Qmin, PX_Qmax);
if Qb_des < PX_Qmin || Qb_des > PX_Qmax
    nUnit = ceil(Qb_des/PX_Qmax);
    fprintf('OUT OF RANGE - need %d units in parallel per train\n', nUnit);
else
    fprintf('within range - one unit per train\n');
end
dP_des_bar = max(pi_avg_eff + d.J_design./A_T);
fprintf('max differential pressure: %.2f bar   (rating %.0f bar)  %s\n', ...
        dP_des_bar, PX_Pmax, string(dP_des_bar < PX_Pmax));
fprintf('net transfer efficiency  : %.3f\n', eta_PX);
fprintf('plant total brine flow   : %.1f m3/h over %d trains\n\n', ...
        k_trains*Qb_des, k_trains);

%% ============ 5b.  SENSITIVITY TO THE TWO UNPUBLISHED NUMBERS =========
% dP_vessel and eta_PX are the only ERD inputs not printed in the
% catalogue.  Quantify them before quoting any SEC.
fprintf('--- sensitivity: the inputs that are NOT from the catalogue ---\n');
H_w   = max(pi_avg_eff + d.J_design./A_T) * bar2m;
eta_s = polyval(pEta, Qp_des);
PHP_s = 1025*9.81*(Qp_des/3600)*H_w/max(eta_s,eps)/1000;
fprintf('%8s %7s | %9s %9s | %9s %9s\n', ...
        'dP_vess','eta_PX','H_boost','P_boost','P_total','vs base');
base = NaN;  shr = NaN;
for ePX = [0.97 0.98]
    for dPv = [0.8 1.5 2.5]
        Hb  = H_w*(1-ePX) + ePX*dPv*bar2m + dP_pipe*bar2m;
        PBO = 1025*9.81*(Qb_des/3600)*Hb/eta_boost/1000;
        tot = PHP_s + PBO;
        if isnan(base), base = tot; end
        shr = 100*PBO/tot;
        fprintf('%8.1f %7.2f | %8.1fm %8.1fkW | %8.1fkW %+8.1f %%\n', ...
                dPv, ePX, Hb, PBO, tot, 100*(tot/base-1));
    end
end
fprintf('Booster is only ~%.0f %% of plant power, so even a 50 %% error in\n', shr);
fprintf('H_boost moves total power a few per cent.  Quote this as the band.\n\n');

%% ============ 6.  SWEEP THE BAND OVER THE YEAR  =======================
a = pH(1);  b = pH(2);  c = pH(3);
speedFor = @(Q,H) ( -b*Q + sqrt( max((b*Q).^2 - 4*c*(a*Q.^2 - H), 0) ) ) ./ (2*c);

Hreq = zeros(nJ,nD);  nreq = zeros(nJ,nD);  etaHP = zeros(nJ,nD);
P_HP = zeros(nJ,nD);  P_BO = zeros(nJ,nD);  Pel  = zeros(nJ,nD);
Hbo  = zeros(nJ,nD);  okSpd = false(nJ,nD);

for t = 1:nD
    H = Hsys(Qf_set, t);                     % head the membranes demand
    n = speedFor(Qp_set, H);                 % HP pump now passes Q_p
    e = polyval(pEta, Qp_set ./ max(n,eps));

    % booster head: PX returns eta_PX of the brine-side head
    H_brine = H - dP_vessel*bar2m;
    H_boost = H - eta_PX*H_brine + dP_pipe*bar2m;

    if BOOST_CURVE
        eB = polyval(pEtaB, Qb_set);
    else
        eB = eta_boost * ones(size(Qb_set));
    end

    Hreq(:,t)  = H;      nreq(:,t) = n;     etaHP(:,t) = e;
    Hbo(:,t)   = H_boost;
    okSpd(:,t) = (n >= n_min) & (n <= n_max) & (e > 0.05);

    P_HP(:,t) = 1025*9.81 .* (Qp_set/3600) .* H       ./ max(e,eps)  /1000;
    P_BO(:,t) = 1025*9.81 .* (Qb_set/3600) .* H_boost ./ max(eB,eps) /1000;
    Pel(:,t)  = (P_HP(:,t) + P_BO(:,t)) / (eta_motor*eta_vfd);
end

%% ============ 7.  DESIGN POINT AND THE COMPARISON  ====================
[~, iDes] = min(abs(Jset - d.J_design));
n_des    = nreq(iDes,:);     eta_des  = etaHP(iDes,:);
H_des    = Hreq(iDes,:);     Hbo_des  = Hbo(iDes,:);
PHP_des  = P_HP(iDes,:);     PBO_des  = P_BO(iDes,:);
Pel_des  = Pel(iDes,:);

SEC_el  = Pel_des / Qp_des;
SEC_hyd = (1025*9.81*(Qp_des/3600).*H_des + ...
           1025*9.81*(Qb_des/3600).*Hbo_des)/1000 / Qp_des;

% What the same plant would need with no ERD at all.
% BUG FIX: with no PX there is NO brine mixing, so the baseline head must be
% rebuilt WITHOUT pi_fac.  Using the mixed head here penalised the baseline
% by an effect it does not have and overstated the ERD saving by ~0.8 %.
H_des_noMix = (pi_avg + d.J_design./A_T) * bar2m;      % 1 x nD, no mixing
P_noERD_hyd = 1025*9.81*(Qf_des/3600).*H_des_noMix/1000;
SEC_noERD   = P_noERD_hyd / Qp_des;

fprintf('--- at the design flux, across the year ---\n');
fprintf('required head        : %.0f - %.0f m\n', min(H_des), max(H_des));
fprintf('HP pump speed        : %.3f - %.3f of nominal\n', min(n_des), max(n_des));
fprintf('HP pump efficiency   : %.3f - %.3f\n', min(eta_des), max(eta_des));
fprintf('booster head         : %.1f - %.1f m  (%.2f - %.2f bar)\n', ...
        min(Hbo_des), max(Hbo_des), min(Hbo_des)/bar2m, max(Hbo_des)/bar2m);
fprintf('HP pump power        : %.1f - %.1f kW\n', min(PHP_des), max(PHP_des));
fprintf('booster power        : %.1f - %.1f kW  (%.0f %% of total)\n', ...
        min(PBO_des), max(PBO_des), 100*mean(PBO_des)/mean(PHP_des+PBO_des));
fprintf('electrical, train    : %.1f - %.1f kW\n', min(Pel_des), max(Pel_des));
fprintf('electrical, plant    : %.1f - %.1f kW  (%d trains)\n', ...
        k_trains*min(Pel_des), k_trains*max(Pel_des), k_trains);
fprintf('------------------------------------------------------------\n');
fprintf('SEC hydraulic, ERD   : %.3f - %.3f kWh/m3\n', min(SEC_hyd), max(SEC_hyd));
fprintf('SEC electrical, ERD  : %.3f - %.3f kWh/m3  (mean %.3f)\n', ...
        min(SEC_el), max(SEC_el), mean(SEC_el));
fprintf('SEC hydraulic, NO ERD: %.3f - %.3f kWh/m3\n', ...
        min(SEC_noERD), max(SEC_noERD));
fprintf('ENERGY SAVED         : %.1f %% on hydraulic specific energy\n', ...
        100*(1 - mean(SEC_hyd)/mean(SEC_noERD)));
fprintf('CHECK electrical > hydraulic -> %s\n', string(all(SEC_el > SEC_hyd)));
fprintf('CHECK ERD below no-ERD       -> %s\n', string(all(SEC_hyd < SEC_noERD)));
fprintf('\n--- band reachability ---\n');
fprintf('flux holdable on every day : %d of %d\n', sum(all(okSpd,2)), nJ);
if ~all(okSpd(:))
    Jbad = Jset(~all(okSpd,2));
    fprintf('unreachable flux: %.2f - %.2f LMH\n', min(Jbad), max(Jbad));
end
fprintf('\n');

%% ====================== 8.  FIGURES  ==================================
figure('Name','erdOperating 1/3 - where the power goes','Color','w', ...
       'Position',[80 320 720 520]);
subplot(2,1,1); hold on; grid on; box on;
area(dates, [PHP_des; PBO_des].');
ylabel('power per train  (kW)');
legend('HP pump','booster','Location','best','Box','off');
title(sprintf('%s - power split with %s', d.cfg_name, ERD_MODEL));

subplot(2,1,2); hold on; grid on; box on;
plot(dates, SEC_noERD, 'r--', 'LineWidth',1.6, 'DisplayName','no ERD (hydraulic)');
plot(dates, SEC_hyd,   'b-',  'LineWidth',1.6, 'DisplayName','with ERD (hydraulic)');
plot(dates, SEC_el,    'k-',  'LineWidth',1.6, 'DisplayName','with ERD (electrical)');
ylabel('SEC  (kWh/m^3)'); xlabel('date');
legend('Location','best','Box','off');
title('Specific energy - the ERD saving');

figure('Name','erdOperating 2/3 - part load','Color','w','Position',[820 320 720 520]);
[~,tHot] = max(H_des);  [~,tCold] = min(H_des);
subplot(2,1,1); hold on; grid on; box on;
plot(Jset, 100*etaHP(:,tHot),  'r-', 'LineWidth',1.7, 'DisplayName','worst day');
plot(Jset, 100*etaHP(:,tCold), 'b-', 'LineWidth',1.7, 'DisplayName','best day');
xline(d.J_design,'k--','HandleVisibility','off');
ylabel('HP pump \eta  (%)');  title('HP pump efficiency across the flux band');
legend('Location','best','Box','off','FontSize',8);

subplot(2,1,2); hold on; grid on; box on;
plot(Jset, Pel(:,tHot)./Qp_set,  'r-', 'LineWidth',1.7, 'DisplayName','worst day');
plot(Jset, Pel(:,tCold)./Qp_set, 'b-', 'LineWidth',1.7, 'DisplayName','best day');
xline(d.J_design,'k--','HandleVisibility','off');
xlabel('Commanded flux  J_w  (LMH)');  ylabel('SEC_{el}  (kWh/m^3)');
title('Electrical specific energy against turndown, with ERD');
legend('Location','best','Box','off','FontSize',8);

figure('Name','erdOperating 3/3 - flow split','Color','w','Position',[450 100 640 420]);
hold on; grid on; box on;
plot(Jset, Qf_set, 'k-',  'LineWidth',1.8, 'DisplayName','Q_f  feed');
plot(Jset, Qp_set, 'b-',  'LineWidth',1.8, 'DisplayName','Q_p  HP pump');
plot(Jset, Qb_set, 'r-',  'LineWidth',1.8, 'DisplayName','Q_b  PX and booster');
yline(PX_Qmin,'k:','DisplayName','PX range');
yline(PX_Qmax,'k:','HandleVisibility','off');
xline(d.J_design,'k--','HandleVisibility','off');
xlabel('Commanded flux  J_w  (LMH)');  ylabel('flow per train  (m^3/h)');
title(sprintf('Flow split - PX must cover Q_b across the whole band\n%s', ERD_MODEL));
legend('Location','best','Box','off');

%% ====================== 9.  SAVE (guarded)  ===========================
SEC_noERD_note = "baseline head excludes PX mixing (no PX in that case)";
if CURVE_SOURCE == "DATASHEET"
    [~, base] = fileparts(SYSFILE);
    out = sprintf('erd_operating_%s_k%d.mat', erase(base,'system_curve_'), k_trains);
    save(out, 'd','k_trains','A_train','pH','pEta','CURVE_SOURCE', ...
         'Q_FIT','CURVE_CAVEAT','SEC_noERD_note', ...
         'ERD_MODEL','eta_PX','mix_frac','APPLY_MIXING','pi_fac', ...
         'eta_boost','dP_vessel','dP_pipe', ...
         'Jset','Qf_set','Qp_set','Qb_set','Hreq','nreq','etaHP', ...
         'P_HP','P_BO','Pel','okSpd','SEC_el','SEC_hyd','SEC_noERD', ...
         'dates','eta_motor','eta_vfd','n_min','n_max');
    fprintf('Saved %s\n', out);
else
    fprintf('NOT SAVED - CURVE_SOURCE is "%s".\n', CURVE_SOURCE);
    fprintf('Digitise an HP pump sized for %.0f m3/h at %.0f m, paste pH and\n', ...
            Qp_des, max(H_des));
    fprintf('pEta, and set CURVE_SOURCE = "DATASHEET".\n');
end