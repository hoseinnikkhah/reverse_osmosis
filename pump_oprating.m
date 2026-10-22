%% pumpOperating.m
%  Couple the selected pump to the system curve and produce the electrical
%  energy demand - the first number in this study that is not purely
%  hydraulic.
%
%  THE PHYSICS
%  System curve, per train, on day t:
%      dP(Q,t) = pi_avg(t) + J/A(T(t))      with  J = Q*R*1000/A_train
%  so it is LINEAR in Q: a large static osmotic term plus a membrane term.
%  (Most pumping systems are quadratic; RO is not, because solution-diffusion
%  flux is linear in pressure.)
%
%  Pump curve at nominal speed, fitted as a quadratic:
%      H(Q) = a*Q^2 + b*Q + c          with a < 0  (head falls with flow)
%
%  Affinity laws: Q ~ n, H ~ n^2, P ~ n^3, with n = N/N_nominal.  Applying
%  them to the quadratic gives a closed form:
%      H(Q,n) = a*Q^2 + b*Q*n + c*n^2
%  which is QUADRATIC IN n.  So for a commanded flow Q and the head the
%  system demands there, the required speed solves exactly:
%      c*n^2 + (b*Q)*n + (a*Q^2 - H_sys) = 0
%  No iteration needed.
%
%  Efficiency is taken as preserved along similarity lines:
%      eta(Q,n) = eta_curve(Q/n)
%  which is the standard engineering approximation and slightly optimistic
%  at low speed - state it as an assumption.
%
%  Inputs : system_curve_<cfg>_<e>e_<v>v_R<rr>.mat   (from systemCurve.m)
%           train_staging.mat                        (for the train count)
%           pump curve coefficients - FROM THE DATASHEET
%  Output : pump_operating_<tag>.mat, a report, two figures
%
%  !! This script REFUSES to save results while CURVE_SOURCE is
%  !! "PLACEHOLDER".  Placeholder coefficients are invented and exist only
%  !! so the code can be tested before the datasheet arrives.

clear; close all; clc;
fprintf('>>> running pumpOperating.m\n');

%% ====================== 1.  THE DESIGN  ===============================
% ---- edit this block only ---------------------------------------------
SYSFILE  = 'system_curve_Conv_7e_96v_R35.mat';   % from run_all_designs.m
k_trains = 3;              % parallel trains (from train_staging.m)

eta_motor = 0.96;          % motor efficiency      (datasheet)
eta_vfd   = 0.98;          % drive efficiency      (datasheet)
n_min     = 0.70;          % minimum speed ratio   (pump datasheet)
n_max     = 1.00;          % maximum speed ratio

% ---- PUMP CURVES --------------------------------------------------------
% Set CURVE_SOURCE = "DATASHEET" once pH and pEta come from digitised
% manufacturer curves.  Until then the numbers below are INVENTED.
CURVE_SOURCE = "DATASHEET";

pH   = [-1.102572e-03, +2.345643e-01, +7.311253e+02];
pEta = [-2.510007e-06, +2.488996e-03, +1.941060e-01];
% -----------------------------------------------------------------------

assert(pH(1) < 0, ['pH(1) must be NEGATIVE - a pump curve falls with flow. ' ...
                   'A positive value means a system curve was fitted by mistake.']);

%% ====================== 2.  LOAD  =====================================
L = load(SYSFILE);
d = L.design;
A_train = d.A_mem / k_trains;              % m2 per train
R       = d.R_set;
bar2m   = L.bar2m;
dates   = L.dates(:).';
pi_avg  = L.pi_avg;                        % bar [1 x 366]
A_T     = L.A_T;                           % LMH/bar [1 x 366]

% --- make the date axis safe ------------------------------------------
% Guard against a dates vector stored as datenum, as the wrong type, or
% with an absurd epoch - any of which makes the time axis unreadable.
nDchk = numel(pi_avg);
if ~isdatetime(dates) || numel(dates) ~= nDchk
    if isnumeric(dates) && numel(dates) == nDchk && all(dates > 6e5 & dates < 8e5)
        dates = datetime(dates, 'ConvertFrom', 'datenum');     % was a datenum
    else
        dates = datetime(2025,7,31) + caldays(0:nDchk-1);      % rebuild
        warning('pumpOperating:dates', ...
                'dates rebuilt from scratch - check the source file.');
    end
elseif year(dates(1)) < 1900 || year(dates(1)) > 2100
    dates = datetime(2025,7,31) + caldays(0:nDchk-1);
    warning('pumpOperating:dates', ...
            'dates had an implausible epoch and were rebuilt.');
end

fprintf('\n%s\n', repmat('=',1,62));
fprintf('%s, %d elements x %d vessels, R = %.0f %%\n', ...
        d.cfg_name, d.n_elem, d.n_vess, R*100);
fprintf('%d trains, %.1f vessels each, %.0f m2 per train\n', ...
        k_trains, d.n_vess/k_trains, A_train);
fprintf('flux band %.0f - %.0f LMH, design %.1f LMH\n', d.J_lo, d.J_hi, d.J_design);
if CURVE_SOURCE ~= "DATASHEET"
    fprintf('\n*** PUMP CURVES ARE PLACEHOLDERS - RESULTS ARE NOT REAL ***\n');
