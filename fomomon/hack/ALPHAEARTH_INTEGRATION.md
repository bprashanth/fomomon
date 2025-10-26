# AlphaEarth Integration Summary

## What Was Implemented

This integration adds Google DeepMind's AlphaEarth satellite embeddings visualization to the Fomomon map widget.

### Files Created

1. **`hack/export_alphaearth.py`** - Python script to export AlphaEarth embeddings from Google Earth Engine

   - Loads the GeoJSON defining the area of interest
   - Fetches AlphaEarth embeddings for a specified year (default: 2024)
   - Selects 3 bands from the 64 available (default: A01, A16, A09)
   - Exports as GeoTIFF to Google Drive
   - Configurable: year, resolution (default 10m), bands

2. **`hack/convert_geotiff_to_png.py`** - Conversion script for Flutter compatibility

   - Converts downloaded GeoTIFF to PNG format
   - Requires: `rasterio` and `pillow` packages
   - Outputs PNG ready for Flutter display

3. **`hack/README.md`** - User documentation with step-by-step instructions

4. **`hack/ALPHAEARTH_INTEGRATION.md`** - This file, technical summary of the integration

### Files Modified

1. **`lib/widgets/site_map_widget.dart`**
   - Added state management for AlphaEarth image bytes and opacity
   - Added `_checkForAlphaEarthImage()` to load the PNG asset
   - Added `_buildAlphaEarthOverlay()` to render the AlphaEarth transparency overlay
   - Modified map children to always show basemap + overlay when active
   - Added **slider control at bottom** for adjusting overlay opacity (0-100%)
   - Overlay blends with underlying basemap using opacity control

## How It Works

### Export Process

1. Run the Python script:

   ```bash
   cd hack
   python export_alphaearth.py
   ```

2. Authenticate with Earth Engine if needed:

   ```bash
   earthengine authenticate
   ```

3. The script will:

   - Load your `assets/maps/sites.geojson` file
   - Query AlphaEarth embeddings for the specified year
   - Export as GeoTIFF to your Google Drive

4. **Download and convert**:
   - Download the GeoTIFF from Google Drive
   - Place it in `assets/maps/alphaearth_2024_10m.tif`
   - Run `python convert_geotiff_to_png.py` to convert to PNG format

### Display in Flutter App

The map widget has an **AlphaEarth transparency overlay** at the bottom:

1. **Loading**: On app start, checks for `assets/maps/alphaearth_2024_10m.png`
2. **Control**: A slider at the bottom (with grass icon) controls overlay opacity
3. **Default**: Overlay starts at 0% (hidden) - move slider to reveal
4. **Rendering**: The PNG is placed as an overlay on top of the basemap (satellite/contour)
5. **Georeferencing**: Image placement based on bounds from KML/GeoJSON data

## Configuration

In `hack/export_alphaearth.py`, you can adjust:

```python
YEAR = 2024              # Year to fetch (2017-2024)
RESOLUTION = 10          # Meters per pixel
BANDS = ['A01', 'A16', 'A09']  # RGB bands from 64 available
MIN_VALUE = -0.3         # Visualization min
MAX_VALUE = 0.3          # Visualization max
```

## Technical Details

### Why PNG + World File Instead of GeoTIFF?

- Flutter doesn't have native GeoTIFF support
- PNG + world file is simpler to implement
- `flutter_map` can display overlay images with bounds
- Easier to modify/update the visualization

### File Size Considerations

- **10m resolution**: ~1-5MB for small areas
- **20m resolution**: ~250KB - 1MB
- **30m resolution**: ~100KB - 500KB

If file is too large, increase `RESOLUTION` value.

### Future Enhancements

Potential improvements:

1. Add tile server support for dynamic loading
2. Support multiple years with a time slider
3. Add user selection of which bands to visualize
4. Add export of specific classifications/analyses

## References

- [Google DeepMind AlphaEarth Blog](https://deepmind.google/discover/blog/alphaearth-foundations-helps-map-our-planet-in-unprecedented-detail/)
- [AlphaEarth Dataset](https://developers.google.com/earth-engine/datasets/catalog/GOOGLE_SATELLITE_EMBEDDING_V1_ANNUAL)
- [AlphaEarth Tutorial](https://leafmap.org/maplibre/AlphaEarth/)
- [YouTube Tutorial](https://www.youtube.com/watch?v=EGL7fXyA7-U)
