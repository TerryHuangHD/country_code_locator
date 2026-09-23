# Data provenance and regeneration

## Pinned inputs

| Input | Pin | SHA-256 |
| --- | --- | --- |
| Natural Earth 1:10m Admin 0 – Map Units | 5.1.1 | `45bebe2aaf8bf42b9daf4428594925bcb11eabd32fe9dc6e0acf681438053eb5` |
| ISO 3166-1 officially assigned Alpha-2 snapshot | 2026-09-23, 249 codes | `801ef127f0b3e6b4e971c239c9b8475caedb65c17573d84ca1b57eed72523a0e` |

The machine-readable pins live in `tool/data/sources.json`. The Natural Earth
archive is downloaded from its official CDN into ignored `tool/cache/` storage.
The ISO list is a committed snapshot of the official ISO Online Browsing
Platform code set. Any checksum mismatch stops generation before parsing.

Natural Earth publishes its raster and vector map data as Public Domain under
its [Terms of Use](https://www.naturalearthdata.com/about/terms-of-use/). ISO
permits free use of its country codes; ISO remains the source and maintenance
authority for the officially assigned set.

## Mapping policy

The generator reads the Natural Earth `ISO_A2_EH` field and accepts a value only
when it appears in the pinned official allowlist. This field preserves official
Alpha-2 values such as `TW` while still allowing strict rejection of `XK`,
`-99`, empty values, placeholders, and user-assigned codes.

Uncoded source polygons are retained with an internal null-code sentinel. A
query hitting one returns `null`; the region cannot accidentally fall through
to an overlapping coded geometry. The runtime code table itself contains only
uppercase, officially assigned values.

Natural Earth's Admin 0 data follows its de facto boundary policy. The package
does not assert legal sovereignty or diplomatic recognition and exposes no
political-policy switch.

## Geometry policy

- Quantization: 100,000 integer units per degree (`1e-5°`), nearest with ties
  away from zero.
- Simplification: none.
- Island removal: none.
- Polygon holes: retained and associated with their containing outer ring.
- MultiPolygon features: encoded as independently indexed polygon records with
  the same code.
- Antimeridian: rings are unwrapped before quantization; query longitudes are
  projected into each candidate's local interval.
- Index: 180 × 90 cells, each 2° × 2°, stored as a CSR reference table.
- Boundary policy: a single code wins; different matching codes or uncoded
  geometry produce `null`.

## Current output

| Metric | Value |
| --- | ---: |
| Asset SHA-256 | `584f7161c86d7e435c1570c7fc9b3bf9817e765fa519912b8c0f61f3ca81db7d` |
| Asset bytes | 2,570,639 |
| Codes represented | 248 |
| Source records | 298 |
| Coded / uncoded source records | 280 / 18 |
| Polygons | 4,292 |
| Rings | 4,312 |
| Quantized points | 548,513 |
| Grid references | 17,686 |
| Removed degenerate rings | 0 |
| Removed islands | 0 |

`assets/country_boundaries.metadata.json` is the authoritative generated
sidecar. It also contains the complete represented code set and the non-metadata
payload digest.

## Regenerate

Python 3.10 or newer is sufficient; the generator has no third-party packages.
From the repository root:

```shell
python3 tool/generate_boundaries.py
```

The command:

1. reads `tool/data/sources.json`;
2. downloads the archive if absent;
3. verifies Natural Earth and allowlist SHA-256 values;
4. validates the Shapefile and DBF structures;
5. filters codes, normalizes rings, preserves holes, and builds the grid;
6. writes the deterministic binary and canonical metadata atomically; and
7. reports code-set, polygon, ring, point, removed-island, and size differences
   from the existing sidecar.

Verify committed bytes from the same pinned inputs:

```shell
python3 tool/generate_boundaries.py --check
```

## Review an update

Before accepting a source, allowlist, generator, quantization, or format change:

1. update explicit pins and expected checksums;
2. regenerate twice and require byte-identical output;
3. review added/removed codes and every reported count/size delta;
4. confirm no unexpected island or geometry loss;
5. run the full fixed-coordinate and synthetic geometry suite;
6. confirm corrupt, truncated, and unsupported data still fail loading;
7. rerun the physical-device benchmark and update `PERFORMANCE.md`; and
8. manually review material boundary or result changes before release.
