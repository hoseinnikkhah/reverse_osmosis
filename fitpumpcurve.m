
clear; close all; clc;
fprintf('>>> running fitPumpCurve.m\n');

%% ====================== 1.  THE DIGITISED DATA  =======================
% ---- paste your two tables here ---------------------------------------
PUMP_LABEL = 'e-MP100B/09  (50Hz)';   % for the figure titles

% ---- THE DUTY POINT IS NO LONGER HARD CODED --------------------------
% It is derived from the same system-curve file the operating codes use,
% so it can never drift out of step with the design again.
%
%   BRANCH = "NOERD"  ->  the HP pump passes the whole feed,  Q_f
%   BRANCH = "ERD"    ->  the HP pump passes the permeate only, Q_p = R*Q_f
%                         (the PX and booster carry Q_b)
BRANCH   = "ERD";
SYSFILE  = 'system_curve_Conv_7e_96v_R35.mat';
k_trains = 3;              % must match the operating code
mix_fac  = 1.0105;         % ERD only: osmotic rise from PX mixing (1 = off)

S  = load(SYSFILE);
dd = S.design;
A_train_fit = dd.A_mem / k_trains;
Q_f_fit = dd.J_design * A_train_fit / (dd.R_set*1000);
Q_p_fit = dd.J_design * A_train_fit / 1000;

if BRANCH == "ERD"
    Q_DUTY = Q_p_fit;
    H_DUTY = max(mix_fac*S.pi_avg + dd.J_design./S.A_T) * S.bar2m;
else
    Q_DUTY = Q_f_fit;
    H_DUTY = max(S.pi_avg + dd.J_design./S.A_T) * S.bar2m;
    mix_fac = 1;
end

fprintf('branch %s : duty  Q = %.1f m3/h,  H = %.0f m\n', BRANCH, Q_DUTY, H_DUTY);
fprintf('  (per train, %d trains, A_train = %.0f m2, R = %.2f)\n', ...
        k_trains, A_train_fit, dd.R_set);
fprintf('  Q_f = %.1f   Q_p = %.1f   Q_b = %.1f  m3/h\n\n', ...
        Q_f_fit, Q_p_fit, Q_f_fit-Q_p_fit);

%           Q [m3/h]    H [m]
QH = [      26.56587473	772.2222222
            49.89200864	761.8863049
            75.16198704	745.3488372
            104.9676026	718.4754522
            130.237581	689.5348837
            150.3239741	658.5271318
            174.9460043	610.9819121
            200.2159827	551.0335917
            214.4708423	507.622739
            230.0215983	458.0103359
            244.924406	408.3979328
            259.8272138	350.5167959
            275.3779698	288.501292
            290.2807775	230.620155];

%           Q [m3/h]    P [kW]
QP = [      30.38793103	215.8536585
            47.84482759	234.1463415
            65.30172414	254.2682927
            80.17241379	270.7317073
            107.3275862	298.1707317
            125.4310345	316.4634146
            155.1724138	343.902439
            177.1551724	360.3658537
            200.4310345	375
            225	        384.1463415
            249.5689655	385.9756098
            275.4310345	376.8292683
            290.3017241	369.5121951];  
% -----------------------------------------------------------------------

if all(QH(:,2) == 0) || all(QP(:,2) == 0)
    error(['fitPumpCurve: the tables still contain zeros. Paste the ' ...
           'digitised head and power values first.']);
end

%% ====================== 2.  EFFICIENCY  ===============================
% put power on the same flows as head, then eta point by point
Q    = QH(:,1);
H    = QH(:,2);
P    = interp1(QP(:,1), QP(:,2), Q, 'linear', 'extrap');   % kW
eta  = Q .* H ./ (367 * P);                                % fraction

%% ====================== 3.  FIT  ======================================
pH   = polyfit(Q, H,   2);
pEta = polyfit(Q, eta, 2);

Hfit   = polyval(pH,   Q);
EtaFit = polyval(pEta, Q);
R2 = @(y,yh) 1 - sum((y-yh).^2)/sum((y-mean(y)).^2);

%% ====================== 4.  CHECKS  ===================================
fprintf('\n================== FIT CHECKS ==================\n');

ok = true;
if pH(1) >= 0
    fprintf('FAIL  pH(1) = %+.3e is not negative.\n', pH(1));
    fprintf('      A pump curve FALLS with flow.  A positive value means\n');
    fprintf('      a rising curve was digitised - check you used the HEAD\n');
    fprintf('      panel and not a system curve.\n');
    ok = false;
else
    fprintf('pass  pH(1) negative (curve falls with flow)\n');
end

if pEta(1) >= 0
    fprintf('FAIL  pEta(1) = %+.3e is not negative - efficiency must peak,\n', pEta(1));
    fprintf('      not rise without limit.\n');
    ok = false;
