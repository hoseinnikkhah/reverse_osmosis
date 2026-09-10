%% Load data
load('delta_P_finder.mat', 'delta_P', 'J_w', 'STPi', 'dates');

%% Month labels (day indices for a year starting 31 July)
month_ticks = [1 32 62 93 123 154 185 214 245 275 306 336 366];
month_labels = {'Aug 25','Sep 25','Oct 25','Nov 25','Dec 25','Jan 26',...
                'Feb 26','Mar 26','Apr 26','May 26','Jun 26','Jul 26','Aug 26'};

%% =======================================================================
%% Figure 1: Heatmap (imagesc)
%% =======================================================================
figure('Name','Heatmap','Position',[100 100 900 400]);
imagesc(1:366, J_w, delta_P);
axis xy;
colorbar;
colormap(jet);

xticks(month_ticks); xticklabels(month_labels);
xlabel('Month');
ylabel('Water Flux J_w (LMH)');
title('Required Net Driving Pressure \DeltaP (bar) — Heatmap');

%% =======================================================================
%% Figure 2: Contour Plot
%% =======================================================================
figure('Name','Contour','Position',[200 200 900 400]);
contourf(1:366, J_w, delta_P, 20);
hold on;
contour(1:366, J_w, delta_P, [50 55 60], 'k-', 'LineWidth', 1.5);
hold off;

colorbar;
colormap(jet);

xticks(month_ticks); xticklabels(month_labels);
xlabel('Month');
ylabel('Water Flux J_w (LMH)');
title('Required \DeltaP (bar) — Contours (black lines: 50/55/60 bar)');

%% =======================================================================
%% Figure 3: Representative Line Curves
%% =======================================================================
figure('Name','Line Curves','Position',[250 250 900 400]);
hold on;

flux_picks = [15, 20, 25, 30];
colors = lines(length(flux_picks));

for k = 1:length(flux_picks)
    idx = find(J_w == flux_picks(k));
    if ~isempty(idx)
        plot(1:366, delta_P(idx, :), 'Color', colors(k,:), ...
             'LineWidth', 1.5, 'DisplayName', sprintf('J_w = %.0f LMH', flux_picks(k)));
    end
end
hold off;

xticks(month_ticks); xticklabels(month_labels);
xlabel('Month');
ylabel('Required \DeltaP (bar)');
title('Net Driving Pressure for Selected Fluxes');
legend('Location', 'best');
grid on;

%% =======================================================================
%% Figure 4: Heatmap + Threshold Contours (combined view)
%% =======================================================================
figure('Name','Combined View','Position',[300 300 900 400]);
imagesc(1:366, J_w, delta_P);
axis xy;
hold on;
contour(1:366, J_w, delta_P, [50 55 60], 'w-', 'LineWidth', 1.5);
hold off;

colorbar;
colormap(jet);

xticks(month_ticks); xticklabels(month_labels);
xlabel('Month');
ylabel('Water Flux J_w (LMH)');
title('\DeltaP Heatmap with 50/55/60 bar Thresholds (white lines)');