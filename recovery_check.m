%% recovery_check.m
%  Justify the choice of system recovery, from the stored data.
%
%  Recovery sets two things that pull in opposite directions:
%
%  COST OF LOW RECOVERY - energy
%      SEC_hyd = 0.027778 * dP / R
%      Raising R puts more in the denominator than it adds to dP, so
%      specific energy FALLS as recovery rises.  Low recovery is expensive.
%
%  COST OF HIGH RECOVERY - operating range
%      Concentration at the brine end goes as C_f/(1-R) while the average
%      only goes as C_f(2-R)/2(1-R).  The gap is the minimum flux that
%      still produces permeate:
%          J_min(T) = A(T) * [pi(C_b) - pi(C_avg)]
%                   = A(T) * pi(C_f) * R / (2(1-R))
%      That factor is 0.269 at R = 0.35 and 0.500 at R = 0.50.  Once J_min
%      climbs past the bottom of the design flux band, the plant loses
%      turndown; once it passes the top, the configuration cannot run at
%      all on the worst day.
%
%  This script computes both across the stored recovery grid, for all four
%  pretreatment configurations, and reports the usable band width.
%
%  Inputs : design_data.mat, osmotic_pressure_recovery.mat,
%           A_temp_data.mat, salinity_and_temp_mean.mat
%  Output : recovery_check.csv  (+ two figures)

clear; close all; clc;
fprintf('>>> running recovery_check.m\n');

%% ====================== 1.  SETTINGS  =================================
% ---- edit this block only ---------------------------------------------
CFGS   = ["Conventional pretreatment"
          "Generic membrane filtration"
          "Well/open intake + UF"
          "UF + B-free"];
P_max  = 83;        % element pressure rating, bar
R_PICK = 35;        % the recovery currently used, marked on the figures
% -----------------------------------------------------------------------

%% ====================== 2.  LOAD  =====================================
D  = load('design_data.mat');
O  = load('osmotic_pressure_recovery.mat');
Ad = load('A_temp_data.mat');
S  = load('salinity_and_temp_mean.mat','T_daily_mean','dates');

A_T  = interp1(Ad.A_block(1,:), Ad.A_block(2,:), S.T_daily_mean);  % LMH/bar
Rgrid = O.recovery(:);                       % percent, e.g. 30:1:60
nR    = numel(Rgrid);
nC    = numel(CFGS);

%% ====================== 3.  SWEEP RECOVERY  ===========================
Jmin   = zeros(nR,1);                 % worst-day minimum flux, LMH
Jlo    = zeros(nC,1);  Jhi = zeros(nC,1);  Jdes = zeros(nC,1);
dPdes  = zeros(nR,nC); SEC = zeros(nR,nC);
UsableLo = zeros(nR,nC);              % effective band bottom = max(J_lo, J_min)
BandUse  = zeros(nR,nC);              % usable share of the band, %
Status   = strings(nR,nC);

for c = 1:nC
    k = find(D.config.Name == CFGS(c), 1);
    assert(~isempty(k), 'Unknown configuration "%s".', CFGS(c));
    band    = D.config.J_design{k};
    Jlo(c)  = min(band);  Jhi(c) = max(band);
    Jdes(c) = round(((Jlo(c)+Jhi(c))/2)/0.5)*0.5;
end

for r = 1:nR
    pi_avg = O.osmotic_pressure_C_avg(r,:);
    pi_b   = O.osmotic_pressure_C_brine(r,:);

    % minimum flux for positive driving force, worst day of the year
    Jmin(r) = max(A_T .* (pi_b - pi_avg));

    for c = 1:nC
        dP          = pi_avg + Jdes(c) ./ A_T;
        dPdes(r,c)  = max(dP);                                  % worst day
        SEC(r,c)    = 1e5*dPdes(r,c)/(3.6e6 * Rgrid(r)/100);    % kWh/m3 hydraulic

        lo = max(Jlo(c), Jmin(r));
        UsableLo(r,c) = lo;
        BandUse(r,c)  = 100*max(0, (Jhi(c)-lo))/(Jhi(c)-Jlo(c));

        if Jmin(r) >= Jhi(c)
            Status(r,c) = "infeasible";          % no flux works
        elseif dPdes(r,c) >= P_max
            Status(r,c) = "over-pressure";
        elseif Jmin(r) > Jdes(c)
            Status(r,c) = "design flux lost";    % midpoint unreachable
        elseif Jmin(r) > Jlo(c)
            Status(r,c) = "band clipped";
        else
            Status(r,c) = "full band";
        end
    end
end

