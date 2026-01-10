#!/usr/bin/env python3
"""
Convert GeoTIFF to PNG for use in Flutter app.

After downloading the GeoTIFF from Google Drive, run this script to convert it
to PNG format that Flutter can display.

Requirements:
    pip install rasterio pillow

Usage:
    python convert_geotiff_to_png.py
"""

import rasterio
from rasterio.enums import Resampling
from PIL import Image
from pathlib import Path

# Configuration
SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent
INPUT_TIFF = PROJECT_ROOT / 'assets' / 'maps' / 'alphaearth_2024_10m.tif'
OUTPUT_PNG = PROJECT_ROOT / 'assets' / 'maps' / 'alphaearth_2024_10m.png'


def convert_geotiff_to_png(input_path, output_path):
    """Convert GeoTIFF to PNG format."""
    print(f"Converting {input_path.name} to {output_path.name}...")

    # Open the GeoTIFF
    import numpy as np

    with rasterio.open(input_path) as src:
        # Read the image data
        # If it's multiband (RGB), read all bands
        if src.count >= 3:
            data = src.read([1, 2, 3])  # Read RGB bands
            # Convert (3, height, width) -> (height, width, 3)
            rgb_data = np.transpose(data, (1, 2, 0))
            # Ensure values are in 0-255 range
            rgb_data = np.clip(rgb_data, 0, 255).astype('uint8')
            image = Image.fromarray(rgb_data, 'RGB')
        else:
            # Single band, duplicate for grayscale
            data = src.read(1)
            # Ensure values are in 0-255 range
            data = np.clip(data, 0, 255).astype('uint8')
            image = Image.fromarray(data, 'L')

        # Get metadata
        width = src.width
        height = src.height
        transform = src.transform

        print(f"Image dimensions: {width}x{height}")
        print(f"Bounds: {src.bounds}")

    # Save as PNG
    image.save(output_path, 'PNG')
    print(f"✓ Converted to: {output_path}")

    # Also save the bounds info in a text file for reference
    bounds_file = output_path.with_suffix('.txt')
    with open(bounds_file, 'w') as f:
        f.write(f"Original bounds: {src.bounds}\n")
        f.write(f"Transform: {transform}\n")
        f.write(f"Width: {width}, Height: {height}\n")

    print(f"Bounds saved to: {bounds_file}")


if __name__ == "__main__":
    if not INPUT_TIFF.exists():
        print(f"Error: {INPUT_TIFF} not found")
        print(f"Please download the GeoTIFF from Google Drive first")
        exit(1)

    convert_geotiff_to_png(INPUT_TIFF, OUTPUT_PNG)
    print("\n✓ Conversion complete!")
