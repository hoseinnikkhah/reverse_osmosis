% This code is used to find C_p based on 366 values of J_s and at each node of J_w.

load('J_s_finder.mat', 'J_s', 'dates');
J_w = 0:0.1:30;  % Water flux range [LMH]

C_p_block = zeros(length(J_w), 366);

for i = 1:length(J_w)
    J_w_i = J_w(i);
    for j = 1:366
        J_s_j = J_s(j);
        if J_w_i > 0
            C_p_block(i, j) = J_s_j / J_w_i;  % Calculate C_p for each J_w and J_s
        else
            C_p_block(i, j) = NaN;  % Avoid division by zero
        end
    end
end

save('C_p_finder.mat', 'C_p_block');