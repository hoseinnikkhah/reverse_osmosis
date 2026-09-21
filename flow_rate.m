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
J_max    = [38; 36; 34; 32];                                % Max element flux [LMH]
rec_max  = [16; 15; 14; 13];                                % Max element recovery [%]

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

for k = 1:height(config)
    J_lo = min(config.J_design{k});
    J_hi = max(config.J_design{k});

    figure('Name', char(config.Name(k)));
    hold on; box on; grid on;

    % Design-flux band (wedge between lowest and highest design flux)
    hBand = fill([A_line; flipud(A_line)], ...
                 [A_line*J_lo; flipud(A_line*J_hi)] * LMH_to_m3d, ...
                 [0.3 0.6 0.9], 'FaceAlpha', 0.25, 'EdgeColor', 'none');
    plot(A_line, A_line*J_lo*LMH_to_m3d, 'b-', 'LineWidth', 1.2);
    plot(A_line, A_line*J_hi*LMH_to_m3d, 'b-', 'LineWidth', 1.2);

    % Max element flux (upper bound)
    hMax = plot(A_line, A_line*config.J_max(k)*LMH_to_m3d, 'r--', 'LineWidth', 1.2);

    % Buildable designs: production range at each achievable area
    for a = A_build'
        plot([a a], [J_lo J_hi]*a*LMH_to_m3d, 'k-', 'LineWidth', 1);
    end
    hDes = plot(A_build, A_build*J_lo*LMH_to_m3d, 'k.', 'MarkerSize', 12);
    plot(A_build, A_build*J_hi*LMH_to_m3d, 'k.', 'MarkerSize', 12);

    % Optional demand line
    handles = [hBand, hMax, hDes];
    labels  = {sprintf('Design flux %g-%g LMH', J_lo, J_hi), ...
               sprintf('Max element flux %g LMH', config.J_max(k)), ...
               'Buildable designs'};
    if ~isempty(Q_demand)
        hDem = yline(Q_demand, 'g-', 'LineWidth', 1.5);
        handles(end+1) = hDem;
        labels{end+1}  = sprintf('Demand %g m^3/d', Q_demand);
    end

    xlabel('Total active membrane area [m^2]');
    ylabel('Permeate production Q_p [m^3/d]');
    title(config.Name(k));
    legend(handles, labels, 'Location', 'northwest');
    hold off;
end