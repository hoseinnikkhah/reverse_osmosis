% Temperature file
ncdisp('cmems_mod_med_phy-temp_my_4.2km_P1D-m_1788963786018.nc');
temp = ncread('cmems_mod_med_phy-temp_my_4.2km_P1D-m_1788963786018.nc', 'temp');

% Salinity file
ncdisp('cmems_mod_med_phy-sal_my_4.2km_P1D-m_1788963651121.nc');
sal = ncread('cmems_mod_med_phy-sal_my_4.2km_P1D-m_1788963651121.nc', 'salinity');

% Check dimensions match
size(temp)
size(sal)