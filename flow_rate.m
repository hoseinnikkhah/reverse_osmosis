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

%% Permeate production for every design and every design flux
% Q_p{k} has size [elements x vessels x flux] for configuration k
LMH_to_m3d = 24/1000;               % L/(m2.h) x m2 -> m3/d

Q_p = cell(height(config), 1);
for k = 1:height(config)
    J3     = reshape(config.J_design{k}, 1, 1, []);   % flux along 3rd dimension
    Q_p{k} = total_A .* J3 * LMH_to_m3d;               % [m3/d]
end

%% Sanity check: conventional pretreatment, 7 elements, 5 vessels, 14 LMH
k  = find(config.Name == "Conventional pretreatment");
iE = find(N_elements == 7);
iV = find(N_vessels == 5);
iJ = find(config.J_design{k} == 14);
fprintf('Q_p = %.1f m3/d (expected ~482)\n', Q_p{k}(iE, iV, iJ));