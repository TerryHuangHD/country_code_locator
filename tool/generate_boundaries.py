#!/usr/bin/env python3
"""Generate the deterministic country boundary runtime asset.

The tool intentionally uses only the Python standard library. It verifies every
pinned input before parsing the Natural Earth Shapefile and never trusts an
unpinned download.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import struct
import sys
import tempfile
import urllib.request
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "tool" / "data" / "sources.json"
DEFAULT_OUTPUT = ROOT / "assets" / "country_boundaries.bin"
DEFAULT_METADATA = ROOT / "assets" / "country_boundaries.metadata.json"
MAGIC = b"CCLOCATR"
HEADER_LENGTH = 80
POLYGON_RECORD_LENGTH = 28
RING_RECORD_LENGTH = 24
NULL_CODE_INDEX = 0xFFFF
WORLD_DEGREES = 360


class GenerationError(RuntimeError):
    """An input or generated-data invariant was violated."""


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _read_config() -> dict[str, object]:
    return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))


def _resolve(path: str) -> Path:
    candidate = Path(path)
    return candidate if candidate.is_absolute() else ROOT / candidate


def _download(url: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    print(f"Downloading {url}")
    with tempfile.NamedTemporaryFile(
        dir=destination.parent, prefix=destination.name, delete=False
    ) as temporary:
        temporary_path = Path(temporary.name)
        try:
            with urllib.request.urlopen(url, timeout=60) as response:
                while chunk := response.read(1024 * 1024):
                    temporary.write(chunk)
            temporary.flush()
            os.fsync(temporary.fileno())
        except BaseException:
            temporary_path.unlink(missing_ok=True)
            raise
    os.replace(temporary_path, destination)


def _load_allowlist(config: dict[str, object]) -> tuple[list[str], bytes]:
    iso = config["iso_3166_1"]
    assert isinstance(iso, dict)
    path = _resolve(str(iso["alpha2_allowlist"]))
    data = path.read_bytes()
    actual_hash = _sha256(data)
    if actual_hash != iso["sha256"]:
        raise GenerationError(
            f"ISO allowlist checksum mismatch: expected {iso['sha256']}, "
            f"got {actual_hash}"
        )
    codes = data.decode("ascii").splitlines()
    if codes != sorted(set(codes)):
        raise GenerationError("ISO allowlist must be sorted and contain no duplicates")
    if len(codes) != iso["count"]:
        raise GenerationError(
            f"ISO allowlist count mismatch: expected {iso['count']}, got {len(codes)}"
        )
    if any(re.fullmatch(r"[A-Z]{2}", code) is None for code in codes):
        raise GenerationError("ISO allowlist contains an invalid Alpha-2 code")
    return codes, data


def _load_source(config: dict[str, object], override: Path | None) -> bytes:
    source = config["natural_earth"]
    assert isinstance(source, dict)
    path = override or _resolve(str(source["archive"]))
    if not path.exists():
        if override is not None:
            raise GenerationError(f"Source archive does not exist: {path}")
        _download(str(source["source_url"]), path)
    data = path.read_bytes()
    actual_hash = _sha256(data)
    if actual_hash != source["sha256"]:
        raise GenerationError(
            f"Natural Earth checksum mismatch: expected {source['sha256']}, "
            f"got {actual_hash}"
        )
    return data


def _decode_dbf(data: bytes) -> list[dict[str, str]]:
    if len(data) < 33:
        raise GenerationError("DBF header is truncated")
    record_count = struct.unpack_from("<I", data, 4)[0]
    header_length = struct.unpack_from("<H", data, 8)[0]
    record_length = struct.unpack_from("<H", data, 10)[0]
    if header_length < 33 or record_length < 2:
        raise GenerationError("DBF header contains invalid lengths")

    fields: list[tuple[str, int, int]] = []
    cursor = 32
    field_offset = 1
    while cursor < header_length and data[cursor] != 0x0D:
        if cursor + 32 > len(data):
            raise GenerationError("DBF field descriptor is truncated")
        descriptor = data[cursor : cursor + 32]
        name = descriptor[:11].split(b"\0", 1)[0].decode("ascii")
        length = descriptor[16]
        if length == 0:
            raise GenerationError(f"DBF field {name} has zero length")
        fields.append((name, field_offset, length))
        field_offset += length
        cursor += 32
    if cursor >= len(data) or data[cursor] != 0x0D:
        raise GenerationError("DBF field descriptor terminator is missing")
    if field_offset != record_length:
        raise GenerationError("DBF field lengths do not match record length")
    expected_end = header_length + record_count * record_length
    if expected_end > len(data):
        raise GenerationError("DBF records are truncated")

    records: list[dict[str, str]] = []
    for index in range(record_count):
        start = header_length + index * record_length
        row = data[start : start + record_length]
        if row[0] == 0x2A:
            raise GenerationError(f"DBF record {index + 1} is marked deleted")
        if row[0] != 0x20:
            raise GenerationError(f"DBF record {index + 1} has an invalid marker")
        values: dict[str, str] = {}
        for name, offset, length in fields:
            value = row[offset : offset + length].decode("utf-8")
            values[name] = value.split("\0", 1)[0].strip()
        records.append(values)
    return records


def _decode_shp(data: bytes) -> list[list[list[tuple[float, float]]]]:
    if len(data) < 100:
        raise GenerationError("SHP header is truncated")
    if struct.unpack_from(">I", data, 0)[0] != 9994:
        raise GenerationError("SHP file code is invalid")
    declared_length = struct.unpack_from(">I", data, 24)[0] * 2
    if declared_length != len(data):
        raise GenerationError("SHP declared length does not match archive member")
    if struct.unpack_from("<I", data, 28)[0] != 1000:
        raise GenerationError("SHP version is unsupported")
    if struct.unpack_from("<I", data, 32)[0] != 5:
        raise GenerationError("SHP must contain Polygon records")

    records: list[list[list[tuple[float, float]]]] = []
    cursor = 100
    expected_record_number = 1
    while cursor < len(data):
        if cursor + 12 > len(data):
            raise GenerationError("SHP record header is truncated")
        record_number, content_words = struct.unpack_from(">II", data, cursor)
        if record_number != expected_record_number:
            raise GenerationError("SHP record numbers are not sequential")
        content_start = cursor + 8
        content_end = content_start + content_words * 2
        if content_end > len(data):
            raise GenerationError(f"SHP record {record_number} is truncated")
        shape_type = struct.unpack_from("<I", data, content_start)[0]
        if shape_type == 0:
            records.append([])
        elif shape_type == 5:
            if content_start + 44 > content_end:
                raise GenerationError(f"SHP record {record_number} is malformed")
            part_count, point_count = struct.unpack_from(
                "<II", data, content_start + 36
            )
            part_table_start = content_start + 44
            point_table_start = part_table_start + part_count * 4
            expected_end = point_table_start + point_count * 16
            if part_count == 0 or point_count == 0 or expected_end != content_end:
                raise GenerationError(
                    f"SHP record {record_number} has inconsistent counts"
                )
            parts = list(
                struct.unpack_from(f"<{part_count}I", data, part_table_start)
            )
            if parts[0] != 0 or parts != sorted(set(parts)):
                raise GenerationError(f"SHP record {record_number} has invalid parts")
            parts.append(point_count)
            points = [
                struct.unpack_from("<dd", data, point_table_start + index * 16)
                for index in range(point_count)
            ]
            if any(not math.isfinite(value) for point in points for value in point):
                raise GenerationError(
                    f"SHP record {record_number} contains a non-finite coordinate"
                )
            records.append(
                [points[parts[i] : parts[i + 1]] for i in range(part_count)]
            )
        else:
            raise GenerationError(
                f"SHP record {record_number} has unsupported shape type {shape_type}"
            )
        cursor = content_end
        expected_record_number += 1
    if cursor != len(data):
        raise GenerationError("SHP has trailing partial data")
    return records


def _round_coordinate(value: float) -> int:
    return math.floor(value + 0.5) if value >= 0 else math.ceil(value - 0.5)


def _normalize_ring(
    raw_ring: list[tuple[float, float]], scale: int
) -> list[tuple[int, int]]:
    if len(raw_ring) < 4:
        return []
    source = raw_ring[:-1] if raw_ring[0] == raw_ring[-1] else raw_ring
    if len(source) < 3:
        return []

    unwrapped: list[tuple[float, float]] = [source[0]]
    previous_longitude = source[0][0]
    for longitude, latitude in source[1:]:
        while longitude - previous_longitude > 180:
            longitude -= WORLD_DEGREES
        while longitude - previous_longitude < -180:
            longitude += WORLD_DEGREES
        unwrapped.append((longitude, latitude))
        previous_longitude = longitude

    quantized: list[tuple[int, int]] = []
    for longitude, latitude in unwrapped:
        point = (
            _round_coordinate(longitude * scale),
            _round_coordinate(latitude * scale),
        )
        if not quantized or point != quantized[-1]:
            quantized.append(point)
    if len(quantized) > 1 and quantized[0] == quantized[-1]:
        quantized.pop()
    return quantized if len(quantized) >= 3 else []


def _signed_area2(ring: list[tuple[int, int]]) -> int:
    return sum(
        ring[index][0] * ring[(index + 1) % len(ring)][1]
        - ring[(index + 1) % len(ring)][0] * ring[index][1]
        for index in range(len(ring))
    )


def _bounds(ring: list[tuple[int, int]]) -> tuple[int, int, int, int]:
    xs = [point[0] for point in ring]
    ys = [point[1] for point in ring]
    return min(xs), min(ys), max(xs), max(ys)


def _point_location(ring: list[tuple[int, int]], x: int, y: int) -> int:
    """Return 0 outside, 1 inside, or 2 on the ring boundary."""
    inside = False
    previous_x, previous_y = ring[-1]
    for current_x, current_y in ring:
        cross = (current_x - previous_x) * (y - previous_y) - (
            current_y - previous_y
        ) * (x - previous_x)
        if (
            cross == 0
            and min(previous_x, current_x) <= x <= max(previous_x, current_x)
            and min(previous_y, current_y) <= y <= max(previous_y, current_y)
        ):
            return 2
        if (previous_y > y) != (current_y > y):
            denominator = current_y - previous_y
            left = (current_x - previous_x) * (y - previous_y)
            right = (x - previous_x) * denominator
            if (denominator > 0 and left > right) or (
                denominator < 0 and left < right
            ):
                inside = not inside
        previous_x, previous_y = current_x, current_y
    return 1 if inside else 0


def _shift_ring(
    ring: list[tuple[int, int]], target_center: int, world: int
) -> list[tuple[int, int]]:
    minimum_x, _, maximum_x, _ = _bounds(ring)
    center = (minimum_x + maximum_x) // 2
    shift_count = (target_center - center + world // 2) // world
    shift = shift_count * world
    return [(x + shift, y) for x, y in ring]


def _build_polygons(
    shape_records: list[list[list[tuple[float, float]]]],
    attributes: list[dict[str, str]],
    allowlist: set[str],
    code_field: str,
    scale: int,
) -> tuple[list[dict[str, object]], dict[str, int]]:
    if len(shape_records) != len(attributes):
        raise GenerationError("SHP and DBF record counts differ")
    world = WORLD_DEGREES * scale
    polygons: list[dict[str, object]] = []
    statistics = {
        "source_records": len(shape_records),
        "coded_source_records": 0,
        "uncoded_source_records": 0,
        "removed_degenerate_rings": 0,
        "removed_islands": 0,
    }

    for record_index, (raw_rings, values) in enumerate(
        zip(shape_records, attributes, strict=True)
    ):
        source_code = values.get(code_field, "")
        code = source_code if source_code in allowlist else None
        if code is None:
            statistics["uncoded_source_records"] += 1
        else:
            statistics["coded_source_records"] += 1

        outer_rings: list[tuple[int, list[tuple[int, int]]]] = []
        hole_rings: list[tuple[int, list[tuple[int, int]]]] = []
        for part_index, raw_ring in enumerate(raw_rings):
            ring = _normalize_ring(raw_ring, scale)
            if not ring or _signed_area2(ring) == 0:
                statistics["removed_degenerate_rings"] += 1
                continue
            if _signed_area2(ring) < 0:
                outer_rings.append((part_index, ring))
            else:
                hole_rings.append((part_index, ring))
        if raw_rings and not outer_rings:
            raise GenerationError(
                f"SHP record {record_index + 1} has no clockwise outer ring"
            )

        holes_by_outer: dict[int, list[tuple[int, list[tuple[int, int]]]]] = {
            part_index: [] for part_index, _ in outer_rings
        }
        for hole_index, hole in hole_rings:
            containing: list[
                tuple[int, int, list[tuple[int, int]]]
            ] = []
            hole_bounds = _bounds(hole)
            hole_center = (hole_bounds[0] + hole_bounds[2]) // 2
            for outer_index, outer in outer_rings:
                outer_bounds = _bounds(outer)
                outer_center = (outer_bounds[0] + outer_bounds[2]) // 2
                aligned_hole = _shift_ring(hole, outer_center, world)
                test_x, test_y = aligned_hole[0]
                if _point_location(outer, test_x, test_y) != 0:
                    containing.append(
                        (abs(_signed_area2(outer)), outer_index, aligned_hole)
                    )
            if not containing:
                raise GenerationError(
                    f"SHP record {record_index + 1} hole {hole_index} "
                    "is not contained by an outer ring"
                )
            _, parent_index, aligned = min(containing, key=lambda item: item[0])
            holes_by_outer[parent_index].append((hole_index, aligned))

        for outer_index, outer in outer_rings:
            rings = [outer] + [
                ring for _, ring in sorted(holes_by_outer[outer_index])
            ]
            outer_bounds = _bounds(outer)
            polygons.append(
                {
                    "code": code,
                    "source_record": record_index,
                    "rings": rings,
                    "bounds": outer_bounds,
                    "center_x": (outer_bounds[0] + outer_bounds[2]) // 2,
                }
            )
    return polygons, statistics


def _grid_index(
    polygons: list[dict[str, object]], scale: int, cell_degrees: int
) -> list[list[int]]:
    width = WORLD_DEGREES // cell_degrees
    height = 180 // cell_degrees
    world = WORLD_DEGREES * scale
    cell_size = cell_degrees * scale
    cells: list[list[int]] = [[] for _ in range(width * height)]
    for polygon_index, polygon in enumerate(polygons):
        minimum_x, minimum_y, maximum_x, maximum_y = polygon["bounds"]
        assert isinstance(minimum_x, int)
        assert isinstance(minimum_y, int)
        assert isinstance(maximum_x, int)
        assert isinstance(maximum_y, int)
        center_x = polygon["center_x"]
        assert isinstance(center_x, int)
        first_row = max(0, min(height - 1, (minimum_y + 90 * scale) // cell_size))
        last_row = max(0, min(height - 1, (maximum_y + 90 * scale) // cell_size))
        for row in range(first_row, last_row + 1):
            cell_minimum_y = -90 * scale + row * cell_size
            cell_maximum_y = cell_minimum_y + cell_size
            if cell_maximum_y < minimum_y or cell_minimum_y > maximum_y:
                continue
            for column in range(width):
                cell_minimum_x = -180 * scale + column * cell_size
                cell_maximum_x = cell_minimum_x + cell_size
                cell_center_x = (cell_minimum_x + cell_maximum_x) // 2
                shift_count = (center_x - cell_center_x + world // 2) // world
                shifted_minimum_x = cell_minimum_x + shift_count * world
                shifted_maximum_x = cell_maximum_x + shift_count * world
                if (
                    shifted_maximum_x >= minimum_x
                    and shifted_minimum_x <= maximum_x
                ):
                    cells[row * width + column].append(polygon_index)
    return cells


def _encode_varint(value: int) -> bytes:
    if value < 0:
        raise GenerationError("Cannot encode a negative unsigned varint")
    encoded = bytearray()
    while value >= 0x80:
        encoded.append((value & 0x7F) | 0x80)
        value >>= 7
    encoded.append(value)
    return bytes(encoded)


def _zigzag(value: int) -> int:
    return value * 2 if value >= 0 else -value * 2 - 1


def _pack_asset(
    polygons: list[dict[str, object]],
    cells: list[list[int]],
    config: dict[str, object],
    statistics: dict[str, int],
    source_bytes: bytes,
    allowlist_bytes: bytes,
) -> tuple[bytes, dict[str, object]]:
    scale = int(config["quantization_scale"])
    cell_degrees = int(config["grid_cell_degrees"])
    width = WORLD_DEGREES // cell_degrees
    height = 180 // cell_degrees
    format_version = int(config["format_version"])

    used_codes = sorted(
        {str(polygon["code"]) for polygon in polygons if polygon["code"] is not None}
    )
    code_indexes = {code: index for index, code in enumerate(used_codes)}
    code_section = "".join(used_codes).encode("ascii")

    point_section = bytearray()
    ring_records: list[tuple[int, int, int, int, int, int]] = []
    polygon_records: list[tuple[int, int, int, int, int, int, int, int]] = []
    point_count = 0
    for polygon in polygons:
        first_ring = len(ring_records)
        rings = polygon["rings"]
        assert isinstance(rings, list)
        for ring in rings:
            point_offset = len(point_section)
            previous_x = 0
            previous_y = 0
            for point_index, (x, y) in enumerate(ring):
                encoded_x = x if point_index == 0 else x - previous_x
                encoded_y = y if point_index == 0 else y - previous_y
                point_section.extend(_encode_varint(_zigzag(encoded_x)))
                point_section.extend(_encode_varint(_zigzag(encoded_y)))
                previous_x = x
                previous_y = y
            minimum_x, minimum_y, maximum_x, maximum_y = _bounds(ring)
            ring_records.append(
                (
                    point_offset,
                    len(ring),
                    minimum_x,
                    minimum_y,
                    maximum_x,
                    maximum_y,
                )
            )
            point_count += len(ring)
        minimum_x, minimum_y, maximum_x, maximum_y = polygon["bounds"]
        code = polygon["code"]
        polygon_records.append(
            (
                NULL_CODE_INDEX if code is None else code_indexes[str(code)],
                len(rings),
                first_ring,
                minimum_x,
                minimum_y,
                maximum_x,
                maximum_y,
                polygon["center_x"],
            )
        )

    polygon_section = b"".join(
        struct.pack("<HHIiiiii", *record) for record in polygon_records
    )
    ring_section = b"".join(
        struct.pack("<IIiiii", *record) for record in ring_records
    )

    cell_offsets = [0]
    cell_references: list[int] = []
    for cell in cells:
        if cell != sorted(set(cell)):
            raise GenerationError("Spatial-index cell is not sorted and unique")
        cell_references.extend(cell)
        cell_offsets.append(len(cell_references))
    cell_offset_section = struct.pack(
        f"<{len(cell_offsets)}I", *cell_offsets
    )
    cell_reference_section = (
        struct.pack(f"<{len(cell_references)}I", *cell_references)
        if cell_references
        else b""
    )

    geometry_payload = b"".join(
        (
            code_section,
            polygon_section,
            ring_section,
            bytes(point_section),
            cell_offset_section,
            cell_reference_section,
        )
    )
    natural_earth = config["natural_earth"]
    iso = config["iso_3166_1"]
    assert isinstance(natural_earth, dict)
    assert isinstance(iso, dict)
    metadata: dict[str, object] = {
        "binary_format_version": format_version,
        "codes": used_codes,
        "counts": {
            **statistics,
            "asset_codes": len(used_codes),
            "grid_cells": width * height,
            "index_references": len(cell_references),
            "points": point_count,
            "polygons": len(polygon_records),
            "rings": len(ring_records),
        },
        "generator_version": config["generator_version"],
        "geometry_payload_sha256": _sha256(geometry_payload),
        "grid": {
            "cell_degrees": cell_degrees,
            "height": height,
            "width": width,
        },
        "iso_3166_1": {
            "allowlist_count": iso["count"],
            "allowlist_sha256": _sha256(allowlist_bytes),
            "snapshot_date": iso["snapshot_date"],
            "source_url": iso["source_url"],
        },
        "natural_earth": {
            "code_field": natural_earth["code_field"],
            "dataset": natural_earth["dataset"],
            "sha256": _sha256(source_bytes),
            "source_url": natural_earth["source_url"],
            "version": natural_earth["version"],
        },
        "quantization": {
            "rounding": "nearest, ties away from zero",
            "scale": scale,
            "units_per_degree": scale,
        },
        "simplification": config["simplification"],
    }
    embedded_metadata = json.dumps(
        metadata, ensure_ascii=True, separators=(",", ":"), sort_keys=True
    ).encode("utf-8")

    codes_offset = HEADER_LENGTH
    polygons_offset = codes_offset + len(code_section)
    rings_offset = polygons_offset + len(polygon_section)
    points_offset = rings_offset + len(ring_section)
    cell_offsets_offset = points_offset + len(point_section)
    cell_references_offset = cell_offsets_offset + len(cell_offset_section)
    metadata_offset = cell_references_offset + len(cell_reference_section)
    total_length = metadata_offset + len(embedded_metadata)
    payload = geometry_payload + embedded_metadata
    checksum = zlib.crc32(payload) & 0xFFFFFFFF
    header = struct.pack(
        "<8sHHIIIHHHHIIIIIIIIIIII",
        MAGIC,
        format_version,
        HEADER_LENGTH,
        total_length,
        checksum,
        scale,
        width,
        height,
        len(used_codes),
        0,
        len(polygon_records),
        len(ring_records),
        point_count,
        len(cell_references),
        codes_offset,
        polygons_offset,
        rings_offset,
        points_offset,
        cell_offsets_offset,
        cell_references_offset,
        metadata_offset,
        len(embedded_metadata),
    )
    if len(header) != HEADER_LENGTH:
        raise GenerationError(f"Internal header length is {len(header)}, expected 80")
    asset = header + payload
    sidecar = dict(metadata)
    sidecar["asset_bytes"] = len(asset)
    sidecar["asset_sha256"] = _sha256(asset)
    return asset, sidecar


def _generate(
    config: dict[str, object], source_path: Path | None
) -> tuple[bytes, dict[str, object]]:
    allowlist, allowlist_bytes = _load_allowlist(config)
    source_bytes = _load_source(config, source_path)
    natural_earth = config["natural_earth"]
    assert isinstance(natural_earth, dict)
    basename = "ne_10m_admin_0_map_units"
    with zipfile.ZipFile(Path(source_path) if source_path else _resolve(str(natural_earth["archive"]))) as archive:
        required = {
            f"{basename}.dbf",
            f"{basename}.shp",
            f"{basename}.VERSION.txt",
        }
        if not required.issubset(archive.namelist()):
            missing = sorted(required.difference(archive.namelist()))
            raise GenerationError(f"Natural Earth archive is missing: {missing}")
        version = archive.read(f"{basename}.VERSION.txt").decode("ascii").strip()
        if version != natural_earth["version"]:
            raise GenerationError(
                f"Natural Earth version mismatch: expected {natural_earth['version']}, "
                f"got {version}"
            )
        attributes = _decode_dbf(archive.read(f"{basename}.dbf"))
        shape_records = _decode_shp(archive.read(f"{basename}.shp"))

    scale = int(config["quantization_scale"])
    polygons, statistics = _build_polygons(
        shape_records,
        attributes,
        set(allowlist),
        str(natural_earth["code_field"]),
        scale,
    )
    cells = _grid_index(
        polygons, scale, int(config["grid_cell_degrees"])
    )
    return _pack_asset(
        polygons,
        cells,
        config,
        statistics,
        source_bytes,
        allowlist_bytes,
    )


def _metadata_bytes(metadata: dict[str, object]) -> bytes:
    return (
        json.dumps(metadata, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    ).encode("utf-8")


def _write_atomic(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        dir=path.parent, prefix=path.name, delete=False
    ) as temporary:
        temporary.write(data)
        temporary.flush()
        os.fsync(temporary.fileno())
        temporary_path = Path(temporary.name)
    os.replace(temporary_path, path)


def _print_difference(
    previous: dict[str, object] | None, current: dict[str, object]
) -> None:
    if previous is None:
        return
    previous_codes = set(previous.get("codes", []))
    current_codes = set(current.get("codes", []))
    previous_counts = previous.get("counts", {})
    current_counts = current["counts"]
    assert isinstance(previous_counts, dict)
    assert isinstance(current_counts, dict)
    print("Data difference from existing asset:")
    print(f"  codes added: {sorted(current_codes - previous_codes)}")
    print(f"  codes removed: {sorted(previous_codes - current_codes)}")
    for key in ("polygons", "rings", "points", "removed_islands"):
        old = int(previous_counts.get(key, 0))
        new = int(current_counts[key])
        print(f"  {key}: {old} -> {new} ({new - old:+d})")
    old_size = int(previous.get("asset_bytes", 0))
    new_size = int(current["asset_bytes"])
    print(f"  asset_bytes: {old_size} -> {new_size} ({new_size - old_size:+d})")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, help="Pinned source archive override")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--metadata", type=Path, default=DEFAULT_METADATA)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Verify committed outputs without modifying them",
    )
    arguments = parser.parse_args()
    config = _read_config()
    source_path = arguments.source.resolve() if arguments.source else None
    asset, metadata = _generate(config, source_path)
    metadata_data = _metadata_bytes(metadata)

    if arguments.check:
        failures = []
        if not arguments.output.exists() or arguments.output.read_bytes() != asset:
            failures.append(str(arguments.output))
        if (
            not arguments.metadata.exists()
            or arguments.metadata.read_bytes() != metadata_data
        ):
            failures.append(str(arguments.metadata))
        if failures:
            raise GenerationError(
                "Generated output differs from committed files: " + ", ".join(failures)
            )
        print(
            f"Verified deterministic asset: {len(asset)} bytes, "
            f"SHA-256 {metadata['asset_sha256']}"
        )
        return 0

    previous = None
    if arguments.metadata.exists():
        try:
            previous = json.loads(arguments.metadata.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            previous = None
    _print_difference(previous, metadata)
    _write_atomic(arguments.output, asset)
    _write_atomic(arguments.metadata, metadata_data)
    print(
        f"Wrote {arguments.output}: {len(asset)} bytes, "
        f"SHA-256 {metadata['asset_sha256']}"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (GenerationError, OSError, UnicodeError, zipfile.BadZipFile) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error
