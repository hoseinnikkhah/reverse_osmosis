data = load('design_data.mat');

ceil_rec = data.ceil_recovery;        % 3×4 matrix
recovery_rate_1 = 30:1:60;            % Recovery rate range [%]
recovery_rate_2 = 30:1:50;            % Recovery rate range [%]

Q_p = data.Q_p;                       % 3×4 matrix a list aof all flow rates

% Each system design flow rate is stored in a cell array
Q_UF_B_free = data.Q_p{1, 1};
Q_Well_open_intake_UF = data.Q_p{2, 1};
Q_Generic_membrane_filtration = data.Q_p{3, 1};
Q_Conventional_pretreatment = data.Q_p{4, 1};

for i = 1:3
    for j = 1:4
        if ceil_rec(i,j) < recovery_rate_1(end)/100
          break
        end

