% This code is used to find C_p based on 366 values of J_s and at each node of J_w.

load('J_s_finder.mat', 'J_s', 'dates');
J_w = 0:0.1:30;  % Water flux range [LMH]

