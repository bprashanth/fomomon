#!/usr/bin/env python3
"""
Export AlphaEarth satellite embeddings from Google Earth Engine to GeoTIFF.

This script loads a GeoJSON file defining the area of interest, fetches AlphaEarth
embeddings from Google DeepMind's dataset, and exports them as a GeoTIFF that can
be used in the Flutter map widget.

Usage:
    python export_alphaearth.py

Configuration can be modified at the top of the script.
"""

import json
import ee
import geemap
from pathlib import Path

# ===== Configuration =====
YEAR = 2024  # Year to fetch embeddings from (2017-2024)
# Resolution in meters (can be changed to 20-30m if file too large)
RESOLUTION = 10
BANDS = ['A01', 'A16', 'A09']  # Three bands to visualize as RGB
MIN_VALUE = -0.3  # Minimum value for visualization
MAX_VALUE = 0.3   # Maximum value for visualization

# Paths
SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent
GEOJSON_PATH = PROJECT_ROOT / 'assets' / 'maps' / 'sites.geojson'
OUTPUT_DIR = PROJECT_ROOT / 'assets' / 'maps'
OUTPUT_FILENAME = f'alphaearth_{YEAR}_{RESOLUTION}m.tif'
OUTPUT_PATH = OUTPUT_DIR / OUTPUT_FILENAME

# AlphaEarth dataset ID
ALPHAEARTH_COLLECTION = 'GOOGLE/SATELLITE_EMBEDDING/V1/ANNUAL'

# Earth Engine project name
EE_PROJECT = 'plantwars'


def load_geojson(filepath):
    """Load GeoJSON file and extract geometries."""
    print(f"Loading GeoJSON from: {filepath}")

    with open(filepath, 'r') as f:
        geojson_data = json.load(f)

    features = geojson_data.get('features', [])
    print(f"Found {len(features)} features")

    # Calculate bounding box from all features
    all_lats = []
    all_lngs = []

    for feature in features:
        geom = feature.get('geometry')
        if not geom:
            continue

        geo_type = geom.get('type')
        coords = geom.get('coordinates')

        if not coords:
            continue

        # Extract coordinates based on geometry type
        coords_list = []
        if geo_type == 'Point':
            coords_list = [coords]
        elif geo_type == 'LineString':
            coords_list = coords
        elif geo_type == 'Polygon':
            # Take outer ring (first array)
            if coords and len(coords) > 0:
                coords_list = coords[0]
        elif geo_type == 'MultiLineString' or geo_type == 'MultiPolygon':
            # Flatten nested arrays
            for part in coords:
                if geo_type == 'MultiLineString':
                    coords_list.extend(part)
                else:  # MultiPolygon
                    if part and len(part) > 0:
                        coords_list.extend(part[0])

        # Collect all lat/lng values
        for coord in coords_list:
            if len(coord) >= 2:
                all_lngs.append(coord[0])
                all_lats.append(coord[1])

    if not all_lats:
        raise ValueError("No valid coordinates found in GeoJSON")

    # Calculate bounding box
    min_lat = min(all_lats)
    max_lat = max(all_lats)
    min_lng = min(all_lngs)
    max_lng = max(all_lngs)

    print(
        f"Calculated bounds: [{min_lat}, {min_lng}] to [{max_lat}, {max_lng}]")

    # Create a rectangular bounding box geometry
    aoi = ee.Geometry.Rectangle([min_lng, min_lat, max_lng, max_lat])

    print(f"Created bounding box geometry")

    return aoi


def get_alphaearth_image(year, bounds):
    """Fetch AlphaEarth embeddings for specified year and area."""
    print(f"Loading AlphaEarth embeddings for year {year}")

    dataset = ee.ImageCollection(ALPHAEARTH_COLLECTION)

    # Filter by date (embeddings are annual, so get the year)
    start_date = f"{year}-01-01"
    end_date = f"{year}-12-31"

    filtered = dataset.filterDate(start_date, end_date).filterBounds(bounds)

    # Get the first image (there should be only one per year)
    image = filtered.first()

    # Check if image exists
    try:
        _ = image.getInfo()
    except Exception as e:
        raise ValueError(
            f"No AlphaEarth data found for year {year} in this area: {e}")

    return image


def visualize_embeddings(image, bands):
    """Apply visualization parameters to create RGB image."""
    print(f"Creating RGB visualization with bands: {bands}")

    # Select the bands
    rgb_image = image.select(bands)

    # Apply visualization parameters
    # Scale to 0-255 range for RGB
    scaled = rgb_image.multiply(255 / (MAX_VALUE - MIN_VALUE)).subtract(
        MIN_VALUE * 255 / (MAX_VALUE - MIN_VALUE)
    ).clamp(0, 255)

    return scaled.toByte()


def export_raster(visualized_image, bounds, output_path):
    """Export the visualized image as a GeoTIFF."""
    print(f"Exporting GeoTIFF to: {output_path}")

    # Get bounds info for world file
    bounds_info = bounds.getInfo()

    # Create task - export as GeoTIFF
    task = ee.batch.Export.image.toDrive(
        image=visualized_image,
        description=f'alphaearth_{YEAR}_{RESOLUTION}m',
        scale=RESOLUTION,
        region=bounds,
        fileFormat='GEO_TIFF',
    )

    print(f"Starting export task...")
    task.start()

    print("Waiting for task to complete...")
    import time

    while task.active():
        status = task.status()
        print(f"Progress: {status.get('state')}")
        time.sleep(5)

    status = task.status()
    print(f"Export completed: {status}")

    # GeoTIFF files contain their own georeferencing, no world file needed

    print(f"\n✓ Export task completed!")
    print(
        f"  The file will be in your Google Drive as: alphaearth_{YEAR}_{RESOLUTION}m.tif")
    print(f"  Download it from: https://drive.google.com")
    print(f"  Then move it to: {output_path}")
    print(f"\nNote: The exported GeoTIFF can be converted to PNG if needed")


def _create_world_file(bounds_info, output_path):
    """Create a PGW (world file) for the exported image.

    Note: This function is kept for reference but not needed for GeoTIFF
    since GeoTIFF already contains georeferencing information.
    """
    pass


def main():
    """Main execution function."""
    print("="*60)
    print("AlphaEarth Embeddings Exporter")
    print("="*60)
    print()

    # Initialize Earth Engine
    print("Initializing Earth Engine...")
    try:
        ee.Initialize(project=EE_PROJECT)
        print(f"✓ Initialized with project: {EE_PROJECT}")
    except Exception as e:
        print(f"Error initializing Earth Engine: {e}")
        print("Run: earthengine authenticate")
        print("or visit: https://code.earthengine.google.com")
        return 1

    # Load the AOI
    try:
        aoi = load_geojson(GEOJSON_PATH)
    except Exception as e:
        print(f"Error loading GeoJSON: {e}")
        return 1

    # Get AlphaEarth image
    try:
        image = get_alphaearth_image(YEAR, aoi)
    except Exception as e:
        print(f"Error fetching AlphaEarth data: {e}")
        return 1

    # Create visualization
    visualized = visualize_embeddings(image, BANDS)

    # Export
    try:
        export_raster(visualized, aoi, OUTPUT_PATH)
    except Exception as e:
        print(f"Error exporting GeoTIFF: {e}")
        return 1

    print()
    print("="*60)
    print("✓ All done!")
    print("="*60)

    return 0


if __name__ == "__main__":
    exit(main())
