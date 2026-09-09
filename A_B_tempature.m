load('membrane_params.mat', 'A', 'B', 'A_LMH','B_LMH');
T_list = 20:1:35;               % Temperature range [C]
A_list = zeros(1,length(T_list));
A_list_LMH = zeros(1,length(T_list));

for i=1:length(T_list)
    T_c = T_list(i);
    A_temp_LMH = A_LMH*1.03^(T_c - 25);  % Temperature correction for A [LMH/bar]
    A_list_LMH(i) = A_temp_LMH;
    A_temp = A*1.03^(T_c - 25);  % Temperature correction for A [LMH/bar]
    A_list(i) = A_temp_LMH;
end