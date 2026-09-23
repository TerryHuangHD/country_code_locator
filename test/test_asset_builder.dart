import 'dart:convert';
import 'dart:typed_data';

import 'package:country_code_locator/src/crc32.dart';
import 'package:country_code_locator/src/official_codes.dart';

const int _scale = 1000;
const int _gridWidth = 180;
const int _gridHeight = 90;
const int _headerLength = 80;
const int _world = 360 * _scale;
const int _cellSize = 2 * _scale;

final class TestPoint {
  const TestPoint(this.longitude, this.latitude);

  final int longitude;
  final int latitude;
}

final class TestPolygon {
  const TestPolygon({required this.code, required this.rings});

  final String? code;
  final List<List<TestPoint>> rings;
}

Uint8List buildTestAsset(List<TestPolygon> inputPolygons) {
  final codes = inputPolygons
      .map((polygon) => polygon.code)
      .whereType<String>()
      .toSet()
      .toList()
    ..sort();
  final codeIndexes = <String, int>{
    for (var index = 0; index < codes.length; index += 1) codes[index]: index,
  };

  final polygons = <_EncodedPolygon>[];
  final rings = <_EncodedRing>[];
  final points = BytesBuilder(copy: false);
  var pointCount = 0;
  for (final polygon in inputPolygons) {
    if (polygon.rings.isEmpty) {
      throw ArgumentError('A test polygon requires an outer ring');
    }
    final firstRing = rings.length;
    for (final sourceRing in polygon.rings) {
      if (sourceRing.length < 3) {
        throw ArgumentError('A test ring requires at least three points');
      }
      final quantized = sourceRing
          .map(
            (point) => TestPoint(
              point.longitude * _scale,
              point.latitude * _scale,
            ),
          )
          .toList(growable: false);
      final pointOffset = points.length;
      var previousX = 0;
      var previousY = 0;
      for (var index = 0; index < quantized.length; index += 1) {
        final point = quantized[index];
        final x = index == 0 ? point.longitude : point.longitude - previousX;
        final y = index == 0 ? point.latitude : point.latitude - previousY;
        points.add(_varint(_zigzag(x)));
        points.add(_varint(_zigzag(y)));
        previousX = point.longitude;
        previousY = point.latitude;
      }
      final bounds = _bounds(quantized);
      rings.add(
        _EncodedRing(
          pointOffset: pointOffset,
          pointCount: quantized.length,
          bounds: bounds,
        ),
      );
      pointCount += quantized.length;
    }
    final outerBounds = rings[firstRing].bounds;
    polygons.add(
      _EncodedPolygon(
        codeIndex: polygon.code == null ? 0xffff : codeIndexes[polygon.code]!,
        firstRing: firstRing,
        ringCount: polygon.rings.length,
        bounds: outerBounds,
        centerX: (outerBounds.minimumX + outerBounds.maximumX) ~/ 2,
      ),
    );
  }

  final alpha3Codes = <String>[
    for (final code in codes) officialAlpha3For(code)!,
  ];
  final codeSection = ascii.encode(
    [
      for (var index = 0; index < codes.length; index += 1)
        '${codes[index]}${alpha3Codes[index]}'
    ].join(),
  );
  final polygonSection = BytesBuilder(copy: false);
  for (final polygon in polygons) {
    final record = ByteData(28)
      ..setUint16(0, polygon.codeIndex, Endian.little)
      ..setUint16(2, polygon.ringCount, Endian.little)
      ..setUint32(4, polygon.firstRing, Endian.little)
      ..setInt32(8, polygon.bounds.minimumX, Endian.little)
      ..setInt32(12, polygon.bounds.minimumY, Endian.little)
      ..setInt32(16, polygon.bounds.maximumX, Endian.little)
      ..setInt32(20, polygon.bounds.maximumY, Endian.little)
      ..setInt32(24, polygon.centerX, Endian.little);
    polygonSection.add(record.buffer.asUint8List());
  }

  final ringSection = BytesBuilder(copy: false);
  for (final ring in rings) {
    final record = ByteData(24)
      ..setUint32(0, ring.pointOffset, Endian.little)
      ..setUint32(4, ring.pointCount, Endian.little)
      ..setInt32(8, ring.bounds.minimumX, Endian.little)
      ..setInt32(12, ring.bounds.minimumY, Endian.little)
      ..setInt32(16, ring.bounds.maximumX, Endian.little)
      ..setInt32(20, ring.bounds.maximumY, Endian.little);
    ringSection.add(record.buffer.asUint8List());
  }

  final cells = List<List<int>>.generate(
    _gridWidth * _gridHeight,
    (_) => <int>[],
  );
  for (var polygonIndex = 0;
      polygonIndex < polygons.length;
      polygonIndex += 1) {
    final polygon = polygons[polygonIndex];
    final firstRow = ((polygon.bounds.minimumY + 90 * _scale) ~/ _cellSize)
        .clamp(0, _gridHeight - 1);
    final lastRow = ((polygon.bounds.maximumY + 90 * _scale) ~/ _cellSize)
        .clamp(0, _gridHeight - 1);
    for (var row = firstRow; row <= lastRow; row += 1) {
      final cellMinimumY = -90 * _scale + row * _cellSize;
      final cellMaximumY = cellMinimumY + _cellSize;
      if (cellMaximumY < polygon.bounds.minimumY ||
          cellMinimumY > polygon.bounds.maximumY) {
        continue;
      }
      for (var column = 0; column < _gridWidth; column += 1) {
        final cellMinimumX = -180 * _scale + column * _cellSize;
        final cellMaximumX = cellMinimumX + _cellSize;
        final cellCenterX = (cellMinimumX + cellMaximumX) ~/ 2;
        final shift = _nearestQuotient(polygon.centerX - cellCenterX, _world);
        final shiftedMinimumX = cellMinimumX + shift * _world;
        final shiftedMaximumX = cellMaximumX + shift * _world;
        if (shiftedMaximumX >= polygon.bounds.minimumX &&
            shiftedMinimumX <= polygon.bounds.maximumX) {
          cells[row * _gridWidth + column].add(polygonIndex);
        }
      }
    }
  }

  final cellOffsets = ByteData((_gridWidth * _gridHeight + 1) * 4);
  final references = <int>[];
  for (var cell = 0; cell < cells.length; cell += 1) {
    cellOffsets.setUint32(cell * 4, references.length, Endian.little);
    references.addAll(cells[cell]);
  }
  cellOffsets.setUint32(cells.length * 4, references.length, Endian.little);
  final referenceSection = ByteData(references.length * 4);
  for (var index = 0; index < references.length; index += 1) {
    referenceSection.setUint32(index * 4, references[index], Endian.little);
  }

  final metadata = utf8.encode(
    jsonEncode(<String, Object?>{
      'binary_format_version': 2,
      'codes': codes,
      'alpha3_codes': alpha3Codes,
      'counts': <String, Object?>{
        'asset_codes': codes.length,
        'grid_cells': _gridWidth * _gridHeight,
        'index_references': references.length,
        'points': pointCount,
        'polygons': polygons.length,
        'rings': rings.length,
      },
      'quantization': <String, Object?>{'scale': _scale},
    }),
  );

  final polygonBytes = polygonSection.takeBytes();
  final ringBytes = ringSection.takeBytes();
  final pointBytes = points.takeBytes();
  final codesOffset = _headerLength;
  final polygonsOffset = codesOffset + codeSection.length;
  final ringsOffset = polygonsOffset + polygonBytes.length;
  final pointsOffset = ringsOffset + ringBytes.length;
  final cellOffsetsOffset = pointsOffset + pointBytes.length;
  final cellReferencesOffset = cellOffsetsOffset + cellOffsets.lengthInBytes;
  final metadataOffset = cellReferencesOffset + referenceSection.lengthInBytes;
  final totalLength = metadataOffset + metadata.length;

  final payload = BytesBuilder(copy: false)
    ..add(codeSection)
    ..add(polygonBytes)
    ..add(ringBytes)
    ..add(pointBytes)
    ..add(cellOffsets.buffer.asUint8List())
    ..add(referenceSection.buffer.asUint8List())
    ..add(metadata);
  final payloadBytes = payload.takeBytes();
  final checksum = crc32(payloadBytes, 0, payloadBytes.length);
  final header = ByteData(_headerLength);
  header.buffer.asUint8List().setAll(0, ascii.encode('CCLOCATR'));
  header
    ..setUint16(8, 2, Endian.little)
    ..setUint16(10, _headerLength, Endian.little)
    ..setUint32(12, totalLength, Endian.little)
    ..setUint32(16, checksum, Endian.little)
    ..setUint32(20, _scale, Endian.little)
    ..setUint16(24, _gridWidth, Endian.little)
    ..setUint16(26, _gridHeight, Endian.little)
    ..setUint16(28, codes.length, Endian.little)
    ..setUint16(30, 0, Endian.little)
    ..setUint32(32, polygons.length, Endian.little)
    ..setUint32(36, rings.length, Endian.little)
    ..setUint32(40, pointCount, Endian.little)
    ..setUint32(44, references.length, Endian.little)
    ..setUint32(48, codesOffset, Endian.little)
    ..setUint32(52, polygonsOffset, Endian.little)
    ..setUint32(56, ringsOffset, Endian.little)
    ..setUint32(60, pointsOffset, Endian.little)
    ..setUint32(64, cellOffsetsOffset, Endian.little)
    ..setUint32(68, cellReferencesOffset, Endian.little)
    ..setUint32(72, metadataOffset, Endian.little)
    ..setUint32(76, metadata.length, Endian.little);

  return (BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(payloadBytes))
      .takeBytes();
}

