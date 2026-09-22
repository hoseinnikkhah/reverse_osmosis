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
    for j = 1:10
        for k = 1:9
        if ceil_rec(i,1) > recovery_rate_1(end)
            Q_UF_B_free(i, j, k) ./ recovery_rate_1;
        elseif ceil_rec(i,1) < recovery_rate_1(end)
            Q_UF_B_free(i, j, k) ./ recovery_rate_2;
        if ceil_rec(i,2) > recovery_rate_1(end)
            Q_Well_open_intake_UF(i, j, k) ./ recovery_rate_1;
        elseif ceil_rec(i,2) < recovery_rate_1(end)
            Q_Well_open_intake_UF(i, j, k) ./ recovery_rate_2;
        if ceil_rec(i,3) > recovery_rate_1(end)
            Q_Generic_membrane_filtration(i, j, k) ./ recovery_rate_1;
        elseif ceil_rec(i,3) < recovery_rate_1(end)
            Q_Generic_membrane_filtration(i, j, k) ./ recovery_rate_2;
        if ceil_rec(i,4) > recovery_rate_1(end)
            Q_Conventional_pretreatment(i, j, k) ./ recovery_rate_1;
        elseif ceil_rec(i,4) < recovery_rate_1(end)
            Q_Conventional_pretreatment(i, j, k) ./ recovery_rate_2;