%% 1. File and read
file = 'cmems_mod_med_phy-temp_my_4.2km_P1D-m_1788964996647.nc';

% Time → dates
t = ncread(file, 'time');
t_units = ncreadatt(file, 'time', 'units');          % 'days since 1950-01-01 ...'
ref = datetime(extractAfter(t_units, 'since '), 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
dates = ref + days(t);

% Temperature (lon × lat × depth × time)
temp = ncread(file, 'thetao');

%% 2. Surface temperature mapped to dates
% Keep only surface layer (depth = 1), result is lon × lat × time
T_surf = squeeze(temp(:,:,1,:));

% T_surf(:,:,i) is now the temperature field for dates(i)