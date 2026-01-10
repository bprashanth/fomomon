# Geojson vs kml

First inspect the kml 
```
$ ogrinfo ./sites.kml 
INFO: Open of `./sites.kml'
      using driver `LIBKML' successful.
1: Temporary Places
2: A_Transects_V2.kml
3: A_Transects_V2
4: 100X100 Grids in 300 m circle
```
Convert 

```
$ ogr2ogr -f GeoJSON sites.geojson sites.kml "Temporary Places" -nln sites
$ ogr2ogr -f GeoJSON sites.geojson sites.kml "A_Transects_V2.kml" -update -append -nln sites
$ ogr2ogr -f GeoJSON sites.geojson sites.kml "A_Transects_V2" -update -append -nln sites
$ ogr2ogr -f GeoJSON sites.geojson sites.kml "100X100 Grids in 300 m circle" -update -append -nln sites
```
Then run 
```
$ ogrinfo sites.geojson 
INFO: Open of `sites.geojson'
      using driver `GeoJSON' successful.
1: sites

```