end
fprintf('%s\n\n', repmat('=',1,62));

%% ============ 3.  SYSTEM CURVE PER TRAIN, AS A FUNCTION OF Q ==========
% J [LMH] = Q_f [m3/h] * R * 1000 / A_train
flux   = @(Q) Q * R * 1000 / A_train;             % m3/h -> LMH
Qof    = @(J) J * A_train / (R*1000);             % LMH  -> m3/h
% head the system demands at flow Q on day t, in metres
Hsys   = @(Q,t) (pi_avg(t) + flux(Q)./A_T(t)) * bar2m;

Q_lo = Qof(d.J_lo);   Q_de = Qof(d.J_design);   Q_hi = Qof(d.J_hi);
fprintf('per-train flow band : %.1f / %.1f / %.1f m3/h\n', Q_lo, Q_de, Q_hi);

%% ============ 4.  REQUIRED SPEED, CLOSED FORM  ========================
% c*n^2 + (b*Q)*n + (a*Q^2 - Hsys) = 0  ->  take the positive root
a = pH(1);  b = pH(2);  c = pH(3);
speedFor = @(Q,H) ( -b*Q + sqrt( max((b*Q).^2 - 4*c*(a*Q.^2 - H), 0) ) ) ./ (2*c);

%% ============ 5.  SWEEP THE BAND OVER THE YEAR  ======================
nD   = numel(dates);
Jset = (d.J_lo : 0.25 : d.J_hi)';          % commanded flux values
nJ   = numel(Jset);

Qset  = Qof(Jset);                          % m3/h, one per flux
Hreq  = zeros(nJ,nD);  nreq = zeros(nJ,nD);
eta   = zeros(nJ,nD);  Psh  = zeros(nJ,nD);  Pel = zeros(nJ,nD);
okSpd = false(nJ,nD);

for t = 1:nD
    H = Hsys(Qset, t);                      % [nJ x 1]
    n = speedFor(Qset, H);
    e = polyval(pEta, Qset ./ max(n,eps));  % efficiency along similarity

    Hreq(:,t) = H;
    nreq(:,t) = n;
    eta(:,t)  = e;
    okSpd(:,t)= (n >= n_min) & (n <= n_max) & (e > 0.05);

    % shaft power per train, kW:  rho*g*Q*H / eta
    Psh(:,t) = 1025*9.81 .* (Qset/3600) .* H ./ max(e,eps) / 1000;
    Pel(:,t) = Psh(:,t) / (eta_motor*eta_vfd);
end

%% ============ 6.  THE DESIGN POINT THROUGH THE YEAR  =================
[~, iDes] = min(abs(Jset - d.J_design));
n_des   = nreq(iDes,:);      eta_des = eta(iDes,:);
Pel_des = Pel(iDes,:);       H_des   = Hreq(iDes,:);

Qp_train = d.J_design * A_train / 1000;              % m3/h permeate per train
SEC_el   = Pel_des / Qp_train;                       % kWh/m3
SEC_hyd  = 1025*9.81*(Q_de/3600).*H_des/1000 / Qp_train;

fprintf('\n--- at the design flux, across the year ---\n');
fprintf('required head      : %.0f - %.0f m\n', min(H_des), max(H_des));
fprintf('required speed     : %.3f - %.3f of nominal\n', min(n_des), max(n_des));
fprintf('efficiency         : %.3f - %.3f\n', min(eta_des), max(eta_des));
fprintf('electrical power   : %.1f - %.1f kW per train\n', min(Pel_des), max(Pel_des));
fprintf('                     %.1f - %.1f kW plant (%d trains)\n', ...
        k_trains*min(Pel_des), k_trains*max(Pel_des), k_trains);
fprintf('SEC hydraulic      : %.3f - %.3f kWh/m3\n', min(SEC_hyd), max(SEC_hyd));
fprintf('SEC electrical     : %.3f - %.3f kWh/m3  (mean %.3f)\n', ...
        min(SEC_el), max(SEC_el), mean(SEC_el));
fprintf('CHECK: electrical must exceed hydraulic -> %s\n', ...
        string(all(SEC_el > SEC_hyd)));

fprintf('\n--- band reachability ---\n');
fprintf('flux values holdable on every day : %d of %d\n', sum(all(okSpd,2)), nJ);
if ~all(okSpd(:))
    Jbad = Jset(~all(okSpd,2));
    fprintf('unreachable flux: %.2f - %.2f LMH (speed outside %.2f-%.2f)\n', ...
            min(Jbad), max(Jbad), n_min, n_max);
end

%% ====================== 7.  FIGURES  ==================================
figure('Name','pumpOperating 1/2 - curves','Color','w','Position',[80 300 700 540]);
hold on; grid on; box on;
Qp = linspace(0.3*Q_lo, 1.4*Q_hi, 300);
for n = [n_max 0.95 0.90 0.85 n_min]
    plot(Qp, a*Qp.^2 + b*Qp*n + c*n^2, '-', 'Color',[0.25 0.45 0.75]*n, ...
         'LineWidth',1.4, 'DisplayName',sprintf('pump, n = %.2f', n));
