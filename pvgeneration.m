%% pvGeneration.m
%  Turn PVGIS hourly radiation files into an hourly AC power series.
%
%  WHY THIS IS NORMALISED PER kWp
%    The DC power model is LINEAR in installed peak power:
%        P_dc = P_peak * (G/1000) * [1 + gamma*(T_mod-25)]
%    so this script computes p_unit, the AC power per kWp installed, once.
%    The whole PV-capacity sweep is then P_ac = P_peak * p_unit - no
%    re-download, no recomputation.  That is the axis of the capacity-ratio
%    study, so it is worth having it cost nothing.
%
%  MODULE TEMPERATURE - Faiman (wind-dependent)
%        T_mod = T_air + G / (U0 + U1*w)
%    This is why WS10m was downloaded.  The simpler NOCT form ignores wind
%    and overstates module temperature on breezy coastal sites, which is
%    exactly where this plant is.
%
%  WHAT IS AND IS NOT INCLUDED
%    Included : irradiance, module temperature, system losses (cabling,
%               soiling, mismatch, INVERTER - PVGIS bundles these in its
%               14 % default, so do NOT apply a separate inverter term).
%    Excluded : spectral and incidence-angle effects, degradation, shading,
%               low-light efficiency roll-off.  All second order for a
%               plant whose startup threshold is ~265 kW; state the omission.
%
%  Inputs : one or more PVGIS "Timeseries_*.csv" hourly radiation files
%  Output : pv_generation.mat  -  p_unit [kW_ac per kWp], time, year index

clear; close all; clc;
fprintf('>>> running pvGeneration.m\n');

%% ====================== 1.  SETTINGS  =================================
% ---- edit this block only ---------------------------------------------
FILES = { ...
    'Timeseries_37.477_15.082_SA3_35deg_0deg_2020_2021.csv'
    'Timeseries_37.477_15.082_SA3_35deg_0deg_2021_2022.csv' };

% ---- module electrical parameters -------------------------------------
% SOURCE THESE FROM A REAL MODULE DATASHEET, the way the pump curve came
% from a real catalogue.  The values below are representative c-Si figures,
% NOT a specific product.  Replace them and record the module in MODULE_REF.
MODULE_REF = "PLACEHOLDER - representative crystalline silicon";
gamma_P    = -0.0040;      % power temperature coefficient, 1/degC  (~-0.40 %/K)
G_ref      = 1000;         % reference irradiance, W/m2
T_ref      = 25;           % reference cell temperature, degC

% ---- Faiman module temperature coefficients ---------------------------
% Faiman (2008), Prog. Photovolt. 16:307-315, Table III "Combined Fit"
U0 = 25.0;                                         %[Faiman 2008]
U1 = 6.84;                                         %[Faiman 2008]

% ---- balance of system -------------------------------------------------
SYS_LOSS = 0.14;           % PVGIS default: cabling, soiling, mismatch,
                           % INVERTER.  Do not add an inverter term on top.

DROP_FEB29 = true;         % leap days have no day-of-year match in the
                           % seawater year; dropping is cleaner than clamping
% -----------------------------------------------------------------------

%% ====================== 2.  READ AND MERGE  ===========================
T = table();
for f = 1:numel(FILES)
    if ~isfile(FILES{f})
        error('pvGeneration: cannot find %s', FILES{f});
    end
    Tf = parsePVGIS(FILES{f});
    fprintf('  %s : %d rows, %s to %s\n', FILES{f}, height(Tf), ...
            datestr(Tf.time(1),'dd mmm yyyy'), datestr(Tf.time(end),'dd mmm yyyy'));
    T = [T; Tf];                                              %#ok<AGROW>
end

% the PVGIS files overlap, so de-duplicate on the timestamp
[~, iu] = unique(T.time, 'stable');
nDup = height(T) - numel(iu);
T = T(iu,:);
T = sortrows(T, 'time');
if nDup > 0
    fprintf('  removed %d duplicated hours (the files overlap on a year)\n', nDup);
end

if DROP_FEB29
    isLeapDay = month(T.time)==2 & day(T.time)==29;
    if any(isLeapDay)
        fprintf('  dropped %d leap-day hours\n', sum(isLeapDay));
        T(isLeapDay,:) = [];
    end
end

yrs = unique(year(T.time));
fprintf('  %d complete-ish years available: %s\n', numel(yrs), ...
        strjoin(string(yrs),', '));

%% ====================== 3.  THE MODEL  ================================
G = T.Gi;  Ta = T.T2m;  w = T.WS10m;

T_mod = Ta + G ./ (U0 + U1*w);                 % Faiman, degC
f_T   = 1 + gamma_P .* (T_mod - T_ref);        % temperature derate
p_dc  = (G / G_ref) .* f_T;                    % kW_dc per kWp
p_dc(G <= 0) = 0;                              % no output in the dark
p_unit = max(p_dc * (1 - SYS_LOSS), 0);        % kW_ac per kWp

T.T_mod  = T_mod;
T.p_unit = p_unit;

