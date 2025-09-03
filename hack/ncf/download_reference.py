import os
import requests
from PIL import Image
from io import BytesIO

# Path to your mapping file
INPUT_FILE = "./sites_to_reference_images.txt"
OUTPUT_DIR = "resized_images"
MAX_SIZE_BYTES = 1 * 1024 * 1024  # 1MB

os.makedirs(OUTPUT_DIR, exist_ok=True)

def download_and_resize(site_id, url):
    # Get the filename from the URL
    filename = url.split("/")[-1]
    local_filename = f"{site_id}_{filename}"
    output_path = os.path.join(OUTPUT_DIR, local_filename)

    # Download the image
    print(f"Downloading {url} ...")
    response = requests.get(url)
    response.raise_for_status()
    img = Image.open(BytesIO(response.content)).convert("RGB")

    # Save with decreasing quality until under 1MB
    quality = 95
    while quality >= 10:
        buffer = BytesIO()
        img.save(buffer, format="JPEG", quality=quality)
        size = buffer.tell()
        if size <= MAX_SIZE_BYTES:
            with open(output_path, "wb") as f:
                f.write(buffer.getvalue())
            print(f"✅ Saved: {output_path} ({size/1024:.1f} KB, quality={quality})")
            return
        quality -= 5

    print(f"⚠️ Could not reduce {url} below 1MB")

def main():
    with open(INPUT_FILE, "r") as f:
        for line in f:
            if not line.strip():
                continue
            parts = line.strip().split()
            if len(parts) != 2:
                print(f"Skipping malformed line: {line.strip()}")
                continue
            site_id, url = parts
            try:
                download_and_resize(site_id, url)
            except Exception as e:
                print(f"❌ Error processing {site_id}: {e}")

if __name__ == "__main__":
    main()