end
plot(Qp, Hsys(Qp, find(H_des==max(H_des),1)), 'r-', 'LineWidth',2.2, ...
     'DisplayName','system, worst day');
plot(Qp, Hsys(Qp, find(H_des==min(H_des),1)), 'b-', 'LineWidth',2.2, ...
     'DisplayName','system, best day');
xline(Q_lo,':k','HandleVisibility','off');  xline(Q_hi,':k','HandleVisibility','off');
plot(Q_de, max(H_des), 'ko', 'MarkerSize',9, 'MarkerFaceColor','k', ...
     'DisplayName','design duty');
xlabel('Flow per train  Q  (m^3/h)');  ylabel('Head  H  (m)');
ylim([0 1.15*c]);
title(sprintf('Pump and system curves - %s, %d trains\n%s', ...
      d.cfg_name, k_trains, CURVE_SOURCE));
legend('Location','southwest','Box','off','FontSize',8);

figure('Name','pumpOperating 2/2 - annual duty','Color','w','Position',[820 300 700 540]);
subplot(3,1,1); plot(dates, n_des, 'LineWidth',1.3); grid on;
ylabel('speed  n/n_{nom}'); title('Required speed at the design flux');
yline(n_min,'r:'); yline(n_max,'r:');
subplot(3,1,2); plot(dates, 100*eta_des, 'LineWidth',1.3); grid on;
ylabel('\eta  (%)'); title('Pump efficiency at the operating point');
subplot(3,1,3); plot(dates, SEC_el, 'LineWidth',1.3); hold on;
plot(dates, SEC_hyd, '--', 'LineWidth',1.1); grid on;
ylabel('SEC  (kWh/m^3)'); xlabel('date');
legend('electrical','hydraulic','Location','best','Box','off');
title('Specific energy - electrical must sit above hydraulic');

%% ============ 7c.  FIGURE 3 - PART LOAD ACROSS THE FLUX BAND =========
% At the design flux the flow is FIXED, so eta and speed barely move from
% day to day - that is why figure 2 looks flat.  The variation that matters
% for a PV plant happens across the BAND, as the plant turns down.
[~, tHot] = max(H_des);   [~, tCold] = min(H_des);

figure('Name','pumpOperating 3/3 - part load','Color','w','Position',[450 120 760 620]);

subplot(3,1,1); hold on; grid on; box on;
plot(Jset, nreq(:,tHot),  'r-', 'LineWidth',1.8, 'DisplayName','worst day');
plot(Jset, nreq(:,tCold), 'b-', 'LineWidth',1.8, 'DisplayName','best day');
yline(n_max,'k:','HandleVisibility','off');
yline(n_min,'k:','HandleVisibility','off');
xline(d.J_design,'k--','DisplayName','design flux');
ylabel('speed  n/n_{nom}');
title('Required speed across the flux band - outside the dotted lines is unreachable');
legend('Location','northwest','Box','off','FontSize',8);

subplot(3,1,2); hold on; grid on; box on;
plot(Jset, 100*eta(:,tHot),  'r-', 'LineWidth',1.8);
plot(Jset, 100*eta(:,tCold), 'b-', 'LineWidth',1.8);
xline(d.J_design,'k--');
ylabel('\eta  (%)');
title('Pump efficiency as the plant turns down - this is the part-load penalty');

subplot(3,1,3); hold on; grid on; box on;
Qp_set = Jset * A_train / 1000;                       % m3/h permeate per train
plot(Jset, Pel(:,tHot)./Qp_set,  'r-', 'LineWidth',1.8, 'DisplayName','worst day');
plot(Jset, Pel(:,tCold)./Qp_set, 'b-', 'LineWidth',1.8, 'DisplayName','best day');
xline(d.J_design,'k--','HandleVisibility','off');
xlabel('Commanded flux  J_w  (LMH)');
ylabel('SEC_{el}  (kWh/m^3)');
title('Electrical specific energy against turndown');
legend('Location','best','Box','off','FontSize',8);

%% ====================== 8.  SAVE (guarded)  ===========================
if CURVE_SOURCE == "DATASHEET"
    [~, base] = fileparts(SYSFILE);
    out = sprintf('pump_operating_%s_k%d.mat', erase(base,'system_curve_'), k_trains);
    save(out, 'd','k_trains','A_train','pH','pEta','CURVE_SOURCE', ...
         'Jset','Qset','Hreq','nreq','eta','Psh','Pel','okSpd', ...
         'n_des','eta_des','Pel_des','H_des','SEC_el','SEC_hyd','dates', ...
         'eta_motor','eta_vfd','n_min','n_max');
    fprintf('\nSaved %s\n', out);
else
    fprintf('\nNOT SAVED - CURVE_SOURCE is "%s".\n', CURVE_SOURCE);
    fprintf('Replace pH and pEta with digitised datasheet curves and set\n');
    fprintf('CURVE_SOURCE = "DATASHEET" to enable saving.\n');
end