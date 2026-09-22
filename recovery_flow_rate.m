data = load('design_data.mat');

ceil_rec = data.ceil_recovery;      % 3×4 matrix
recovery_rate = 30:1:60;            % Recovery rate range [%]

for i = 1:3
    for j = 1:4
        if ceil_rec(i,j) < recovery_rate(end)/100
            fprintf('Configuration %d, Elements per vessel %d: Max recovery %.2f%% < %.2f%%\n')
                    recovery_rate_temp = 30:1:50;  % Recovery rate range [%]
        end