# pip install xarray netCDF4
import xarray as xr

files = {
    "salinity":    "cmems_mod_med_phy-sal_my_4.2km_P1D-m_1788964958643.nc",
    "temperature": "cmems_mod_med_phy-temp_my_4.2km_P1D-m_1788964996647.nc",
}

for name, f in files.items():
    ds = xr.open_dataset(f)
    lon, lat, dep = ds.longitude.values, ds.latitude.values, ds.depth.values
    print(f"\n== {name} ==")
    print(f"lon: {lon.min():.4f} to {lon.max():.4f} °E  ({lon.size} cells)")
    print(f"lat: {lat.min():.4f} to {lat.max():.4f} °N  ({lat.size} cells)")
    print(f"surface depth used: {dep[0]:.3f} m")
    print(f"box centroid: {lon.mean():.4f} °E, {lat.mean():.4f} °N")
    print(f"time: {str(ds.time.values[0])[:10]} to {str(ds.time.values[-1])[:10]}")

    # Land-masked (NaN) cells in the surface layer — they bias a plain mean()
    var = "so" if "so" in ds else "thetao"
    land = ds[var].isel(depth=0, time=0).isnull()
    print(f"land/NaN surface cells: {int(land.sum())} of {land.size}")