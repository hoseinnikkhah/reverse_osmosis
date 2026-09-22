%% Feed and concentrate flow for every design and recovery
% Q_f = Q_p / R,   Q_c = Q_f - Q_p
% Recoveries above each design's upper bound are set to NaN.

data = load('design_data.mat');

config     = data.config;          % table of 4 pretreatment configurations
Q_p        = data.Q_p;             % 4x1 cell; Q_p{k} is [elements x vessels x flux], m3/d
ceil_rec   = data.ceil_recovery;   % [elements x configs] = 3x4, as a fraction (0-1)
N_elements = data.N_elements;      % [5 6 7]
N_vessels  = data.N_vessels;       % 1:10

%% Recovery sweep (as a fraction, to match ceil_rec)
R  = (30:1:60) / 100;              % 0.30 ... 0.60
nR = numel(R);

%% Upper recovery bound for each design
% Limit 1: element ceiling (ceil_rec)
% Limit 2: brine osmotic pressure pi0/(1-R) must not exceed the element max pressure
pi0_max = 33;                          % [bar] highest feed osmotic pressure in your yearly data (replace)
P_max   = 83;                          % [bar] element max pressure (confirm on SW30HRLE-440 datasheet)
R_pressure = 1 - pi0_max / P_max;      % ~0.60

R_upper = min(ceil_rec, R_pressure);   % [3 x 4], same layout as ceil_rec

%% Q_f and Q_c for each configuration
R4 = reshape(R, 1, 1, 1, nR);          % recovery placed on the 4th dimension

Q_f = cell(height(config), 1);
Q_c = cell(height(config), 1);

for k = 1:height(config)
    % [elements x vessels x flux] ./ [1 x 1 x 1 x nR] -> [elements x vessels x flux x recovery]
    Q_f{k} = Q_p{k} ./ R4;             % [m3/d]
    Q_c{k} = Q_f{k} - Q_p{k};          % [m3/d]

    % Remove recoveries above the bound, separately for each vessel length
    for iE = 1:numel(N_elements)
        too_high = R > R_upper(iE, k);         % 1 x nR logical
        Q_f{k}(iE, :, :, too_high) = NaN;
        Q_c{k}(iE, :, :, too_high) = NaN;
    end
end

%% Per-vessel feed flow check
Qf_vessel_max = 16;                    % [m3/h] per vessel (Lu et al. 2007, Table 1; confirm on datasheet)

flow_ok = cell(height(config), 1);
for k = 1:height(config)
    Qf_vessel  = Q_f{k} ./ N_vessels / 24;     % [m3/h]; N_vessels (1x10) lines up with dimension 2
    flow_ok{k} = Qf_vessel <= Qf_vessel_max;   % true where feasible (NaN entries give false)
end

%% Sanity check: conventional, 7 elements, 5 vessels, 14 LMH, 45% recovery
k  = find(config.Name == "Conventional pretreatment");
iE = find(N_elements == 7);
iV = find(N_vessels == 5);
iJ = find(config.J_design{k} == 14);
iR = find(round(R*100) == 45);
fprintf('Q_f = %.1f m3/d (expected ~1071.5)\n', Q_f{k}(iE, iV, iJ, iR));
fprintf('Q_c = %.1f m3/d (expected ~589.3)\n',  Q_c{k}(iE, iV, iJ, iR));

disp('Upper recovery bound [%] (rows: 5,6,7 elements; cols: configurations):');
disp(round(R_upper * 100, 1));

%% Save
save('flow_data.mat', 'Q_f', 'Q_c', 'R', 'R_upper', 'flow_ok', 'Qf_vessel_max');