%% ====================== 4.  REPORT  ===================================
fprintf('\n=============== RECOVERY SWEEP (worst day) ===============\n');
fprintf('%4s %8s', 'R %%', 'J_min');
for c = 1:nC, fprintf(' | %-28s', extractBefore(CFGS(c)+"                    ",20)); end
fprintf('\n%4s %8s', '', 'LMH');
for c = 1:nC, fprintf(' | %7s %6s %12s', 'dP bar', 'SEC', 'status'); end
fprintf('\n');
for r = 1:nR
    if mod(Rgrid(r),5) ~= 0 && Rgrid(r) ~= R_PICK, continue; end   % every 5 %
    mark = ' ';  if Rgrid(r) == R_PICK, mark = '*'; end
    fprintf('%s%3d %8.2f', mark, Rgrid(r), Jmin(r));
    for c = 1:nC
        fprintf(' | %7.2f %6.3f %12s', dPdes(r,c), SEC(r,c), Status(r,c));
    end
    fprintf('\n');
end
fprintf('* = the recovery currently used.  "band clipped" means J_min has\n');
fprintf('risen above the band bottom, so turndown is lost from below.\n');
fprintf('==========================================================\n\n');

% flat table for the paper
Rpct=[]; Cfg=strings(0,1); Jm=[]; dPc=[]; SECc=[]; Usable=[]; Stat=strings(0,1);
for c = 1:nC
    Rpct   = [Rpct;   Rgrid];                      %#ok<AGROW>
    Cfg    = [Cfg;    repmat(CFGS(c),nR,1)];       %#ok<AGROW>
    Jm     = [Jm;     Jmin];                       %#ok<AGROW>
    dPc    = [dPc;    dPdes(:,c)];                 %#ok<AGROW>
    SECc   = [SECc;   SEC(:,c)];                   %#ok<AGROW>
    Usable = [Usable; BandUse(:,c)];               %#ok<AGROW>
    Stat   = [Stat;   Status(:,c)];                %#ok<AGROW>
end
T = table(Cfg, Rpct, Jm, dPc, SECc, Usable, Stat, 'VariableNames', ...
    {'Configuration','Recovery_pct','Jmin_LMH','dP_design_bar', ...
     'SEChyd_kWhm3','BandUsable_pct','Status'});
writetable(T,'recovery_check.csv');

%% ========= 5.  FIGURE 1 - J_min against the four design bands =========
figure('Name','recovery_check 1/2 - driving force limit','Color','w', ...
       'Position',[80 300 760 560]);
hold on; grid on; box on;
col = lines(nC);
for c = 1:nC
    patch([Rgrid(1) Rgrid(end) Rgrid(end) Rgrid(1)], ...
          [Jlo(c) Jlo(c) Jhi(c) Jhi(c)], col(c,:), ...
          'FaceAlpha',0.10, 'EdgeColor',col(c,:), 'LineStyle',':', ...
          'DisplayName',sprintf('%s  band %.0f-%.0f LMH', CFGS(c), Jlo(c), Jhi(c)));
end
plot(Rgrid, Jmin, 'k-', 'LineWidth',2.4, ...
     'DisplayName','J_{min} = A(T)\pi(C_f)R/(2(1-R))   worst day');
xline(R_PICK, 'k:', 'LineWidth',1.6, 'Label',sprintf('R = %d %%',R_PICK), ...
      'LabelOrientation','horizontal', 'HandleVisibility','off');
xlabel('System recovery  R  (%)');
ylabel('Permeate flux  J_w  (LMH)');
ylim([0 max(Jhi)*1.3]);  xlim([Rgrid(1) Rgrid(end)]);
title(['Why recovery is limited: the minimum workable flux climbs with R' newline ...
       'where the black line enters a band, that band starts losing turndown']);
legend('Location','northwest','Box','off','FontSize',8);

%% ========= 6.  FIGURE 2 - the trade-off: energy vs operating range ====
figure('Name','recovery_check 2/2 - the trade-off','Color','w', ...
       'Position',[870 300 700 560]);

subplot(2,1,1); hold on; grid on; box on;
for c = 1:nC
    plot(Rgrid, SEC(:,c), '-', 'Color',col(c,:), 'LineWidth',1.8, ...
         'DisplayName',CFGS(c));
end
xline(R_PICK,'k:','LineWidth',1.4,'HandleVisibility','off');
xlabel('System recovery  R  (%)');
ylabel('SEC_{hyd}  (kWh/m^3)');
title('Higher recovery is cheaper on energy');
legend('Location','northeast','Box','off','FontSize',8);

subplot(2,1,2); hold on; grid on; box on;
for c = 1:nC
    plot(Rgrid, BandUse(:,c), '-', 'Color',col(c,:), 'LineWidth',1.8, ...
         'DisplayName',CFGS(c));
end
xline(R_PICK,'k:','LineWidth',1.4,'HandleVisibility','off');
xlabel('System recovery  R  (%)');
ylabel('Usable share of design band  (%)');
ylim([-2 105]);
title('...and costs operating range, which a PV plant needs');
legend('Location','southwest','Box','off','FontSize',8);

fprintf('Saved recovery_check.csv\n');