# Release Channels & Build Variants

## Overview

This project uses **build variants** to manage different release channels from a single codebase. Each variant maps to a specific Google Play Store track and serves different testing/production purposes.

## Build Variants

### Dev Variant (Personal Development)

- **Application ID**: `com.t4gc.fomomon.dev`
- **App Name**: "Fomomon Dev"
- **Build Command**: `flutter build appbundle --flavor dev`
- **Purpose**: Personal development and testing
- **Play Store Track**: Internal Testing (Personal Account)
- **Target Users**: Developer only

### Alpha Variant (Closed Testing)

- **Application ID**: `com.t4gc.fomomon.alpha`
- **App Name**: "Fomomon Alpha"
- **Build Command**: `flutter build appbundle --flavor alpha`
- **Purpose**: Closed testing with select users
- **Play Store Track**: Closed Testing
- **Target Users**: Internal team, trusted testers

### Beta Variant (Open Testing)

- **Application ID**: `com.t4gc.fomomon.beta`
- **App Name**: "Fomomon Beta"
- **Build Command**: `flutter build appbundle --flavor beta`
- **Purpose**: Public beta testing
- **Play Store Track**: Open Testing
- **Target Users**: Public beta testers

### Production Variant (Production)

- **Application ID**: `com.t4gc.fomomon`
- **App Name**: "Fomomon"
- **Build Command**: `flutter build appbundle --flavor production`
- **Purpose**: Production releases
- **Play Store Track**: Production
- **Target Users**: General public

## Google Play Store Track Mapping

### Internal Testing Track

- **Variant**: Dev (`com.t4gc.fomomon.dev`)
- **Purpose**: Personal development, quick iterations
- **Users**: Developer only (up to 100 internal testers)
- **Review**: No Google review required
- **Updates**: Instant deployment

### Closed Testing Track

- **Variant**: Alpha (`com.t4gc.fomomon.alpha`)
- **Purpose**: Limited testing with select users
- **Users**: Invited testers only (up to 2,000 testers)
- **Review**: No Google review required
- **Updates**: Instant deployment

### Open Testing Track

- **Variant**: Beta (`com.t4gc.fomomon.beta`)
- **Purpose**: Public beta testing
- **Users**: Anyone can join (unlimited testers)
- **Review**: No Google review required
- **Updates**: Instant deployment

### Production Track

- **Variant**: Production (`com.t4gc.fomomon`)
- **Purpose**: General public release
- **Users**: Everyone on Google Play
- **Review**: Full Google review required
- **Updates**: Review required for updates

See [app/build.gradle](`android/app/build.gradle.kts`) for implementation details.

### MainActivity Package

The MainActivity automatically uses the correct package name based on the build variant:

- Dev: `package com.t4gc.fomomon.dev`
- Alpha: `package com.t4gc.fomomon.alpha`
- Beta: `package com.t4gc.fomomon.beta`
- Production: `package com.t4gc.fomomon`

## Usage

### Building for Different Channels

```bash
# Personal development
flutter build appbundle --flavor dev
# Generates: app-dev-release.aab with com.t4gc.fomomon.dev

# Closed testing
flutter build appbundle --flavor alpha
# Generates: app-alpha-release.aab with com.t4gc.fomomon.alpha

# Open testing
flutter build appbundle --flavor beta
# Generates: app-beta-release.aab with com.t4gc.fomomon.beta

# Production
flutter build appbundle --flavor production
# Generates: app-production-release.aab with com.t4gc.fomomon
```

### Installing Multiple Variants

You can install multiple variants simultaneously on the same device for testing:

- Dev + Alpha + Beta + Production can all coexist
- Each has a different app icon and name
- Useful for comparing different versions

## File Structure

```
android/app/src/main/kotlin/
└── com/t4gc/fomomon/
    └── MainActivity.kt  # Used by all variants, templated
```

These are referenced in `android/app/key.properties` and used by all build variants.
See [docs/app_store.md](docs/app_store.md) for details.
