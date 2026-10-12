function out = systemCurve(n_elem, n_vess, R_set, J_design, cfg_name, plotMode)
%SYSTEMCURVE  Annual system curve for one PV-SWRO design point.
%
%   The system curve is the pressure the high-pressure pump must deliver to
%   sustain a given feed flow, for every day of the year:
%
%       dP(J,t) = pi_avg(R,t) + J / A(T(t))                        [bar]
%       Q_f(J)  = J * A_mem * (24/1000) / R                        [m3/d]
%
%   Note that dP depends only on recovery, seawater salinity and seawater
%   temperature.  It carries no pretreatment term and no membrane-area term.
%   The pretreatment configuration fixes WHERE on that curve the plant is
%   allowed to sit (the design flux band) and HOW FAR the curve extends
%   (the maximum element flux).  The vessel/element count fixes only the
%   Q_f axis, through A_mem.
%
% SYNTAX
%   out = systemCurve(n_elem, n_vess)
%   out = systemCurve(n_elem, n_vess, R_set, J_design, cfg_name, plotMode)
%
% INPUTS
%   n_elem    elements per pressure vessel                 5, 6 or 7
%   n_vess    number of pressure vessels                   1 ... 150
%   R_set     system recovery, fraction                    default 0.35
%   J_design  design permeate flux, LMH                    default = midpoint
%             of this configuration's design band (14.5 / 15.5 / 17 / 19)
%   cfg_name  pretreatment configuration, one of
%               "UF + B-free"                   band 17-21, J_max 38
%               "Well/open intake + UF"         band 15-19, J_max 36
%               "Generic membrane filtration"   band 14-17, J_max 34
%               "Conventional pretreatment"     band 12-17, J_max 32
%             default "Conventional pretreatment"
%   plotMode  "off" | "new" | "add"                        default "off"
%               "off"  no figure
%               "new"  clear the shared figure, then draw this design
%               "add"  overlay this design on the shared figure
%
% OUTPUT  out  struct with the curve, the feasibility masks, the design
%              point and the pump duty.
%
% REQUIRES  design_data.mat, osmotic_pressure_recovery.mat,
%           A_temp_data.mat, salinity_and_temp_mean.mat

% ------------------------------------------------------------------------
% 0.  defaults
% ------------------------------------------------------------------------
if nargin < 3 || isempty(R_set),    R_set    = 0.35;                       end
if nargin < 4,                      J_design = [];                         end
if nargin < 5 || isempty(cfg_name), cfg_name = "Conventional pretreatment"; end
if nargin < 6 || isempty(plotMode), plotMode = "off";                      end

cfg_name = string(cfg_name);
plotMode = lower(string(plotMode));
if ~ismember(plotMode, ["off" "new" "add"])
    error('systemCurve: plotMode must be "off", "new" or "add".');
end

% ------------------------------------------------------------------------
% 1.  cached inputs  (loaded once per MATLAB session)
% ------------------------------------------------------------------------
persistent D O Ad S
if isempty(D)
    D  = load('design_data.mat');                 % config, ceil_recovery, N_elements, N_vessels, total_A
    O  = load('osmotic_pressure_recovery.mat');   % recovery, osmotic_pressure_C_avg, osmotic_pressure_C_brine
    Ad = load('A_temp_data.mat');                 % A_block = [T ; A(T) in LMH/bar]
    S  = load('salinity_and_temp_mean.mat','T_daily_mean','S_daily_mean','dates');
end
dates = S.dates;                                  % promote out of the struct

% ------------------------------------------------------------------------
% 2.  index lookups
% ------------------------------------------------------------------------
k  = find(D.config.Name == cfg_name, 1);
iE = find(D.N_elements  == n_elem,   1);
iV = find(D.N_vessels   == n_vess,   1);
iR = find(abs(O.recovery - R_set*100) < 1e-9, 1);

if isempty(k)
    error('systemCurve: unknown configuration "%s". Valid: %s', ...
          cfg_name, strjoin(cellstr(D.config.Name), ' | '));
end
if isempty(iE)
    error('systemCurve: n_elem = %g not in design grid [%s].', ...
          n_elem, num2str(D.N_elements));
end
if isempty(iV)
    error('systemCurve: n_vess = %g not in design grid 1..%d.', ...
          n_vess, max(D.N_vessels));
end
if isempty(iR)
    error('systemCurve: R_set = %.3f not in the stored recovery grid (%g..%g %%).', ...
          R_set, min(O.recovery), max(O.recovery));
