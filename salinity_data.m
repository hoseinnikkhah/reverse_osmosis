%% Salinity file
file_sal = 'cmems_mod_med_phy-sal_my_4.2km_P1D-m_1788964958643.nc';

% Time → dates (same method as temp)
t = ncread(file_sal, 'time');
t_units = ncreadatt(file_sal, 'time', 'units');
ref = datetime(extractAfter(t_units, 'since '), 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
dates_sal = ref + days(t);

% Salinity (lon × lat × depth × time)
sal = ncread(file_sal, 'so');

% Surface layer only
S_surf = squeeze(sal(:,:,1,:));   % lon × lat × 366
save('salinity_surface.mat', 'S_surf', 'dates_sal');