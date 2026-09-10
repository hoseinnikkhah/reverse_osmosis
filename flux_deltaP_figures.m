load('delta_P_finder.mat', 'delta_P', 'J_w', 'STPi', 'dates');

figure;
imagesc(dates, J_w, delta_P);          % x=dates, y=J_w, color=delta_P
axis xy;                                % flip y-axis so J_w increases upward
colorbar;
colormap(jet);                          % or parula, turbo, hot

xlabel('Date');
ylabel('Water Flux J_w (LMH)');
title('Required Net Driving Pressure \DeltaP (bar)');
datetick('x', 'mmm-yyyy', 'keeplimits');  % format dates nicely