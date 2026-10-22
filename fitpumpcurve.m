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
Q_DUTY     = 390.5;    % m3/h, your design flow  - checked against BEP
H_DUTY     = 584;      % m,    your design head

%           Q [m3/h]    H [m]
QH = [      260.75	    719.5121951
            299.25	    702.4390244
            339.5	    682.9268293
            379.75	    660.9756098
            420	        631.7073171
            460.25	    602.4390244
            500.5	    573.1707317
            539	        539.0243902
            581	        500
            619.5	    458.5365854
            647.5	    419.5121951
            659.75	    400     ];

%            Q [m3/h]       P [kW]
QP = [       250            0
            260.0997506	    760.3305785
            300.2493766	    800.8264463
            340.3990025	    841.322314
            380.5486284 	881.8181818
            420.6982544	    910.7438017
            459.1022444 	939.6694215
            499.2518703	    962.8099174
            539.4014963	    980.1652893
            579.5511222 	991.7355372
            619.7007481 	997.5206612
            659.8503741	    974.3801653   ];  
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
        fprintf('WARN  eta_BEP outside 0.55-0.92 - recheck the power digitisation\n');
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
fprintf('Use that as n_min in pumpOperating.m if it exceeds the\n');
fprintf('mechanical minimum from the datasheet.\n');
fprintf('================================================\n\n');

%% ====================== 5.  WHAT TO PASTE  ============================
fprintf('Paste these two lines into pumpOperating.m:\n\n');
fprintf('CURVE_SOURCE = "DATASHEET";\n');
fprintf('pH   = [%+.6e, %+.6e, %+.6e];\n', pH(1),   pH(2),   pH(3));
fprintf('pEta = [%+.6e, %+.6e, %+.6e];\n\n', pEta(1), pEta(2), pEta(3));
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