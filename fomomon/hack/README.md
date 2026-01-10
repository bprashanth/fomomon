# Hack Directory

This directory contains development scripts and tools for the Fomomon project.

## AlphaEarth Integration

### Setup

Install required Python packages:

```bash
pip install earthengine-api geemap rasterio pillow
```

- `earthengine-api`: For Earth Engine authentication and API access
- `geemap`: For interactive Earth Engine mapping (may be optional)
- `rasterio`: For reading GeoTIFF files
- `pillow`: For converting to PNG format

### Authenticate with Earth Engine

Before running the export script, authenticate with Google Earth Engine:

```bash
earthengine authenticate
```

Alternatively, visit [Google Earth Engine Code Editor](https://code.earthengine.google.com) to enable access.

### Export AlphaEarth Embeddings

#### Step 1: Export from Earth Engine

Run the export script to generate a GeoTIFF:

```bash
python export_alphaearth.py
```

#### Step 2: Download the GeoTIFF

The script creates an export task in Earth Engine. After completion:

1. Go to [Google Drive](https://drive.google.com)
2. Find the file named `alphaearth_2024_10m.tif`
3. Download it to your computer

#### Step 3: Convert to PNG for Flutter

Move the GeoTIFF to `assets/maps/` and convert it:

```bash
# Place the downloaded file
cp ~/Downloads/alphaearth_2024_10m.tif assets/maps/

# Convert to PNG
python convert_geotiff_to_png.py
```

This creates `alphaearth_2024_10m.png` ready for Flutter.

### Configuration

Edit `export_alphaearth.py` to configure:

- **YEAR**: Year to fetch embeddings from (2017-2024), default: 2024
- **RESOLUTION**: Resolution in meters (10m, 20m, 30m), default: 10
- **BANDS**: Three bands to visualize as RGB, default: ['A01', 'A16', 'A09']
- **MIN_VALUE/MAX_VALUE**: Visualization range, default: -0.3 to 0.3

### File Size Considerations

- **10m resolution**: ~1-5MB for a small area
- **20m resolution**: ~250KB - 1MB
- **30m resolution**: ~100KB - 500KB

If the file is too large, increase the `RESOLUTION` value.

### Usage in Flutter

Once the PNG is in `assets/maps/`, it will automatically be available in the map widget.

The AlphaEarth overlay appears as a transparency control at the bottom of the map:

- Move the slider to adjust opacity (0% = hidden, 100% = fully visible)
- The overlay blends with the underlying satellite/contour basemap
- The grass icon indicates AI embeddings visualization

### References

- [Google DeepMind AlphaEarth Blog](https://deepmind.google/discover/blog/alphaearth-foundations-helps-map-our-planet-in-unprecedented-detail/)
- [AlphaEarth Dataset](https://developers.google.com/earth-engine/datasets/catalog/GOOGLE_SATELLITE_EMBEDDING_V1_ANNUAL)
- [AlphaEarth Tutorial](https://leafmap.org/maplibre/AlphaEarth/)
- [Earth Engine Export Documentation](https://developers.google.com/earth-engine/guides/image_export)
