%% fitPumpCurve.m
%  Turn digitised manufacturer curves into the two coefficient vectors that
%  pumpOperating.m needs, with sanity checks and a visual fit check.
%
%  INPUT   two tables read off the catalogue chart for ONE labelled curve:
%            QH : flow [m3/h]  and head [m]        (top panel)
%            QP : flow [m3/h]  and shaft power [kW] (bottom panel)
%
%  EFFICIENCY is not published on this catalogue, so it is computed:
%            eta = rho*g*Q*H / P  =  Q*H / (367*P)
%  with Q in m3/h, H in m, P in kW.  The 367 = 3600/9.81 assumes
%  rho = 1000 kg/m3, which is what the catalogue footnote states the
%  curves are valid for.  DO NOT substitute seawater density here -
%  pumpOperating.m applies rho = 1025 when it computes power, and
%  efficiency is a ratio so density cancels out of it entirely.
%
%  OUTPUT  pH and pEta printed ready to paste, plus two check figures.

clear; close all; clc;
fprintf('>>> running fitPumpCurve.m\n');

%% ====================== 1.  THE DIGITISED DATA  =======================
% ---- paste your two tables here ---------------------------------------
PUMP_LABEL = 'e-MP150A/05  (curve <label>)';   % for the figure titles

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

%           Q [m3/h]             H [m]
QH = [      30.370370370370374	 687.4677003
            68.14814814814815	 670.9302325581397
            102.96296296296296	 652.3255813953489
            137.03703703703707	 623.3850129198968
            165.92592592592595	 592.3772609819123
            188.8888888888889	 561.3695090439277
            222.96296296296296	 499.3540051679588
            240.00000000000003	 462.14470284237734
            262.96296296296293	 408.3979328165375
            291.1111111111111	 329.8449612403101
            320	                 243.02325581395348
            331.1111111111111	 205.81395348837214 ];

%           Q [m3/h]       P [kW]
QP = [      28.83548983	186.5853659
            51.75600739	204.8780488
            80.59149723	228.6585366
            108.6876155	254.2682927
            131.6081331	272.5609756
            155.2680222	290.8536585
            183.3641405	309.1463415
            217.3752311	329.2682927
            258.0406654	340.2439024
            297.2273567	340.2439024
            331.9778189	327.4390244];  
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
fprintf('shutoff head at nominal speed : %.0f m\n', pH(3));
fprintf('if pi_avg is ~45 bar (447 m), the pump deadheads below\n');
fprintf('n = sqrt(447/%.0f) = %.3f of nominal speed.\n', pH(3), sqrt(447/pH(3)));
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
fprintf('n_min = %.3f;\n\n', sqrt(447/pH(3)));
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