end

% ------------------------------------------------------------------------
% 3.  configuration-dependent limits  (THE ONLY THINGS cfg_name CHANGES)
% ------------------------------------------------------------------------
J_band = D.config.J_design{k};
J_lo   = min(J_band);                 % bottom of design band,  LMH
J_hi   = max(J_band);                 % top of design band,     LMH
J_elem = D.config.J_max(k);           % max element flux,       LMH
r_e    = D.config.rec_max(k)/100;     % max element recovery,   fraction
R_ceil = D.ceil_recovery(iE,k);       % 1-(1-r_e)^n_elem,       fraction

% default design flux = band midpoint, snapped to the 0.5 LMH grid
if isempty(J_design)
    J_design = round(((J_lo + J_hi)/2)/0.5)*0.5;
end
inBand = (J_design >= J_lo) && (J_design <= J_hi);
if ~inBand
    warning('systemCurve:fluxOutOfBand', ...
        ['J_design = %.2f LMH is outside the design band of "%s" ' ...
         '(%.1f-%.1f LMH). Band midpoint is %.1f LMH.'], ...
         J_design, cfg_name, J_lo, J_hi, (J_lo+J_hi)/2);
end
if R_set >= R_ceil
    warning('systemCurve:aboveCeiling', ...
        ['R_set = %.1f %% is at or above the staging ceiling %.1f %% ' ...
         '(%d elements, r_e,max = %.0f %%).'], ...
         R_set*100, R_ceil*100, n_elem, r_e*100);
end

% ------------------------------------------------------------------------
% 4.  state variables
% ------------------------------------------------------------------------
A_mem  = D.total_A(iE,iV);                       % installed membrane area, m2
pi_avg = O.osmotic_pressure_C_avg(iR,:);         % pi at log-mean-ish C_avg, bar  [1 x 366]
pi_b   = O.osmotic_pressure_C_brine(iR,:);       % pi at brine C_b,          bar  [1 x 366]
A_T    = interp1(Ad.A_block(1,:), Ad.A_block(2,:), S.T_daily_mean);  % LMH/bar  [1 x 366]

LMH_to_m3d = 24/1000;
flux2Qf = @(J)  J  * A_mem * LMH_to_m3d / R_set;         % LMH  -> m3/d
Qf2flux = @(Qf) Qf * R_set * 1000 / (24 * A_mem);        % m3/d -> LMH

% ------------------------------------------------------------------------
% 5.  the system curve
% ------------------------------------------------------------------------
J_sweep = (0 : 0.25 : J_elem)';                  % starts at 0 so the intercept is pi(C_avg)
Qf      = flux2Qf(J_sweep);                      % m3/d
Hsys    = pi_avg + (J_sweep ./ A_T);             % bar  [nQ x 366]

dP_env_max = max(Hsys, [], 2);                   % hardest day of the year, per flux
dP_env_min = min(Hsys, [], 2);                   % easiest day of the year, per flux

% ------------------------------------------------------------------------
% 6.  feasibility
% ------------------------------------------------------------------------
P_max = 83;                                      % element / vessel pressure rating, bar

driving_ok  = Hsys >  pi_b;                      % net driving force positive
pressure_ok = Hsys <  P_max;                     % within the pressure rating
feasible    = driving_ok & pressure_ok;

% minimum flux that still produces permeate, exact closed form:
%   J_min = A(T) * [pi(C_b) - pi(C_avg)] = A(T) * pi(C_f) * R / (2(1-R))
% -> pretreatment-independent; set only by recovery, salinity, temperature
J_min_day = A_T .* (pi_b - pi_avg);              % LMH  [1 x 366]
[J_min_yr, iHard] = max(J_min_day);              % worst (highest-floor) day
[~, iEasy]        = min(J_min_day);
Qf_min_yr = flux2Qf(J_min_yr);                   % m3/d

turndown = 1 - J_min_yr / J_design;              % usable flux turndown at the design point

% ------------------------------------------------------------------------
% 7.  design point and pump duty
% ------------------------------------------------------------------------
Q_p = J_design * A_mem * LMH_to_m3d;             % permeate, m3/d
Q_f = Q_p / R_set;                               % feed,     m3/d
Q_b = Q_f - Q_p;                                 % brine,    m3/d

dP_des      = pi_avg + J_design ./ A_T;          % required pressure at J_design, bar [1 x 366]
dP_des_max  = max(dP_des);
dP_des_min  = min(dP_des);
dP_des_mean = mean(dP_des);

