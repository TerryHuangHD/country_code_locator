## 1.1.3 - 2026-11-05

- Upgraded the FVM and CI toolchain to Flutter 3.47.9 / Dart 3.13.7.
- Updated analyzer exclusions for Flutter-generated build output.
- Recorded a fresh Pixel 10 profile-mode benchmark with the upgraded toolchain.

## 1.1.2 - 2026-10-02

- Named TerryHuangHD as the MIT license copyright holder.
- Removed the English-precedence notes from the translated READMEs.

## 1.1.1 - 2026-10-02

- Added Traditional Chinese and Japanese README translations.

## 1.1.0 - 2026-09-24

- Added per-lookup ISO 3166-1 Alpha-2 or Alpha-3 selection; Alpha-2 remains the default.
- Pinned and validated the official Alpha-2/Alpha-3 mapping in the version 2 boundary asset.
- Updated the Flutter example to switch code formats without reloading geometry.

## 1.0.0 - 2026-09-23

- Added offline WGS 84 coordinate lookup with synchronous post-load queries.
- Added strict ISO 3166-1 Alpha-2 filtering and deterministic ambiguity rules.
- Added Polygon, MultiPolygon, hole, island, and antimeridian handling.
- Added a validated, indexed Natural Earth 5.1.1 binary asset.
- Added a reproducible checksum-pinned data generator and provenance metadata.
- Added fixed-coordinate, geometry, input-validation, and corruption coverage.
- Added a Flutter example, performance benchmark, CI, and pub.dev release flow.
