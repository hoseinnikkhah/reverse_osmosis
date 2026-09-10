load('membrane_params.mat', 'A', 'B', 'A_LMH','B_LMH');
T_list = 14:0.0001:35;               % Temperature range [C]
A_list = zeros(1,length(T_list));
A_list_LMH = zeros(1,length(T_list));

for i=1:length(T_list)
    T_c = T_list(i);
    A_temp_LMH = A_LMH*1.03^(T_c - 25);  % Temperature correction for A [LMH/bar]
    A_list_LMH(i) = A_temp_LMH;
    A_temp = A*1.03^(T_c - 25);  % Temperature correction for A [LMH/bar]
    A_list(i) = A_temp;
end

save('A_temp_data.mat', 'A_LMH');

figure;
plot(T_list, A_list_LMH, 'LineWidth', 1);

xlabel('Temperature (°C)', 'FontSize', 12);
ylabel('Water Permeability Coefficient A (LMH/bar)', 'FontSize', 12);
legend('DuPont FilmTec SW30HRLE-440', 'Location', 'best');
grid on;