% hydraulic power of the HP pump at the design point, kW
P_hyd = dP_des * 1e5 .* (Q_f/86400) / 1000;

label = sprintf('%s | %de x %dv | R=%.0f%% | J=%.1f LMH', ...
                shortName(cfg_name), n_elem, n_vess, R_set*100, J_design);

% ------------------------------------------------------------------------
% 8.  pack output
% ------------------------------------------------------------------------
out = struct( ...
    'cfg_name',    cfg_name,      'n_elem',      n_elem, ...
    'n_vess',      n_vess,        'R_set',       R_set, ...
    'J_design',    J_design,      'J_lo',        J_lo, ...
    'J_hi',        J_hi,          'J_elem',      J_elem, ...
    'r_e',         r_e,           'R_ceil',      R_ceil, ...
    'inBand',      inBand,        'A_mem',       A_mem, ...
    'J_sweep',     J_sweep,       'Qf_sweep',    Qf, ...
    'Hsys',        Hsys,          'dP_env_max',  dP_env_max, ...
    'dP_env_min',  dP_env_min,    'feasible',    feasible, ...
    'driving_ok',  driving_ok,    'pressure_ok', pressure_ok, ...
    'J_min_day',   J_min_day,     'J_min_yr',    J_min_yr, ...
    'Qf_min_yr',   Qf_min_yr,     'turndown',    turndown, ...
    'Q_p',         Q_p,           'Q_f',         Q_f, ...
    'Q_b',         Q_b,           'dP_des',      dP_des, ...
    'dP_des_max',  dP_des_max,    'dP_des_min',  dP_des_min, ...
    'dP_des_mean', dP_des_mean,   'P_hyd',       P_hyd, ...
    'P_hyd_max',   max(P_hyd),    'P_hyd_min',   min(P_hyd), ...
    'date_hard',   dates(iHard),  'date_easy',   dates(iEasy), ...
    'pi_avg',      pi_avg,        'pi_b',        pi_b, ...
    'A_T',         A_T,           'dates',       dates, ...
    'P_max',       P_max,         'label',       string(label), ...
    'flux2Qf',     flux2Qf,       'Qf2flux',     Qf2flux);

% ------------------------------------------------------------------------
% 9.  plot
% ------------------------------------------------------------------------
if plotMode ~= "off"
    plotSystemCurve(out, plotMode);
end

end % ===================== main function ends ==========================


% ========================================================================
function plotSystemCurve(out, plotMode)
%PLOTSYSTEMCURVE  Draw one design onto the shared, re-entrant figure.
%   Left  panel: flux space  -> the curve itself, plus this design's band.
%   Right panel: feed-flow space -> where this design sits in absolute flow.

TAG = 'PVSWRO_systemCurve';
f = findobj('Type','figure','Tag',TAG);

if plotMode == "new" || isempty(f)
    if ~isempty(f), clf(f(1)); fig = f(1); else, fig = figure; end
    set(fig,'Tag',TAG,'Name','PV-SWRO system curve','Color','w', ...
            'Position',[80 80 1180 520]);
    axL = subplot(1,2,1,'Parent',fig);  hold(axL,'on');  grid(axL,'on');  box(axL,'on');
    axR = subplot(1,2,2,'Parent',fig);  hold(axR,'on');  grid(axR,'on');  box(axR,'on');
    setappdata(fig,'axL',axL);  setappdata(fig,'axR',axR);
    setappdata(fig,'nSeries',0);
    setappdata(fig,'cfgDrawn',strings(0,1));
    setappdata(fig,'QfMax',0);
    setappdata(fig,'QfMin',Inf);
    setappdata(fig,'JMax',0);
else
    fig = f(1);
    figure(fig);
end

axL = getappdata(fig,'axL');
axR = getappdata(fig,'axR');
n   = getappdata(fig,'nSeries');
C   = lines(8);
col = C(mod(n,8)+1,:);

% ---- once per figure: the 366 daily curves and the pressure rating ----
if n == 0
    plot(axL, out.J_sweep, out.Hsys, '-', 'Color',[0.80 0.84 0.90], ...
         'LineWidth',0.3, 'HandleVisibility','off');
    yline(axL, out.P_max, 'r--', 'LineWidth',1.1, ...
          'Label','element rating 83 bar', 'LabelHorizontalAlignment','left', ...
          'HandleVisibility','off');
    yline(axR, out.P_max, 'r--', 'LineWidth',1.1, 'HandleVisibility','off');