_Bounds _bounds(List<TestPoint> points) {
  var minimumX = points.first.longitude;
  var minimumY = points.first.latitude;
  var maximumX = minimumX;
  var maximumY = minimumY;
  for (final point in points.skip(1)) {
    minimumX = point.longitude < minimumX ? point.longitude : minimumX;
    minimumY = point.latitude < minimumY ? point.latitude : minimumY;
    maximumX = point.longitude > maximumX ? point.longitude : maximumX;
    maximumY = point.latitude > maximumY ? point.latitude : maximumY;
  }
  return _Bounds(
    minimumX: minimumX,
    minimumY: minimumY,
    maximumX: maximumX,
    maximumY: maximumY,
  );
}

Uint8List _varint(int value) {
  final result = <int>[];
  while (value >= 0x80) {
    result.add((value & 0x7f) | 0x80);
    value >>= 7;
  }
  result.add(value);
  return Uint8List.fromList(result);
}

int _zigzag(int value) => value >= 0 ? value * 2 : -value * 2 - 1;

int _nearestQuotient(int numerator, int denominator) => numerator >= 0
    ? (numerator + denominator ~/ 2) ~/ denominator
    : -((-numerator + denominator ~/ 2) ~/ denominator);

final class _EncodedPolygon {
  const _EncodedPolygon({
    required this.codeIndex,
    required this.firstRing,
    required this.ringCount,
    required this.bounds,
    required this.centerX,
  });

  final int codeIndex;
  final int firstRing;
  final int ringCount;
  final _Bounds bounds;
  final int centerX;
}

final class _EncodedRing {
  const _EncodedRing({
    required this.pointOffset,
    required this.pointCount,
    required this.bounds,
  });

  final int pointOffset;
  final int pointCount;
  final _Bounds bounds;
}

final class _Bounds {
  const _Bounds({
    required this.minimumX,
    required this.minimumY,
    required this.maximumX,
    required this.maximumY,
  });

  final int minimumX;
  final int minimumY;
  final int maximumX;
  final int maximumY;
}
