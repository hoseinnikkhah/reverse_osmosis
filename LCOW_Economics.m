%% lcowEconomics.m
%  Levelised cost of water for every PV capacity in the dispatch sweep, and
%  the PV capacity that minimises it.
%
%  FORMULA  (Qudah et al. 2025, Eq. 4, wind-turbine and tank terms removed)
%     LCOW = [ (C_RO + C_PV + C_inv)*CRF + C_OM_RO + C_OM_PV + C_OM_inv
%              + C_rep + C_chm ] / sum_t Q_P(t)
%     CRF  = i(1+i)^N / ((1+i)^N - 1)
%
%  HOW THE MODEL ENTERS
%     sum Q_P      <- pvDispatch: PV output, Pel(J,d) i.e. SEC, okSpd,
%                     integer trains, curtailment
%     C_RO         <- design capacity k * Qp(J_design) * 24     (membrane level)
%                     bottom-up check: HP pump at worst feasible Hreq,
%                     PX at max Qb, element and vessel count
%     C_PV, OM_PV  <- P_peak, the optimisation variable
%     C_inv rep    <- inverter rated at max(p_unit) * P_peak
%     C_chm        <- annual feed  sum Q_P / R                  (explicit mode)
%     SEC does not appear explicitly.  In a PV-only plant energy has no
%     running cost - it is paid for through C_PV - so SEC acts on LCOW only
%     through sum Q_P (water per kWh) and through the PV size.
%
%  PROVENANCE TAGS  (same convention as erdOperating.m)
%     [LIT]  taken from a cited paper.  A '->' in the source names the
%            primary source that should replace it before publication.
%     [PH]   placeholder, no value yet.  Only needed by the optional modes.
%  Money in USD of COST_YEAR, constant (real) prices, no escalation over
%  the plant life, CAPEX paid up front at t = 0.
%
%  Inputs : erd_operating_<tag>_k<k>.mat, pv_dispatch_<tag>_<year>.mat,
%           pv_generation.mat
%  Output : lcow_<tag>.mat, lcow_parameters.csv, a report, three figures

clear; close all; clc;
fprintf('>>> running lcowEconomics.m\n');

%% ====================== 1.  SETTINGS  =================================
% ---- edit this block only ---------------------------------------------
ERDFILE   = 'erd_operating_Conv_7e_96v_R35_k3.mat';
PVFILE    = 'pv_generation.mat';
DISPFILES = {'pv_dispatch_Conv_7e_96v_R35_k3_2021.mat'};
            % first file = base case.  Add the 2020 and 2022 dispatch runs
            % to get the inter-annual band on LCOW.

CAPEX_METHOD = "topdown";    % "topdown"  : specific cost x design capacity
                             % "bottomup" : Lu et al. 2007 RO island / f_island
OPEX_METHOD  = "lumped";     % "lumped"   : one variable USD/m3 (Janowitz)
                             % "explicit" : chemicals + membranes + other
COST_YEAR = 2022;
SENS_FRAC = 0.30;            % +/- range on cost items in the tornado
I_RANGE   = [0.02 0.07];     % discount-rate range, as Janowitz 2025

