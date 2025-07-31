# App Icon Setup

## How to Use flutter_launcher_icons

1. **Place your icon image** in `fomomon/assets/icon/` as `app_icon.png`

   - Must be a square image (1:1 aspect ratio)
   - Recommended size: 1024x1024 pixels
   - PNG format preferred
   - No transparency (solid background required)

2. **Generate all icon sizes** by running:

   ```bash
   flutter pub run flutter_launcher_icons:main
   ```

3. **Clean and regenerate** if you make changes:
   ```bash
   flutter clean
   flutter pub get
   flutter pub run flutter_launcher_icons:main
   ```

## What this will generate:

- **Android**: All required mipmap sizes (mdpi, hdpi, xhdpi, xxhdpi, xxxhdpi)
- **iOS**: All required icon sizes for iPhone and iPad
- **Web**: Favicon and PWA icons
- **Windows**: App icon
- **macOS**: App icon

## Configuration

The configuration is in `pubspec.yaml` under the `flutter_launcher_icons:` section.
You can customize colors, sizes, and which platforms to generate icons for.
