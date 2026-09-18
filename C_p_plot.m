%% Obselet file
load('C_p_finder.mat', 'C_p_block', 'J_w');

month_ticks = [1 32 62 93 123 154 185 214 245 275 306 336 366];
month_labels = {'Aug 25','Sep 25','Oct 25','Nov 25','Dec 25','Jan 26',...
                'Feb 26','Mar 26','Apr 26','May 26','Jun 26','Jul 26','Aug 26'};


figure('Name','Cp Line Curves','Position',[300 300 900 400]);
hold on;

flux_picks = [0, 5, 10, 15, 20, 25, 30];
colors = lines(length(flux_picks));

for k = 1:length(flux_picks)
    idx = find(J_w == flux_picks(k));
    plot(1:366, C_p_block(idx, :), 'Color', colors(k,:), ...
         'LineWidth', 1.5, 'DisplayName', sprintf('J_w = %.0f LMH', flux_picks(k)));
end
hold off;

xticks(month_ticks); xticklabels(month_labels);
xlabel('Month');
ylabel('Permeate Concentration C_p [ppm]');
title('C_p Variation Over the Year for Selected Fluxes');
legend('Location', 'best');
grid on;