%% ====================== 4.  REPORT  ===================================
fprintf('\n%s\n', repmat('=',1,62));
fprintf('PV GENERATION, per kWp installed\n');
fprintf('module      : %s\n', MODULE_REF);
fprintf('gamma_P     : %+.4f /degC      Faiman U0 %.1f, U1 %.2f\n', gamma_P, U0, U1);
fprintf('system loss : %.0f %% (includes the inverter)\n', 100*SYS_LOSS);
fprintf('%s\n', repmat('-',1,62));
for y = yrs'
    k = year(T.time) == y;
    if sum(k) < 8000, continue; end            % skip partial years
    fprintf('  %d : %6.0f kWh/kWp/yr   %4.0f full-load hours   peak %.3f kW/kWp\n', ...
            y, sum(p_unit(k)), sum(p_unit(k)), max(p_unit(k)));
end
fprintf('%s\n', repmat('-',1,62));
hot = T_mod > Ta + 20;
fprintf('module runs >20 degC above air for %.1f %% of hours\n', 100*mean(hot));
fprintf('max module temperature : %.1f degC (air %.1f at that hour)\n', ...
        max(T_mod), Ta(T_mod==max(T_mod)));
fprintf('mean temperature derate while generating : %.1f %%\n', ...
        100*(1-mean(f_T(G>50))));
if MODULE_REF.startsWith("PLACEHOLDER")
    fprintf('\n*** MODULE PARAMETERS ARE PLACEHOLDERS - source gamma_P from a\n');
    fprintf('    real datasheet before quoting any yield figure ***\n');
end
fprintf('%s\n\n', repmat('=',1,62));

%% ====================== 5.  FIGURES  ==================================
figure('Name','pvGeneration 1/2 - the year','Color','w','Position',[80 320 860 520]);
subplot(2,1,1); hold on; grid on; box on;
yb = yrs(find(arrayfun(@(y) sum(year(T.time)==y), yrs') >= 8000, 1));
k  = year(T.time) == yb;
plot(T.time(k), p_unit(k), '-', 'Color',[0.85 0.6 0.1], 'LineWidth',0.3);
ylabel('kW_{ac} per kWp');  title(sprintf('Hourly specific output, %d', yb));

subplot(2,1,2); hold on; grid on; box on;
d  = dateshift(T.time(k),'start','day');
dd = unique(d);
daily = splitapply(@sum, p_unit(k), findgroups(d));
plot(dd, daily, '-', 'Color',[0.2 0.4 0.75], 'LineWidth',1.2);
ylabel('kWh/kWp/day');  xlabel('date');
title('Daily yield - the seasonal shape the dispatch has to live with');

figure('Name','pvGeneration 2/2 - temperature','Color','w','Position',[960 320 620 520]);
hold on; grid on; box on;
gen = G > 50;
scatter(Ta(gen), T_mod(gen), 4, G(gen), 'filled');
plot([min(Ta) max(Ta)], [min(Ta) max(Ta)], 'k--', 'LineWidth',1.2);
cb = colorbar;  cb.Label.String = 'G(i)  (W/m^2)';
xlabel('air temperature  (\circC)');  ylabel('module temperature  (\circC)');
title(sprintf('Faiman model: T_{mod} = T_{air} + G/(%.1f + %.2f w)', U0, U1));

%% ====================== 6.  SAVE  =====================================
pv = struct('time',T.time, 'p_unit',p_unit, 'G',G, 'T_air',Ta, ...
            'T_mod',T_mod, 'WS',w, 'gamma_P',gamma_P, 'U0',U0, 'U1',U1, ...
            'SYS_LOSS',SYS_LOSS, 'MODULE_REF',MODULE_REF, ...
            'lat',37.477, 'lon',15.082, 'slope',35, 'azimuth',0, ...
            'source',"PVGIS-SARAH3 hourly radiation");
save('pv_generation.mat','pv');
fprintf('Saved pv_generation.mat  (%d hours, %d years)\n', height(T), numel(yrs));

%% ====================== 7.  PARSER  ===================================
function T = parsePVGIS(fname)
% PVGIS writes metadata, then a header starting "time,", then data, then
% more metadata.  Find the header rather than assuming a fixed offset.
    L = readlines(fname);
    h = find(startsWith(strtrim(L), 'time,'), 1);
    assert(~isempty(h), 'parsePVGIS: no "time," header row in %s', fname);

    isData = ~cellfun(@isempty, regexp(strtrim(L(h+1:end)), '^\d{8}:', 'once'));
    nData  = find(~isData, 1) - 1;
    if isempty(nData), nData = numel(isData); end
    assert(nData > 0, 'parsePVGIS: header found but no data rows follow.');

    C = split(strtrim(L(h+1 : h+nData)), ',');       % nData x 6 string array
    T = table;
    T.time  = datetime(C(:,1), 'InputFormat','yyyyMMdd:HHmm');
    T.Gi    = double(C(:,2));
    T.H_sun = double(C(:,3));
    T.T2m   = double(C(:,4));
    T.WS10m = double(C(:,5));

    % PVGIS stamps satellite observation time (e.g. :09 past) - floor to hour
    T.time = dateshift(T.time, 'start', 'hour');
end