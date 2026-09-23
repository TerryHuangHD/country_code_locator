# Country boundary binary format

Format version `2` is a little-endian, self-validating container optimized for
one-time loading and repeated synchronous lookup. All offsets are absolute byte
offsets from the beginning of the file. Integers are unsigned unless marked
signed.

## Header

The fixed header is 80 bytes.

| Offset | Type | Meaning |
| ---: | --- | --- |
| 0 | 8 bytes | ASCII magic `CCLOCATR` |
| 8 | `u16` | Format version (`2`) |
| 10 | `u16` | Header length (`80`) |
| 12 | `u32` | Total file length |
| 16 | `u32` | CRC-32/ISO-HDLC of bytes `[80, total length)` |
| 20 | `u32` | Coordinate quantization scale (`100000` units/degree) |
| 24 | `u16` | Grid width (`180`) |
| 26 | `u16` | Grid height (`90`) |
| 28 | `u16` | Number of ISO code entries |
| 30 | `u16` | Reserved; must be zero |
| 32 | `u32` | Polygon count |
| 36 | `u32` | Ring count |
| 40 | `u32` | Decoded point count |
| 44 | `u32` | Spatial-index reference count |
| 48 | `u32` | Code-table offset |
| 52 | `u32` | Polygon-table offset |
| 56 | `u32` | Ring-table offset |
| 60 | `u32` | Encoded-point-stream offset |
| 64 | `u32` | Cell-offset-table offset |
| 68 | `u32` | Cell-reference-table offset |
| 72 | `u32` | Metadata offset |
| 76 | `u32` | Metadata byte length |

Sections are contiguous and ordered exactly as listed. A loader rejects an
unknown version, non-zero reserved field, inconsistent count or offset,
truncated section, trailing data, checksum mismatch, invalid code, invalid
index, invalid ring, or out-of-range coordinate.

## Code table

Code records are sorted by Alpha-2 and stored as five uppercase ASCII bytes
each: two Alpha-2 bytes followed by their corresponding three Alpha-3 bytes.
Both codes and the exact pair must appear in the pinned ISO 3166-1 mapping;
the runtime rejects mismatches even when both individual codes are official.

## Polygon table

Each 28-byte record contains:

1. `u16` code index; `0xffff` means that the source geometry has no officially
   assigned code and therefore resolves to `null`.
2. `u16` ring count.
3. `u32` first ring index.
4. Four signed `i32` bounds: minimum longitude, minimum latitude, maximum
   longitude, maximum latitude.
5. Signed `i32` longitude center used to project a canonical query longitude
   into the polygon's unwrapped longitude interval.

The first ring is the outer ring. Remaining rings are holes. A Shapefile
MultiPolygon is represented by multiple polygon records with the same code.

## Ring table and point stream

Each 24-byte ring record contains a byte offset relative to the point stream,
point count, and four signed `i32` bounds. Rings contain at least three distinct
points; the closing point is implicit.

The first point is stored as two ZigZag-encoded unsigned varints. Every later
point stores ZigZag-encoded deltas from the preceding point. Longitude is
unwrapped before quantization, so antimeridian-crossing rings remain locally
continuous. Latitude and longitude are quantized by rounding to the nearest
`1 / scale` degree.

## Spatial grid

The world is divided into `180 × 90` cells of `2° × 2°`. The cell-offset table
is a CSR offset array of `(cell count + 1)` `u32` values. The reference table
contains sorted, unique polygon indexes. Polygon bounds are projected back to
the canonical `[-180°, 180°)` longitude domain when cells are populated.

Lookup always uses the grid first, then polygon bounds, then ring bounds and
point-in-polygon. Every candidate is evaluated. Multiple hits with one code
return that code; hits with different codes, or a hit on uncoded geometry,
return `null`.

## Metadata

The final section is canonical UTF-8 JSON (`sort_keys=true`, compact
separators). It records source URL/version/SHA-256, mapping provenance and
SHA-256, generator version, format version, quantization, simplification,
counts, parallel Alpha-2 `codes` and `alpha3_codes` arrays, and a SHA-256 digest
of the non-metadata payload. The deterministic sidecar metadata file
additionally records the completed asset's SHA-256.
