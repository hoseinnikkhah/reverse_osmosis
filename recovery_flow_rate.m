data = load('design_data.mat');

ceil_rec = data.ceil_recovery;        % 3×4 matrix
recovery_rate_1 = 30:1:60;            % Recovery rate range [%]
recovery_rate_2 = 30:1:50;            % Recovery rate range [%]

for i = 1:3
    for j = 1:4
        if ceil_rec(i,j) < recovery_rate_1(end)/100
          break
        end

