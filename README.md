# country_code_locator

[![CI](https://github.com/TerryHuangHD/country_code_locator/actions/workflows/ci.yml/badge.svg)](https://github.com/TerryHuangHD/country_code_locator/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Offline WGS 84 coordinate-to-country-code lookup for Flutter. The package loads
a bundled, versioned boundary index once and then returns a strict, officially
assigned ISO 3166-1 Alpha-2 code synchronously—without network access, GPS,
permissions, a platform geocoder, or a map-service SDK.

## Features

- Fully offline lookup after package installation.
- Synchronous queries after one asynchronous initialization.
- Pure Dart spatial grid, bounding-box, and point-in-polygon implementation.
- Polygon, MultiPolygon, holes, islands, and antimeridian support.
- Deterministic shared-boundary handling independent of source row order.
- Strict official ISO Alpha-2 filtering; placeholders and `XK` never escape.
- Validated binary data with format versioning, lengths, semantic checks, and
  CRC-32 integrity protection.
- Reproducible, checksum-pinned Natural Earth data pipeline.

## Install

```shell
flutter pub add country_code_locator
```

The boundary asset is declared by the package. Applications do not need to add
it to their own `pubspec.yaml`.

## Use

Load one locator during application startup and retain it for every query:

```dart
import 'package:country_code_locator/country_code_locator.dart';

final locator = await OfflineCountryCode.load();

final code = locator.lookup(
  latitude: 35.6812,
  longitude: 139.7671,
);

print(code); // JP
```

`lookup` returns `null` for ocean, uncovered or uncoded land, and a point that
matches different codes on a shared boundary.

### Input validation

Latitude must be finite and in `[-90, 90]`; longitude must be finite and in
`[-180, 180]`. Invalid values throw `ArgumentError`. Longitudes `-180` and
`180` are treated as the same meridian.

### Custom asset loading

Applications with their own loading layer can validate and initialize directly
from bytes:

```dart
final locator = OfflineCountryCode.fromBytes(bytes);
```

`fromBytes` decodes all runtime structures immediately and does not retain or
mutate the supplied `Uint8List`. `OfflineCountryCode.load(bundle: customBundle)`
is also available for a custom Flutter `AssetBundle`.

## Result policy

| Situation | Result |
| --- | --- |
| Point inside one officially coded land polygon | That uppercase Alpha-2 code |
| Multiple matching polygons with the same code | That code |
| Boundary shared by different codes | `null` |
| Ocean or data gap | `null` |
| Uncoded or non-official source region, including Kosovo/`XK` | `null` |
| Invalid coordinate | Throws `ArgumentError` |

This package identifies land polygons only. It does **not** identify territorial
waters, exclusive economic zones, addresses, administrative subdivisions, or
legal sovereignty.

## Data and accuracy

The bundled asset is generated from **Natural Earth 5.1.1, 1:10m Admin 0 – Map
Units**. Natural Earth depicts boundaries according to its de facto policy;
results do not express a legal position, sovereignty claim, or diplomatic
recognition.

Coordinates are quantized to `1e-5` degree and no polygon simplification or
island-area threshold is applied. Accuracy remains limited by the source map's
scale and policy. See [data provenance and regeneration](doc/DATA.md) and the
[binary format](doc/BINARY_FORMAT.md).

Natural Earth data is [Public Domain](https://www.naturalearthdata.com/about/terms-of-use/).
The library source is MIT licensed.

## Performance

The asset is **2,570,639 bytes (2.45 MiB)**. A reference profile-mode run on a
physical Pixel 10 measured 55.345 ms cold load, 8.875 µs average warm lookup,
and a 13.50 MiB process-wide peak-RSS delta. These are measurements, not service
level guarantees; application, device, build mode, and workload matter. Full
methodology and reproduction guidance are in [PERFORMANCE.md](doc/PERFORMANCE.md).

Runtime lookup consults a 2° spatial grid before polygon and ring bounds. It
does not scan every global polygon, reparse the asset, or copy the geometry per
query.

## Example

`example/lib/main.dart` contains a Material 3 application with editable latitude
and longitude fields. The package test suite also covers fixed real-world
coordinates, holes, MultiPolygon members, antimeridian wrapping, ambiguity,
invalid inputs, and corrupt assets.

## Updating the data

The generator uses only the Python standard library:

```shell
python3 tool/generate_boundaries.py
python3 tool/generate_boundaries.py --check
```

The first command downloads the source only when the local cache is absent,
verifies its SHA-256, regenerates the asset and sidecar metadata, and reports
changes from the previous asset. The second regenerates in memory and fails if
committed output differs. Review [DATA.md](doc/DATA.md) before changing a pin.

## Contributing and releasing

- [Contributing guide](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [pub.dev release checklist](PUBLISHING.md)
- [Changelog](CHANGELOG.md)
