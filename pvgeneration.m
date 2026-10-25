%% pvgisFetch.m
%  Download PVGIS hourly irradiance and weather for one point, or for a
%  grid of points, and save them in a form the PV layer can read.
%
%  PVGIS is a POINT service: unlike CMEMS it returns one time series per
%  call, not a gridded field.  That is the right thing for this study - a
%  PV array sits at one location, and averaging irradiance over a box
%  would smooth away the cloud transients the dispatch model exists to
%  resolve.  Looping the API is only for spatial SENSITIVITY: pick one
%  point as the base case and treat the rest as a check.
%
%  API (non-interactive service, v5_2):
%    https://re.jrc.ec.europa.eu/api/v5_2/seriescalc
%      lat, lon        decimal degrees, south and west negative
%      startyear/endyear   omit for the full database span
%      angle           inclination from horizontal, degrees
%      aspect          0 = south, 90 = west, -90 = east
%      outputformat    csv
%      components      1 to also get beam / diffuse / reflected
%
%  RETURNED COLUMNS (confirm on your first download - PVGIS has changed
%  these between versions):
%      time    timestamp, yyyymmdd:HHMM
%      G(i)    global irradiance on the inclined plane, W/m2
%      H_sun   sun height, degrees
%      T2m     air temperature at 2 m, degC
%      WS10m   wind speed at 10 m, m/s
%      Int     1 if the values are reconstructed
%
%  Output : pv_raw_<lat>_<lon>.mat  per point, plus pvgis_points.mat
%
%  NOTE  this script has not been run against the live service from here,
%  so check the first download before trusting the parse.  The parser
%  finds the header line rather than assuming a fixed number of metadata
%  rows, which is the part most likely to change.

clear; clc;
fprintf('>>> running pvgisFetch.m\n');

%% ====================== 1.  SETTINGS  =================================
% ---- edit this block only ---------------------------------------------
% One point: give scalars.  A grid: give vectors and set GRID = true.
LAT   = 37.05;             % <-- centroid of your CMEMS box, on the coast
LON   = 14.25;             % <--
GRID  = false;             % true to sweep the vectors below
LAT_V = [36.9 37.05 37.2];
LON_V = [14.0 14.25 14.5];

YEAR0 = [];                % [] = first year the database offers
YEAR1 = [];                % [] = last year
ANGLE = 30;                % module tilt from horizontal, degrees
ASPECT= 0;                 % 0 = due south
COMPONENTS = 0;            % 1 also returns beam / diffuse / reflected

API = 'https://re.jrc.ec.europa.eu/api/v5_2/seriescalc';
OUTDIR = pwd;
% -----------------------------------------------------------------------

if GRID
    [LA, LO] = meshgrid(LAT_V, LON_V);
    pts = [LA(:) LO(:)];
    fprintf('grid mode: %d points\n', size(pts,1));
else
    pts = [LAT LON];
end

%% ====================== 2.  FETCH  ====================================
files = strings(size(pts,1),1);
for p = 1:size(pts,1)
    la = pts(p,1);  lo = pts(p,2);

    q = sprintf('%s?lat=%.5f&lon=%.5f&angle=%g&aspect=%g&outputformat=csv&components=%d', ...
                API, la, lo, ANGLE, ASPECT, COMPONENTS);
    if ~isempty(YEAR0), q = sprintf('%s&startyear=%d', q, YEAR0); end
    if ~isempty(YEAR1), q = sprintf('%s&endyear=%d',   q, YEAR1); end

    raw = fullfile(OUTDIR, sprintf('pvgis_%.3f_%.3f.csv', la, lo));
    fprintf('  [%d/%d] lat %.3f lon %.3f ... ', p, size(pts,1), la, lo);
    try
        websave(raw, q);
    catch ME
        fprintf('FAILED\n');
        fprintf('    %s\n', ME.message);
        fprintf('    If this is a connection error, download by hand from\n');
        fprintf('    re.jrc.ec.europa.eu/pvg_tools/en/ (HOURLY DATA tab) and\n');
        fprintf('    run section 3 on the saved file instead.\n');
        continue
    end

    T = parsePVGIS(raw);
    fprintf('%d rows, %s to %s\n', height(T), ...
            datestr(T.time(1),'dd mmm yyyy'), datestr(T.time(end),'dd mmm yyyy'));

    out = fullfile(OUTDIR, sprintf('pv_raw_%.3f_%.3f.mat', la, lo));
    site = struct('lat',la, 'lon',lo, 'angle',ANGLE, 'aspect',ASPECT, ...
                  'source',"PVGIS v5_2 seriescalc", 'fetched',datetime('now'));
    save(out, 'T', 'site');
    files(p) = string(out);
end

save(fullfile(OUTDIR,'pvgis_points.mat'), 'pts', 'files', 'ANGLE', 'ASPECT');
fprintf('\nSaved %d point file(s) + pvgis_points.mat\n', sum(files ~= ""));

%% ====================== 3.  PARSER  ===================================
function T = parsePVGIS(fname)
% PVGIS CSV is metadata lines, then a header row starting with "time,",
% then the data, then more metadata.  Find the header rather than assuming
% a fixed offset, and stop at the first line that is not a data row.

    L = readlines(fname);
    h = find(startsWith(strtrim(L), 'time,'), 1);
    assert(~isempty(h), ...
        ['parsePVGIS: no header row starting "time," in %s.\n' ...
         'PVGIS may have changed its format - open the file and check.'], fname);

    % data runs until the first line that does not start with 8 digits
    isData = ~cellfun(@isempty, regexp(strtrim(L(h+1:end)), '^\d{8}:', 'once'));
    nData  = find(~isData, 1) - 1;
    if isempty(nData), nData = numel(isData); end
    assert(nData > 0, 'parsePVGIS: header found but no data rows follow.');

    opts = detectImportOptions(fname, 'NumHeaderLines', h-1, ...
                               'ReadVariableNames', true, 'Delimiter', ',');
    opts.DataLines = [h+1, h+nData];
    opts = setvartype(opts, opts.VariableNames(1), 'char');   % keep time as text
    T = readtable(fname, opts);

    % yyyymmdd:HHMM -> datetime
    T.(1) = datetime(string(T.(1)), 'InputFormat', 'yyyyMMdd:HHmm');
    T.Properties.VariableNames{1} = 'time';

    % PVGIS writes G(i) etc; MATLAB mangles the brackets.  Normalise.
    v = T.Properties.VariableNames;
    v = replace(v, {'G_i_','Gb_i_','Gd_i_','Gr_i_'}, {'Gi','Gbi','Gdi','Gri'});
    T.Properties.VariableNames = v;

    need = {'Gi','T2m','WS10m'};
    miss = need(~ismember(need, T.Properties.VariableNames));
    if ~isempty(miss)
        warning('parsePVGIS:missing', ...
            ['Expected column(s) %s not found. Got: %s\n' ...
             'Check the tilt/azimuth were accepted - without them PVGIS\n' ...
             'returns horizontal irradiance under a different name.'], ...
            strjoin(miss,', '), strjoin(T.Properties.VariableNames,', '));
    end
end