%  name            value    unit               tag    source
PAR = {
 'i'               0.06     '1/yr'             'LIT'  'Qudah et al. 2025 Sec. 4.2'
 'N'               25       'yr'               'LIT'  'Qudah 2025 Sec. 4.2; Janowitz et al. 2025 Table 2'
 'c_RO_spec'       1037     'USD/(m3/d)'       'LIT'  'Janowitz 2025 Table 2 -> Voutchkov 2018; Caldera & Breyer 2017'
 'f_island'        NaN      '-'                'PH'   'RO-island share of total SWRO CAPEX -> Voutchkov 2018 (bottomup only)'
 'c_element_07'    1200     'USD(2007)/elem'   'LIT'  'Lu et al. 2007 Table 1 -> current DuPont quote'
 'c_vessel_07'     1000     'USD(2007)/vessel' 'LIT'  'Lu et al. 2007 Table 2'
 'k_invest'        1.411    '-'                'LIT'  'Lu et al. 2007 Eq. 41'
 'CEPCI_2007'      525.4    '-'                'LIT'  'Chemical Engineering CEPCI annual 2007 (verify)'
 'CEPCI_base'      816.0    '-'                'LIT'  'Chemical Engineering CEPCI annual 2022 (verify)'
 'om_fix_plant'    0.03     '1/yr of C_RO'     'LIT'  'Janowitz 2025 Table 2 -> Voutchkov 2018'
 'om_fix_infra'    0.01     '1/yr of C_RO'     'LIT'  'Janowitz 2025 Table 2 -> Voutchkov 2018'
 'c_labour'        0.04     'USD/m3 design'    'LIT'  'Janowitz 2025 Table 2 -> Voutchkov 2018'
 'c_var'           0.10     'USD/m3 produced'  'LIT'  'Janowitz 2025 Table 2 (chem, membranes, cartridges, disposal) -> Voutchkov 2018'
 'c_chem'          NaN      'USD/m3 feed'      'PH'   'Voutchkov 2018; doses DuPont FilmTec manual (explicit only)'
 'c_var_other'     NaN      'USD/m3 produced'  'PH'   'Voutchkov 2018: cartridges, disposal (explicit only)'
 'mem_rate'        0.10     '1/yr'             'LIT'  'Cervantes-Rendon et al. 2022 -> DuPont FilmTec manual (explicit only)'
 'c_PV'            820      'USD/kWp'          'LIT'  'Janowitz 2025 Table 3 (NREL Q1-2022, US tracking) -> IRENA RPGC 2024, Italy'
 'om_PV'           16.42    'USD/kWp/yr'       'LIT'  'Janowitz 2025 Table 3 -> IRENA RPGC 2024'
 'c_inv'           0        'USD/kW_ac'        'LIT'  'inside installed PV cost (IRENA balance of system)'
 'c_inv_rep'       650      'USD/kW_ac'        'LIT'  'Qudah 2025 Sec. 3.3 (small-scale, high) -> IRENA / NREL utility inverter'
 'L_inv'           15       'yr'               'LIT'  'Qudah 2025 Sec. 3.3'
 };
% -----------------------------------------------------------------------

Ptab = cell2table(PAR, 'VariableNames', {'name','value','unit','tag','source'});
p    = cell2struct(PAR(:,2), PAR(:,1), 1);

%% ====================== 2.  LOAD  =====================================
E = load(ERDFILE);
V = load(PVFILE);

nY = numel(DISPFILES);
DS = cell(nY,1);  yrs = zeros(nY,1);
for y = 1:nY
    DS{y}  = load(DISPFILES{y});
    yrs(y) = double(DS{y}.PV_YEAR);
