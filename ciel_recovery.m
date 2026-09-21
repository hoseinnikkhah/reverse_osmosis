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

ceil_recovery = zeros(3, 4);   % rows = elements per vessel (5,6,7), cols = configurations
for iE = 1:3
    for k = 1:4
        r_e = rec_max(k) / 100;                                 % max element recovery [-]
        ceil_recovery(iE, k) = 1 - (1 - r_e)^N_elements(iE);    % max vessel recovery [-]
    end
end
