%% Vessel design
A_m        = 41;                    % Active area per element [m2] (SW30HRLE-440)
N_elements = [5, 6, 7];             % Elements per vessel (Codeline 80E max = 7)
N_vessels  = 1:10;                  % Number of vessels in parallel

% Total active area: rows = elements per vessel, columns = number of vessels
total_A = A_m * N_elements(:) * N_vessels;          % [m2], size 3 x 10

%% Pretreatment configurations (DuPont FilmTec Manual, Table 22, seawater)
Name     = ["UF + B-free"; "Well/open intake + UF"; ...
            "Generic membrane filtration"; "Conventional pretreatment"];
J_design = {17:0.5:21; 15:0.5:19; 14:0.5:17; 12:0.5:17};   % Design flux [LMH]
J_max    = [38; 36; 34; 32];                               % Max element flux [LMH]
rec_max  = [16; 15; 14; 13];                               % Max element recovery [%]

R_ceil = 1 - (1 - config.rec_max/100) .^ N_elements;   % [4 x 3], rows = config, cols = elements/vessel

config = table(Name, J_design, J_max, rec_max);

%% Permeate production
% Q_p{k}      : [elements x vessels x flux] across the design flux range
% Q_p_Jmax{k} : [elements x vessels] at the max element flux (upper bound only,
%               not a design point; in a real vessel the lead element exceeds
%               the average flux, so average flux should stay below J_max)
LMH_to_m3d = 24/1000;               % L/(m2.h) x m2 -> m3/d

Q_p      = cell(height(config), 1);
Q_p_Jmax = cell(height(config), 1);
for k = 1:height(config)
    J3          = reshape(config.J_design{k}, 1, 1, []);   % flux along 3rd dimension
    Q_p{k}      = total_A .* J3 * LMH_to_m3d;               % [m3/d]
    Q_p_Jmax{k} = total_A * config.J_max(k) * LMH_to_m3d;   % [m3/d]
end

%% Sanity check: conventional pretreatment, 7 elements, 5 vessels, 14 LMH
k  = find(config.Name == "Conventional pretreatment");
iE = find(N_elements == 7);
iV = find(N_vessels == 5);
iJ = find(config.J_design{k} == 14);
fprintf('Q_p = %.1f m3/d (expected ~482)\n', Q_p{k}(iE, iV, iJ));

%% Plots: capacity band for each pretreatment configuration
A_build  = unique(total_A(:));       % distinct buildable areas [m2]
A_line   = [0; max(A_build)];        % x-range for the band edges [m2]
Q_demand = [];                       % optional demand line [m3/d], e.g. 500

% Common y-limit so all configurations are directly comparable
Q_ymax = max(A_build) * max(config.J_max) * LMH_to_m3d;

%% (1) Separate figure for each configuration
for k = 1:height(config)
    J_lo = min(config.J_design{k});
    J_hi = max(config.J_design{k});

    fig = figure('Name', char(config.Name(k)));
    ax  = axes(fig);
    h   = plotCapacityBand(ax, A_build, A_line, J_lo, J_hi, ...
                           config.J_max(k), LMH_to_m3d, Q_demand);

    handles = [h.band, h.max, h.des];
    labels  = {sprintf('Design flux %g-%g LMH', J_lo, J_hi), ...
               sprintf('Max element flux %g LMH', config.J_max(k)), ...
               'Buildable designs'};
    if ~isempty(h.dem)
        handles(end+1) = h.dem;
        labels{end+1}  = sprintf('Demand %g m^3/d', Q_demand);
    end

    xlabel(ax, 'Total active membrane area [m^2]');
    ylabel(ax, 'Permeate production Q_p [m^3/d]');
    title(ax, config.Name(k));
    ylim(ax, [0 Q_ymax]);
    legend(ax, handles, labels, 'Location', 'northwest');
end

%% (2) Combined 2x2 figure for the paper
figC = figure('Name', 'Capacity bands - all configurations');
tl   = tiledlayout(figC, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

for k = 1:height(config)
    J_lo = min(config.J_design{k});
    J_hi = max(config.J_design{k});

    ax = nexttile(tl);
    h  = plotCapacityBand(ax, A_build, A_line, J_lo, J_hi, ...
                          config.J_max(k), LMH_to_m3d, Q_demand);

    title(ax, sprintf('%s (%g-%g LMH)', config.Name(k), J_lo, J_hi));
    ylim(ax, [0 Q_ymax]);
end

xlabel(tl, 'Total active membrane area [m^2]');
ylabel(tl, 'Permeate production Q_p [m^3/d]');

% One shared legend below all tiles (flux values are in each tile title)
handles = [h.band, h.max, h.des];
labels  = {'Design flux range', 'Max element flux', 'Buildable designs'};
if ~isempty(h.dem)
    handles(end+1) = h.dem;
    labels{end+1}  = 'Demand';
end
lg = legend(ax, handles, labels, 'Orientation', 'horizontal');
lg.Layout.Tile = 'south';

% exportgraphics(figC, 'capacity_bands_all.pdf', 'ContentType', 'vector');

%% Local function: draws one capacity band on a given axes
function h = plotCapacityBand(ax, A_build, A_line, J_lo, J_hi, J_max, c, Q_demand)
    hold(ax, 'on'); box(ax, 'on'); grid(ax, 'on');

    % Design-flux band
    h.band = fill(ax, [A_line; flipud(A_line)], ...
                  [A_line*J_lo; flipud(A_line*J_hi)] * c, ...
                  [0.3 0.6 0.9], 'FaceAlpha', 0.25, 'EdgeColor', 'none');
    plot(ax, A_line, A_line*J_lo*c, 'b-', 'LineWidth', 1.2);
    plot(ax, A_line, A_line*J_hi*c, 'b-', 'LineWidth', 1.2);

    % Max element flux (upper bound only)
    h.max = plot(ax, A_line, A_line*J_max*c, 'r--', 'LineWidth', 1.2);

    % Buildable designs: production range at each achievable area
    for a = A_build'
        plot(ax, [a a], [J_lo J_hi]*a*c, 'k-', 'LineWidth', 1);
    end
    h.des = plot(ax, A_build, A_build*J_lo*c, 'k.', 'MarkerSize', 12);
    plot(ax, A_build, A_build*J_hi*c, 'k.', 'MarkerSize', 12);

    % Optional demand line
    h.dem = [];
    if ~isempty(Q_demand)
        h.dem = yline(ax, Q_demand, 'g-', 'LineWidth', 1.5);
    end

    hold(ax, 'off');
end