# Data provenance and regeneration

## Pinned inputs

| Input | Pin | SHA-256 |
| --- | --- | --- |
| Natural Earth 1:10m Admin 0 – Map Units | 5.1.1 | `45bebe2aaf8bf42b9daf4428594925bcb11eabd32fe9dc6e0acf681438053eb5` |
| ISO 3166-1 officially assigned Alpha-2/Alpha-3 pairs | pycountry 26.2.16, commit `4ba3951667c2ed98363a3640c9022cf1b7a59300`, 249 pairs | `e0b1ba597ec82374406bbc87db49ced745b77d1a893c482a1741253e470fd3c2` |

The machine-readable pins live in `tool/data/sources.json`. The Natural Earth
archive is downloaded from its official CDN into ignored `tool/cache/` storage.
The committed sorted `AA AAA` mapping was derived from
[pycountry's ISO 3166-1 data](https://github.com/pycountry/pycountry/blob/4ba3951667c2ed98363a3640c9022cf1b7a59300/src/pycountry/databases/iso3166-1.json)
(upstream JSON SHA-256
`f01b812b57fba9f31ff621bf33e7c7570a01964dbeb5be2167e94decf538c89f`).
Its 249 Alpha-2 keys match the previous pinned official ISO snapshot exactly.
Any committed mapping checksum mismatch stops generation before parsing.

Natural Earth publishes its raster and vector map data as Public Domain under
its [Terms of Use](https://www.naturalearthdata.com/about/terms-of-use/). ISO
permits free use of its country codes; ISO remains the source and maintenance
authority for the officially assigned set.

## Mapping policy

The generator reads the Natural Earth `ISO_A2_EH` field and accepts a value only
when it appears in the pinned official mapping. This field preserves official
Alpha-2 values such as `TW` while still allowing strict rejection of `XK`,
`-99`, empty values, placeholders, and user-assigned codes. Each accepted
Alpha-2 value has one pinned official Alpha-3 partner.

Uncoded source polygons are retained with an internal null-code sentinel. A
query hitting one returns `null`; the region cannot accidentally fall through
to overlapping coded geometry. The runtime code table contains only validated
official pairs, and both requested formats use identical boundary decisions.

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
| Asset SHA-256 | `8c2c0176d801323386ee9602ac7df1c0a449e4437af338211b6b658d98f84478` |
| Asset bytes | 2,573,123 |
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
sidecar. It contains both represented code lists and the non-metadata payload
digest. Compared with the version 1 asset, all polygon, ring, point, and grid
index bytes are unchanged; only the code table and metadata changed.

## Regenerate

Python 3.10 or newer is sufficient; the generator has no third-party packages.
From the repository root:

```shell
python3 tool/generate_boundaries.py
```

The command:

1. reads `tool/data/sources.json`;
2. downloads the Natural Earth archive if absent;
3. verifies Natural Earth and pinned code-mapping SHA-256 values;
4. validates the Shapefile and DBF structures;
5. filters codes, normalizes rings, preserves holes, and builds the grid;
6. writes the deterministic binary, canonical metadata, and runtime code-pair
   validator atomically; and
7. reports code-set, polygon, ring, point, removed-island, and size differences
   from the existing sidecar.

Verify committed bytes from the same pinned inputs:

```shell
python3 tool/generate_boundaries.py --check
```

## Review an update

Before accepting a source, code mapping, generator, quantization, or format change:

1. update explicit pins and expected checksums;
2. regenerate twice and require byte-identical output;
3. review added/removed codes and every reported count/size delta;
4. confirm no unexpected island or geometry loss;
5. run the full fixed-coordinate and synthetic geometry suite;
6. confirm corrupt, truncated, and unsupported data still fail loading;
7. rerun the physical-device benchmark and update `PERFORMANCE.md`; and
8. manually review material boundary or result changes before release.
