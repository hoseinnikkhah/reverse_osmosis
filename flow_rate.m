%% vessel design contains the design of the vessel and the number of membranes

N_elements = [6,7,8]; % Number of membranes in the vessel which is limited to 6-8 elements
N_vessels = 1:10; % Number of vessels in the system which is from 1 to 10 vessels
A_m = 41; % Active area of the membrane [m2] A_mem


A_membrane = A_m .* N_elements; % Total active area of the membrane in the vessel [m2]

total_A = zeros(length(N_elements), length(N_vessels)); % Preallocate total_A array
for i = 1:length(N_elements)
    for j = 1:length(N_vessels)
        total_A(i, j) = A_membrane(i) * N_vessels(j); % Total active area of the system [m2]
    end
end