end
Pk = double([DS{1}.res.P_peak]');   nP = numel(Pk);
for y = 2:nY
    assert(isequal(double([DS{y}.res.P_peak]'), Pk), ...
        'lcowEconomics: %s uses a different P_SWEEP from the base case', DISPFILES{y});
end

%% ============ 3.  DESIGN QUANTITIES FROM THE MODEL  ===================
kt    = double(E.k_trains);
R     = double(E.d.R_set);
nVess = double(E.d.n_vess);
nEl   = double(E.d.n_elem) * nVess;
Jset  = double(E.Jset(:));
Qp_d  = interp1(Jset, double(E.Qp_set(:)), double(E.d.J_design));   % m3/h per train
Cap   = kt * Qp_d * 24;                                              % m3/d

ok    = logical(E.okSpd);
Jok   = any(ok, 2);
Hmax  = max(E.Hreq(ok));                    % m, worst feasible duty of the year
Qhpp  = max(E.Qp_set(Jok));                 % m3/h, HP pump flow with ERD = Qp
Qbmax = max(E.Qb_set(Jok));                 % m3/h, PX flow
dPmax = 1027 * 9.81 * Hmax / 1e5;           % bar, seawater 1027 kg/m3
pu_max = max(V.pv.p_unit);                  % kW_ac per kWp, all solar years

%% ============ 4.  SWRO CAPITAL  =======================================
esc   = p.CEPCI_base / p.CEPCI_2007;
C_top = p.c_RO_spec * Cap;

% Lu et al. 2007 Eqs 41-45.  Units read as bar x m3/h: with Lu's MPa the
% HP pump for ~600 kW hydraulic would cost ~80 kUSD, which is implausible;
% bar gives ~0.35 MUSD (2007).  Verify against Malek et al. 1996.
CC_hpp = 52 * (dPmax * Qhpp)^0.96;
CC_px  = 3134.7 * Qbmax^0.58;
C_mem  = nEl * p.c_element_07 + nVess * p.c_vessel_07;
C_isl  = (kt * (CC_hpp + CC_px) + C_mem) * p.k_invest * esc;   % RO island only

switch CAPEX_METHOD
    case "topdown"
        C_RO = C_top;
    case "bottomup"
        assert(~isnan(p.f_island), ...
            'lcowEconomics: bottomup needs f_island (Voutchkov 2018 cost breakdown)');
        C_RO = C_isl / p.f_island;
    otherwise
        error('lcowEconomics: CAPEX_METHOD must be "topdown" or "bottomup"');
end
if OPEX_METHOD == "explicit"
    assert(~any(isnan([p.c_chem p.c_var_other])), ...
        'lcowEconomics: explicit OPEX needs c_chem and c_var_other (Voutchkov 2018)');
elseif OPEX_METHOD ~= "lumped"
    error('lcowEconomics: OPEX_METHOD must be "lumped" or "explicit"');
end

%% ============ 5.  LCOW FOR EVERY PV CAPACITY  =========================
Y = struct('year', num2cell(yrs));
for y = 1:nY
    r = DS{y}.res;
    W = double([r.water]');
    Y(y).W    = W;
    Y(y).util = double([r.util]');
    Y(y).SEC  = double([r.SEC]');
    Y(y).c    = lcowCore(p, Pk, W, C_RO, Cap, R, nEl, esc, pu_max, OPEX_METHOD);
end
c = Y(1).c;   W = Y(1).W;
[LCOWmin, iOpt] = min(c.LCOW);
Popt = Pk(iOpt);

%% ============ 6.  SENSITIVITY AT THE OPTIMUM  =========================
%  label                    key          low factor          high factor
sens = {
 'discount rate i'          'i'          I_RANGE(1)/p.i      I_RANGE(2)/p.i
 'SWRO CAPEX'               'C_RO'       1-SENS_FRAC         1+SENS_FRAC
 'PV CAPEX'                 'c_PV'       1-SENS_FRAC         1+SENS_FRAC
 'SWRO fixed O&M + labour'  'om_fix'     1-SENS_FRAC         1+SENS_FRAC
 'variable O&M'             'var'        1-SENS_FRAC         1+SENS_FRAC
 'inverter replacement'     'c_inv_rep'  1-SENS_FRAC         1+SENS_FRAC
 };
nS = size(sens,1);   Lr = zeros(nS,2);
for s = 1:nS
    for e = 1:2
        q = p;  CR = C_RO;  f = sens{s,2+e};
        switch sens{s,2}
            case 'C_RO'
                CR = C_RO * f;
            case 'om_fix'
                q.om_fix_plant = p.om_fix_plant * f;
                q.om_fix_infra = p.om_fix_infra * f;
                q.c_labour     = p.c_labour * f;
            case 'var'
                q.c_var = p.c_var * f;  q.c_chem = p.c_chem * f;
                q.c_var_other = p.c_var_other * f;  q.mem_rate = p.mem_rate * f;
            otherwise
                q.(sens{s,2}) = p.(sens{s,2}) * f;
        end
        cc = lcowCore(q, Pk(iOpt), W(iOpt), CR, Cap, R, nEl, esc, pu_max, OPEX_METHOD);
        Lr(s,e) = cc.LCOW;
    end
end

%% ====================== 7.  REPORT  ===================================
sep  = repmat('=',1,78);  dash = repmat('-',1,78);
fprintf('\n%s\nLCOW, USD %d, CAPEX %s, OPEX %s\n%s\n', sep, COST_YEAR, ...
        CAPEX_METHOD, OPEX_METHOD, dash);
fprintf('plant : %d x %d vessels, R = %.0f %%, %d trains, design flux %.1f LMH\n', ...
        double(E.d.n_elem), nVess, 100*R, kt, double(E.d.J_design));
fprintf('design capacity          : %8.0f m3/d\n', Cap);
fprintf('CRF (i = %.1f %%, N = %d) : %8.4f\n', 100*p.i, p.N, ...
        p.i*(1+p.i)^p.N/((1+p.i)^p.N-1));
fprintf('SWRO CAPEX, top-down     : %8.2f MUSD (%.0f USD per m3/d)\n', C_top/1e6, p.c_RO_spec);
fprintf('RO island, Lu bottom-up  : %8.2f MUSD = %.0f %% of top-down\n', ...
        C_isl/1e6, 100*C_isl/C_top);
fprintf('   HP pump %.0f kUSD x %d at %.1f bar, %.0f m3/h;  PX %.0f kUSD x %d\n', ...
        CC_hpp*esc*p.k_invest/1e3, kt, dPmax, Qhpp, CC_px*esc*p.k_invest/1e3, kt);
fprintf('   (compare the island share with the Voutchkov 2018 cost breakdown)\n');
fprintf('%s\n', dash);
fprintf('%6s %10s %6s %6s %7s | %6s %6s %6s %6s %6s %6s\n', 'kWp', 'water m3', ...
        'util%', 'SEC', 'LCOW', 'capRO', 'capPV', 'omRO', 'omPV', 'rep', 'var');
for k = 1:nP
    fprintf('%6d %10.0f %6.1f %6.3f %7.3f | %6.3f %6.3f %6.3f %6.3f %6.3f %6.3f%s\n', ...
        Pk(k), W(k), 100*Y(1).util(k), Y(1).SEC(k), c.LCOW(k), ...
        c.capRO(k)/W(k), c.capPV(k)/W(k), c.omRO(k)/W(k), c.omPV(k)/W(k), ...
        (c.repInv(k)+c.repMem(k))/W(k), (c.var(k)+c.chm(k))/W(k), ...
        repmat('  <- min', 1, double(k==iOpt)));
end
fprintf('%s\n', dash);
fprintf('minimum LCOW %.3f USD/m3 at %d kWp  (PV/SWRO = %.2f kWp per m3/h of capacity)\n', ...
        LCOWmin, Popt, Popt/(Cap/24));
if iOpt == 1 || iOpt == nP
    warning('LCOW minimum is at the edge of P_SWEEP (%d kWp): extend the sweep in pvDispatch.m', Popt);
end
if nY > 1
    Lopt = arrayfun(@(s) s.c.LCOW(iOpt), Y);
    fprintf('inter-annual band at %d kWp : %.3f - %.3f USD/m3 (solar years %s)\n', ...
            Popt, min(Lopt), max(Lopt), mat2str(yrs'));
end
fprintf('\nsensitivity at %d kWp (design held fixed):\n', Popt);
for s = 1:nS
    fprintf('  %-26s %.3f / %.3f USD/m3\n', sens{s,1}, Lr(s,1), Lr(s,2));
end

ph = Ptab.name(strcmp(Ptab.tag,'PH'));
if ~isempty(ph)
    fprintf('\nplaceholders (needed only by the optional modes): %s\n', strjoin(ph', ', '));
end
upg = Ptab.name(contains(Ptab.source,'->'));
fprintf('interim values to replace from the primary source before publication:\n  %s\n', ...
        strjoin(upg', ', '));
fprintf('%s\n\n', sep);

%% ====================== 8.  FIGURES  ==================================
figure('Name','lcow 1/3 - LCOW against PV capacity','Color','w','Position',[60 300 760 480]);
yyaxis left;  hold on;  grid on;  box on;
for y = 1:nY
    plot(Pk, Y(y).c.LCOW, 'o-', 'LineWidth', 1.8 - 0.6*(y>1));
end
plot(Popt, LCOWmin, 'kp', 'MarkerSize', 14, 'MarkerFaceColor', 'y');
ylabel(sprintf('LCOW  (USD_{%d}/m^3)', COST_YEAR));
yyaxis right;
plot(Pk, W/1e3, 's--', 'LineWidth', 1.2);
ylabel('annual permeate  (10^3 m^3)');
xlabel('installed PV capacity  (kWp)');
legend([arrayfun(@(v) sprintf('LCOW, solar %d', v), yrs', 'uni', 0), ...
        {'minimum', 'permeate'}], 'Location', 'north', 'Box', 'off');
title('Small arrays leave the SWRO idle; large arrays are curtailed');

figure('Name','lcow 2/3 - cost structure','Color','w','Position',[840 300 760 480]);
comp = [c.capRO c.capPV c.omRO c.omPV c.repInv c.repMem c.var c.chm] ./ W;
lab  = {'SWRO capital','PV capital','SWRO fixed O&M','PV O&M', ...
        'inverter replacement','membrane replacement','variable O&M','chemicals'};
use  = any(comp > 0, 1);
bar(1:nP, comp(:,use), 'stacked');  grid on;  box on;
xticks(1:nP);  xticklabels(string(Pk));
xlabel('installed PV capacity  (kWp)');  ylabel('USD / m^3');
legend(lab(use), 'Location', 'northeast', 'Box', 'off');
title('SWRO capital is spread over more water as PV grows');

figure('Name','lcow 3/3 - sensitivity','Color','w','Position',[60 60 760 420]);
[~, ord] = sort(abs(Lr(:,2) - Lr(:,1)));
base = LCOWmin;
hold on;  grid on;  box on;
barh(1:nS, Lr(ord,1) - base, 'FaceColor', [0.20 0.45 0.75]);
barh(1:nS, Lr(ord,2) - base, 'FaceColor', [0.85 0.40 0.10]);
yticks(1:nS);  yticklabels(sens(ord,1));
xlabel(sprintf('change in LCOW from %.3f USD/m^3', base));
legend('low value', 'high value', 'Location', 'southeast', 'Box', 'off');
title(sprintf('Sensitivity at %d kWp', Popt));

%% ====================== 9.  SAVE  =====================================
[~, tag] = fileparts(ERDFILE);
tag = erase(tag, 'erd_operating_');
out = sprintf('lcow_%s.mat', tag);
save(out, 'Ptab', 'p', 'Pk', 'Y', 'yrs', 'C_RO', 'C_top', 'C_isl', 'Cap', ...
     'Popt', 'LCOWmin', 'sens', 'Lr', 'CAPEX_METHOD', 'OPEX_METHOD', ...
     'COST_YEAR', 'DISPFILES', 'ERDFILE');
writetable(Ptab, 'lcow_parameters.csv');
fprintf('Saved %s and lcow_parameters.csv\n', out);

%% ====================== LOCAL FUNCTION  ===============================
function c = lcowCore(p, P, W, C_RO, Cap, R, nEl, esc, pu_max, opexMode)
%  Annual cost terms (USD/yr) and LCOW (USD/m3) for PV capacities P (kWp)
%  and annual permeate W (m3/yr), both column vectors of equal length.
    a     = p.i*(1+p.i)^p.N / ((1+p.i)^p.N - 1);
    P_ac  = pu_max .* P;
    tRep  = p.L_inv : p.L_inv : p.N-1;
    pvRep = sum((1+p.i).^(-tRep));
    one   = ones(size(P));

    c.capRO  = C_RO * a * one;
    c.capPV  = (p.c_PV .* P + p.c_inv .* P_ac) * a;
    c.omRO   = ((p.om_fix_plant + p.om_fix_infra) * C_RO + p.c_labour * Cap * 365) * one;
    c.omPV   = p.om_PV .* P;
    c.repInv = p.c_inv_rep .* P_ac * pvRep * a;
    if opexMode == "lumped"
        c.var    = p.c_var .* W;
        c.chm    = 0 * W;
        c.repMem = 0 * W;
    else
        c.var    = p.c_var_other .* W;
        c.chm    = p.c_chem .* W ./ R;
        c.repMem = p.mem_rate * nEl * p.c_element_07 * esc * one;
    end
    c.total = c.capRO + c.capPV + c.omRO + c.omPV + c.repInv + c.repMem + c.var + c.chm;
    c.LCOW  = c.total ./ W;
end