end

% ---- once per configuration: shade its design flux band ----------------
drawn = getappdata(fig,'cfgDrawn');
if ~any(drawn == out.cfg_name)
    yl = [0 out.P_max];
    patch(axL, [out.J_lo out.J_hi out.J_hi out.J_lo], [yl(1) yl(1) yl(2) yl(2)], ...
          col, 'FaceAlpha',0.10, 'EdgeColor',col, 'LineStyle',':', ...
          'HandleVisibility','off');
    text(axL, (out.J_lo+out.J_hi)/2, out.P_max-2, ...
         sprintf('%.0f-%.0f', out.J_lo, out.J_hi), ...
         'Color',col*0.7, 'FontSize',8, 'HorizontalAlignment','center');
    setappdata(fig,'cfgDrawn',[drawn; out.cfg_name]);
end

% ---- left panel: annual envelope in flux space -------------------------
plot(axL, out.J_sweep, out.dP_env_max, '-',  'Color',col, 'LineWidth',2.0, ...
     'DisplayName',out.label);
plot(axL, out.J_sweep, out.dP_env_min, '--', 'Color',col, 'LineWidth',1.2, ...
     'HandleVisibility','off');
plot(axL, out.J_design, out.dP_des_max, 'o', 'MarkerSize',7, ...
     'MarkerFaceColor',col, 'MarkerEdgeColor','k', 'HandleVisibility','off');
xline(axL, out.J_min_yr, ':', 'Color',col, 'LineWidth',1.3, ...
      'HandleVisibility','off');

% ---- right panel: annual envelope in feed-flow space -------------------
Qh = out.Qf_sweep/24;                                  % m3/h
plot(axR, Qh, out.dP_env_max, '-',  'Color',col, 'LineWidth',2.0, ...
     'DisplayName',out.label);
plot(axR, Qh, out.dP_env_min, '--', 'Color',col, 'LineWidth',1.2, ...
     'HandleVisibility','off');
plot(axR, out.Q_f/24, out.dP_des_max, 'o', 'MarkerSize',7, ...
     'MarkerFaceColor',col, 'MarkerEdgeColor','k', 'HandleVisibility','off');

% ---- axes bookkeeping --------------------------------------------------
setappdata(fig,'QfMax', max(getappdata(fig,'QfMax'), max(Qh)));
setappdata(fig,'QfMin', min(getappdata(fig,'QfMin'), max(Qh)));
setappdata(fig,'JMax',  max(getappdata(fig,'JMax'),  out.J_elem));
setappdata(fig,'nSeries', n+1);

if n == 0, setappdata(fig,'YLo',Inf); end
setappdata(fig,'YLo', min(getappdata(fig,'YLo'), min(out.dP_env_min)));
y_lo = max(0, floor(getappdata(fig,'YLo')/5)*5 - 5);
y_hi = ceil(out.P_max/5)*5;

xlabel(axL,'Permeate flux  J_w  (LMH)');
ylabel(axL,'Required pressure  \DeltaP  (bar)');
title (axL,'System curve - flux space');
xlim  (axL,[0 getappdata(fig,'JMax')]);
ylim  (axL,[y_lo y_hi]);
legend(axL,'Location','northwest','FontSize',8,'Box','off');

QfMax = getappdata(fig,'QfMax');
QfMin = getappdata(fig,'QfMin');
xlabel(axR,'Feed flow  Q_f  (m^3/h)');
ylabel(axR,'Required pressure  \DeltaP  (bar)');
title (axR,'System curve - pump duty space');
ylim  (axR,[y_lo y_hi]);
if QfMax/max(QfMin,eps) > 20
    set(axR,'XScale','log');
    xlim(axR,[max(0.1,QfMin/3) QfMax*1.1]);
else
    set(axR,'XScale','linear');
    xlim(axR,[0 QfMax*1.05]);
end
legend(axR,'Location','northwest','FontSize',8,'Box','off');

end % ===================== plot helper ends ============================


% ========================================================================
function s = shortName(cfg)
%SHORTNAME  Compact configuration tag for legends.
switch cfg
    case "UF + B-free",                 s = 'UF+Bfree';
    case "Well/open intake + UF",       s = 'Well+UF';
    case "Generic membrane filtration", s = 'GenMF';
    case "Conventional pretreatment",   s = 'Conv';
    otherwise,                          s = char(cfg);
end
end