else
    Q_bep   = -pEta(2)/(2*pEta(1));
    eta_bep = polyval(pEta, Q_bep);
    fprintf('pass  efficiency peaks at %.0f m3/h, eta_BEP = %.3f\n', Q_bep, eta_bep);
    if eta_bep < 0.55 || eta_bep > 0.92
        fprintf('FAIL  eta_BEP = %.3f is outside 0.55-0.92.\n', eta_bep);
        if eta_bep > 0.92
            fprintf('      No pump this size reaches that.  eta = QH/(367P), so\n');
            fprintf('      too-high eta means the POWER was read too low.  The\n');
            fprintf('      usual cause is reading head and power from DIFFERENT\n');
            fprintf('      labelled curves on the page - the panels carry one\n');
            fprintf('      curve per stage count or impeller trim.  Confirm both\n');
            fprintf('      tables came from the same label.\n');
        end
        ok = false;
    end
    fprintf('      your duty %.0f m3/h is %.0f %% of BEP flow\n', ...
            Q_DUTY, 100*Q_DUTY/Q_bep);
    if Q_DUTY < 0.7*Q_bep || Q_DUTY > 1.2*Q_bep
        fprintf('WARN  duty outside 70-120 %% of BEP - consider another trim\n');
    end
end

fprintf('R2  head       : %.5f\n', R2(H,   Hfit));
fprintf('R2  efficiency : %.5f\n', R2(eta, EtaFit));
if R2(H,Hfit) < 0.995
    fprintf('WARN  head fit poor - add points or check axis calibration\n');
end

H_at_duty   = polyval(pH,   Q_DUTY);
eta_at_duty = polyval(pEta, Q_DUTY);
fprintf('------------------------------------------------\n');
fprintf('at %.0f m3/h the fitted curve gives H = %.0f m (need %.0f m)\n', ...
        Q_DUTY, H_at_duty, H_DUTY);
if H_at_duty < H_DUTY
    fprintf('NOTE  the pump is BELOW the required head at nominal speed.\n');
    fprintf('      It cannot reach this duty - pick a curve with more\n');
    fprintf('      stages or a larger trim.\n');
    ok = false;
else
    fprintf('pass  head available, margin %.0f m (%.1f %%)\n', ...
            H_at_duty-H_DUTY, 100*(H_at_duty-H_DUTY)/H_DUTY);
end
fprintf('efficiency at duty : %.3f\n', eta_at_duty);

% deadhead speed: where shutoff head n^2*c falls to the static osmotic head
fprintf('------------------------------------------------\n');
% Use the REAL osmotic pressure from the loaded design, not a round number.
% Worst case is the highest pi_avg of the year at zero flux: below that head
% the pump cannot push any permeate at all.
pi_head = max(mix_fac*S.pi_avg) * S.bar2m;        % m
fprintf('shutoff head at nominal speed : %.0f m\n', pH(3));
fprintf('max pi_avg this design        : %.2f bar  (%.0f m)\n', ...
        max(mix_fac*S.pi_avg), pi_head);
fprintf('the pump deadheads below\n');
fprintf('n = sqrt(%.0f/%.0f) = %.3f of nominal speed.\n', ...
        pi_head, pH(3), sqrt(pi_head/pH(3)));
fprintf('Use that as n_min if it exceeds the\n');
fprintf('mechanical minimum from the datasheet.\n');
fprintf('================================================\n\n');

%% ====================== 5.  WHAT TO PASTE  ============================
if BRANCH == "ERD", tgt = 'erdOperating.m'; else, tgt = 'pumpOperating.m'; end
fprintf('Paste these four lines into %s:\n\n', tgt);
fprintf('CURVE_SOURCE = "DATASHEET";\n');
fprintf('pH    = [%+.6e, %+.6e, %+.6e];\n', pH(1),   pH(2),   pH(3));
fprintf('pEta  = [%+.6e, %+.6e, %+.6e];\n', pEta(1), pEta(2), pEta(3));
fprintf('Q_FIT = [%.0f %.0f];\n', min(Q), max(Q));
fprintf('n_min = %.3f;\n\n', sqrt(pi_head/pH(3)));
if ~ok
    fprintf('*** CHECKS FAILED - fix the digitisation before using these ***\n\n');
end

%% ====================== 6.  VISUAL CHECK  =============================
Qs = linspace(min(Q)*0.9, max(Q)*1.05, 200);

figure('Name','fitPumpCurve - head','Color','w','Position',[80 350 640 460]);
hold on; grid on; box on;
plot(Q,  H,  'ko', 'MarkerFaceColor','k', 'DisplayName','digitised');
plot(Qs, polyval(pH,Qs), 'b-', 'LineWidth',1.8, 'DisplayName','quadratic fit');
plot(Q_DUTY, H_DUTY, 'ro', 'MarkerSize',6, 'MarkerFaceColor','r', ...
     'DisplayName','required duty');
xlabel('Q  (m^3/h)');  ylabel('H  (m)');
title(sprintf('%s - head\nR^2 = %.5f', PUMP_LABEL, R2(H,Hfit)));
legend('Location','southwest','Box','off');

figure('Name','fitPumpCurve - efficiency','Color','w','Position',[760 350 640 460]);
hold on; grid on; box on;
plot(Q,  100*eta,  'ko', 'MarkerFaceColor','k', 'DisplayName','from Q,H,P');
plot(Qs, 100*polyval(pEta,Qs), 'b-', 'LineWidth',1.8, 'DisplayName','quadratic fit');
xline(Q_DUTY, 'r:', 'LineWidth',1.5, 'Label','duty', 'HandleVisibility','off');
if pEta(1) < 0
    xline(-pEta(2)/(2*pEta(1)), 'k--', 'Label','BEP', 'HandleVisibility','off');
end
xlabel('Q  (m^3/h)');  ylabel('\eta  (%)');
title(sprintf('%s - efficiency, computed as QH/(367P)', PUMP_LABEL));
legend('Location','south','Box','off');