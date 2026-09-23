import 'dart:convert';
import 'dart:typed_data';

import 'package:country_code_locator/src/country_code_data_exception.dart';
import 'package:country_code_locator/src/crc32.dart';
import 'package:country_code_locator/src/official_codes.dart';

const int _headerLength = 80;
const int _polygonRecordLength = 28;
const int _ringRecordLength = 24;
const int _nullCodeIndex = 0xffff;
const int _supportedFormatVersion = 1;
const List<int> _magic = <int>[67, 67, 76, 79, 67, 65, 84, 82];

final class CountryData {
  CountryData._({
    required this.codes,
    required List<_Polygon> polygons,
    required List<_Ring> rings,
    required this.pointLongitudes,
    required this.pointLatitudes,
    required this.cellOffsets,
    required this.cellReferences,
    required this.scale,
    required this.gridWidth,
    required this.gridHeight,
  })  : _polygons = polygons,
        _rings = rings;

  factory CountryData.parse(Uint8List bytes) =>
      _CountryDataParser(bytes).parse();

  final List<String> codes;
  final List<_Polygon> _polygons;
  final List<_Ring> _rings;
  final Int32List pointLongitudes;
  final Int32List pointLatitudes;
  final Uint32List cellOffsets;
  final Uint32List cellReferences;
  final int scale;
  final int gridWidth;
  final int gridHeight;

  String? lookup({required double latitude, required double longitude}) {
    if (!latitude.isFinite || latitude < -90 || latitude > 90) {
      throw ArgumentError.value(
        latitude,
        'latitude',
        'must be finite and between -90 and 90',
      );
    }
    if (!longitude.isFinite || longitude < -180 || longitude > 180) {
      throw ArgumentError.value(
        longitude,
        'longitude',
        'must be finite and between -180 and 180',
      );
    }

    final normalizedLongitude = longitude == 180 ? -180.0 : longitude;
    final queryX = (normalizedLongitude * scale).round();
    final queryY = (latitude * scale).round();
    final world = 360 * scale;
    final cellWidth = world ~/ gridWidth;
    final cellHeight = 180 * scale ~/ gridHeight;
    var column = (queryX + 180 * scale) ~/ cellWidth;
    var row = (queryY + 90 * scale) ~/ cellHeight;
    column = column.clamp(0, gridWidth - 1);
    row = row.clamp(0, gridHeight - 1);
    final cell = row * gridWidth + column;

    String? matchedCode;
    var ambiguous = false;
    var uncodedHit = false;
    for (var reference = cellOffsets[cell];
        reference < cellOffsets[cell + 1];
        reference += 1) {
      final polygon = _polygons[cellReferences[reference]];
      final projectedX =
          queryX + _nearestQuotient(polygon.centerX - queryX, world) * world;
      if (!_insideBounds(
        projectedX,
        queryY,
        polygon.minimumX,
        polygon.minimumY,
        polygon.maximumX,
        polygon.maximumY,
      )) {
        continue;
      }
      if (!_polygonContains(polygon, projectedX, queryY)) {
        continue;
      }
      if (polygon.codeIndex < 0) {
        uncodedHit = true;
        continue;
      }
      final code = codes[polygon.codeIndex];
      if (matchedCode == null) {
        matchedCode = code;
      } else if (matchedCode != code) {
        ambiguous = true;
      }
    }
    return ambiguous || uncodedHit ? null : matchedCode;
  }

  bool _polygonContains(_Polygon polygon, int x, int y) {
    final outer = _rings[polygon.firstRing];
    final outerLocation = _ringLocation(outer, x, y);
    if (outerLocation == _PointLocation.outside) {
      return false;
    }
    if (outerLocation == _PointLocation.boundary) {
      return true;
    }
    final endRing = polygon.firstRing + polygon.ringCount;
    for (var ringIndex = polygon.firstRing + 1;
        ringIndex < endRing;
        ringIndex += 1) {
      final hole = _rings[ringIndex];
      if (!_insideBounds(
        x,
        y,
        hole.minimumX,
        hole.minimumY,
        hole.maximumX,
        hole.maximumY,
      )) {
        continue;
      }
      final holeLocation = _ringLocation(hole, x, y);
      if (holeLocation == _PointLocation.boundary) {
        return true;
      }
      if (holeLocation == _PointLocation.inside) {
        return false;
      }
    }
    return true;
  }

  _PointLocation _ringLocation(_Ring ring, int x, int y) {
    if (!_insideBounds(
      x,
      y,
      ring.minimumX,
      ring.minimumY,
      ring.maximumX,
      ring.maximumY,
    )) {
      return _PointLocation.outside;
    }
    var inside = false;
    final endPoint = ring.firstPoint + ring.pointCount;
    var previousIndex = endPoint - 1;
    for (var currentIndex = ring.firstPoint;
        currentIndex < endPoint;
        currentIndex += 1) {
      final previousX = pointLongitudes[previousIndex];
      final previousY = pointLatitudes[previousIndex];
      final currentX = pointLongitudes[currentIndex];
      final currentY = pointLatitudes[currentIndex];
      final cross = (currentX - previousX) * (y - previousY) -
          (currentY - previousY) * (x - previousX);
      if (cross == 0 &&
          x >= _minimum(previousX, currentX) &&
          x <= _maximum(previousX, currentX) &&
          y >= _minimum(previousY, currentY) &&
          y <= _maximum(previousY, currentY)) {
        return _PointLocation.boundary;
      }
      if ((previousY > y) != (currentY > y)) {
        final denominator = currentY - previousY;
        final left = (currentX - previousX) * (y - previousY);
        final right = (x - previousX) * denominator;
        if ((denominator > 0 && left > right) ||
            (denominator < 0 && left < right)) {
          inside = !inside;
        }
      }
      previousIndex = currentIndex;
    }
    return inside ? _PointLocation.inside : _PointLocation.outside;
  }
}

final class _CountryDataParser {
  _CountryDataParser(this.bytes) : data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData data;

  CountryData parse() {
    if (bytes.length < _headerLength) {
      _invalid('Country boundary data is shorter than its header');
    }
    for (var index = 0; index < _magic.length; index += 1) {
      if (bytes[index] != _magic[index]) {
        _invalid('Country boundary data has an invalid magic number', index);
      }
    }
    final formatVersion = _uint16(8);
    if (formatVersion != _supportedFormatVersion) {
      _invalid('Unsupported country boundary format version $formatVersion', 8);
    }
    if (_uint16(10) != _headerLength) {
      _invalid('Country boundary header length is invalid', 10);
    }
    final totalLength = _uint32(12);
    if (totalLength != bytes.length) {
      _invalid(
        'Country boundary data length is $totalLength, but ${bytes.length} bytes were provided',
        12,
      );
    }
    final expectedChecksum = _uint32(16);
    final actualChecksum = crc32(bytes, _headerLength, bytes.length);
    if (actualChecksum != expectedChecksum) {
      _invalid('Country boundary data checksum does not match', 16);
    }

    final scale = _uint32(20);
    final gridWidth = _uint16(24);
    final gridHeight = _uint16(26);
    final codeCount = _uint16(28);
    if (_uint16(30) != 0) {
      _invalid('Country boundary reserved header field is non-zero', 30);
    }
    final polygonCount = _uint32(32);
    final ringCount = _uint32(36);
    final pointCount = _uint32(40);
    final referenceCount = _uint32(44);
    final codesOffset = _uint32(48);
    final polygonsOffset = _uint32(52);
    final ringsOffset = _uint32(56);
    final pointsOffset = _uint32(60);
    final cellOffsetsOffset = _uint32(64);
    final cellReferencesOffset = _uint32(68);
    final metadataOffset = _uint32(72);
    final metadataLength = _uint32(76);

    if (scale == 0 || scale > 10000000) {
      _invalid('Country boundary quantization scale is invalid', 20);
    }
    if (gridWidth == 0 ||
        gridHeight == 0 ||
        360 % gridWidth != 0 ||
        180 % gridHeight != 0) {
      _invalid('Country boundary grid dimensions are invalid', 24);
    }
    if (codeCount == 0 ||
        polygonCount == 0 ||
        ringCount == 0 ||
        pointCount == 0) {
      _invalid('Country boundary data contains an empty required section', 28);
    }

    final cellCount = gridWidth * gridHeight;
    final expectedPolygonsOffset = _headerLength + codeCount * 2;
    final expectedRingsOffset =
        expectedPolygonsOffset + polygonCount * _polygonRecordLength;
    final expectedPointsOffset =
        expectedRingsOffset + ringCount * _ringRecordLength;
    final expectedCellReferencesOffset =
        cellOffsetsOffset + (cellCount + 1) * 4;
    final expectedMetadataOffset =
        expectedCellReferencesOffset + referenceCount * 4;
    final expectedTotalLength = expectedMetadataOffset + metadataLength;
    if (codesOffset != _headerLength ||
        polygonsOffset != expectedPolygonsOffset ||
        ringsOffset != expectedRingsOffset ||
        pointsOffset != expectedPointsOffset ||
        cellOffsetsOffset < pointsOffset ||
        cellReferencesOffset != expectedCellReferencesOffset ||
        metadataOffset != expectedMetadataOffset ||
        totalLength != expectedTotalLength) {
      _invalid('Country boundary section offsets are inconsistent');
    }

    final codes = _parseCodes(codesOffset, codeCount);
    final rawPolygons = _parsePolygons(
      polygonsOffset,
      polygonCount,
      codeCount,
      ringCount,
      scale,
    );
    final rawRings = _parseRingRecords(
      ringsOffset,
      ringCount,
      pointsOffset,
      cellOffsetsOffset,
      scale,
    );
    final decodedPoints = _parsePoints(
      rawRings,
      pointsOffset,
      cellOffsetsOffset,
      pointCount,
      scale,
    );
    final rings = decodedPoints.rings;
    final polygons = _validatePolygons(rawPolygons, rings, ringCount);
    final index = _parseIndex(
      cellOffsetsOffset,
      cellReferencesOffset,
      cellCount,
      referenceCount,
      polygonCount,
    );
    _validateIndexReferences(
      index.offsets,
      index.references,
      polygons,
      gridWidth,
      gridHeight,
      scale,
    );
    _validateMetadata(
      metadataOffset,
      metadataLength,
      formatVersion: formatVersion,
      scale: scale,
      gridCells: cellCount,
      codes: codes,
      polygonCount: polygonCount,
      ringCount: ringCount,
      pointCount: pointCount,
      referenceCount: referenceCount,
    );

    return CountryData._(
      codes: List<String>.unmodifiable(codes),
      polygons: List<_Polygon>.unmodifiable(polygons),
      rings: List<_Ring>.unmodifiable(rings),
      pointLongitudes: decodedPoints.longitudes,
      pointLatitudes: decodedPoints.latitudes,
      cellOffsets: index.offsets,
      cellReferences: index.references,
      scale: scale,
      gridWidth: gridWidth,
      gridHeight: gridHeight,
    );
  }

  List<String> _parseCodes(int offset, int count) {
    final codes = <String>[];
    String? previous;
    for (var index = 0; index < count; index += 1) {
      final first = bytes[offset + index * 2];
      final second = bytes[offset + index * 2 + 1];
      if (first < 65 || first > 90 || second < 65 || second > 90) {
        _invalid('Country boundary code table contains non-uppercase ASCII',
            offset + index * 2);
      }
      final code = String.fromCharCodes(<int>[first, second]);
      if (!isOfficialAlpha2(code)) {
        _invalid(
            'Country boundary code table contains non-official code $code');
      }
      if (previous != null && previous.compareTo(code) >= 0) {
        _invalid('Country boundary code table is not strictly sorted');
      }
      codes.add(code);
      previous = code;
    }
    return codes;
  }

  List<_RawPolygon> _parsePolygons(
    int offset,
    int count,
    int codeCount,
    int ringCount,
    int scale,
  ) {
    final polygons = <_RawPolygon>[];
    final world = 360 * scale;
    var expectedFirstRing = 0;
    for (var index = 0; index < count; index += 1) {
      final recordOffset = offset + index * _polygonRecordLength;
      final storedCodeIndex = _uint16(recordOffset);
      if (storedCodeIndex != _nullCodeIndex && storedCodeIndex >= codeCount) {
        _invalid('Polygon $index has an invalid code index', recordOffset);
      }
      final polygonRingCount = _uint16(recordOffset + 2);
      final firstRing = _uint32(recordOffset + 4);
      final minimumX = _int32(recordOffset + 8);
      final minimumY = _int32(recordOffset + 12);
      final maximumX = _int32(recordOffset + 16);
      final maximumY = _int32(recordOffset + 20);
      final centerX = _int32(recordOffset + 24);
      if (polygonRingCount == 0 ||
          firstRing != expectedFirstRing ||
          firstRing + polygonRingCount > ringCount) {
        _invalid(
            'Polygon $index has invalid ring references', recordOffset + 2);
      }
      _validateBounds(
        'Polygon $index',
        minimumX,
        minimumY,
        maximumX,
        maximumY,
        scale,
      );
      if (maximumX - minimumX > world ||
          centerX < minimumX ||
          centerX > maximumX) {
        _invalid('Polygon $index has invalid longitude projection data',
            recordOffset + 8);
      }
      polygons.add(
        _RawPolygon(
          codeIndex: storedCodeIndex == _nullCodeIndex ? -1 : storedCodeIndex,
          firstRing: firstRing,
          ringCount: polygonRingCount,
          minimumX: minimumX,
          minimumY: minimumY,
          maximumX: maximumX,
          maximumY: maximumY,
          centerX: centerX,
        ),
      );
      expectedFirstRing += polygonRingCount;
    }
    if (expectedFirstRing != ringCount) {
      _invalid('Polygon table does not reference every ring exactly once');
    }
    return polygons;
  }

  List<_RawRing> _parseRingRecords(
    int offset,
    int count,
    int pointsOffset,
    int pointSectionEnd,
    int scale,
  ) {
    final records = <_RawRing>[];
    var expectedPointOffset = 0;
    for (var index = 0; index < count; index += 1) {
      final recordOffset = offset + index * _ringRecordLength;
      final pointOffset = _uint32(recordOffset);
      final ringPointCount = _uint32(recordOffset + 4);
      final minimumX = _int32(recordOffset + 8);
      final minimumY = _int32(recordOffset + 12);
      final maximumX = _int32(recordOffset + 16);
      final maximumY = _int32(recordOffset + 20);
      if (pointOffset != expectedPointOffset && index == 0) {
        _invalid('First ring does not start at the point stream', recordOffset);
      }
      if (pointOffset < expectedPointOffset ||
          pointsOffset + pointOffset >= pointSectionEnd ||
          ringPointCount < 3) {
        _invalid('Ring $index has invalid point data', recordOffset);
      }
      _validateBounds(
        'Ring $index',
        minimumX,
        minimumY,
        maximumX,
        maximumY,
        scale,
      );
      records.add(
        _RawRing(
          pointOffset: pointOffset,
          pointCount: ringPointCount,
          minimumX: minimumX,
          minimumY: minimumY,
          maximumX: maximumX,
          maximumY: maximumY,
        ),
      );
      expectedPointOffset = pointOffset;
    }
    return records;
  }

  _DecodedPoints _parsePoints(
    List<_RawRing> rawRings,
    int pointsOffset,
    int pointSectionEnd,
    int expectedPointCount,
    int scale,
  ) {
    final longitudes = Int32List(expectedPointCount);
    final latitudes = Int32List(expectedPointCount);
    final rings = <_Ring>[];
    final cursor = _VarintCursor(bytes, pointsOffset, pointSectionEnd);
    final maximumAbsoluteX = 540 * scale;
    final maximumAbsoluteY = 90 * scale;
    var decodedPointCount = 0;
    for (var ringIndex = 0; ringIndex < rawRings.length; ringIndex += 1) {
      final raw = rawRings[ringIndex];
      if (cursor.offset - pointsOffset != raw.pointOffset) {
        _invalid(
            'Ring $ringIndex point offset is not contiguous', cursor.offset);
      }
      if (decodedPointCount + raw.pointCount > expectedPointCount) {
        _invalid('Decoded point count exceeds the header count', cursor.offset);
      }
      final firstPoint = decodedPointCount;
      var x = 0;
      var y = 0;
      var actualMinimumX = 0x7fffffff;
      var actualMinimumY = 0x7fffffff;
      var actualMaximumX = -0x80000000;
      var actualMaximumY = -0x80000000;
      for (var pointIndex = 0; pointIndex < raw.pointCount; pointIndex += 1) {
        final encodedX = cursor.read();
        final encodedY = cursor.read();
        final valueX = _unzigzag(encodedX);
        final valueY = _unzigzag(encodedY);
        if (pointIndex == 0) {
          x = valueX;
          y = valueY;
        } else {
          x += valueX;
          y += valueY;
        }
        if (x < -maximumAbsoluteX ||
            x > maximumAbsoluteX ||
            y < -maximumAbsoluteY ||
            y > maximumAbsoluteY) {
          _invalid('Ring $ringIndex contains an out-of-range coordinate',
              cursor.offset);
        }
        if (pointIndex > 0 &&
            longitudes[decodedPointCount - 1] == x &&
            latitudes[decodedPointCount - 1] == y) {
          _invalid('Ring $ringIndex contains consecutive duplicate points',
              cursor.offset);
        }
        longitudes[decodedPointCount] = x;
        latitudes[decodedPointCount] = y;
        decodedPointCount += 1;
        actualMinimumX = _minimum(actualMinimumX, x);
        actualMinimumY = _minimum(actualMinimumY, y);
        actualMaximumX = _maximum(actualMaximumX, x);
        actualMaximumY = _maximum(actualMaximumY, y);
      }
      if (longitudes[firstPoint] == longitudes[decodedPointCount - 1] &&
          latitudes[firstPoint] == latitudes[decodedPointCount - 1]) {
        _invalid('Ring $ringIndex repeats its implicit closing point');
      }
      if (actualMinimumX != raw.minimumX ||
          actualMinimumY != raw.minimumY ||
          actualMaximumX != raw.maximumX ||
          actualMaximumY != raw.maximumY) {
        _invalid('Ring $ringIndex bounds do not match its decoded points');
      }
      rings.add(
        _Ring(
          firstPoint: firstPoint,
          pointCount: raw.pointCount,
          minimumX: raw.minimumX,
          minimumY: raw.minimumY,
          maximumX: raw.maximumX,
          maximumY: raw.maximumY,
        ),
      );
    }
    if (decodedPointCount != expectedPointCount ||
        cursor.offset != pointSectionEnd) {
      _invalid('Point stream length or decoded point count is inconsistent',
          cursor.offset);
    }
    return _DecodedPoints(
      longitudes: longitudes,
      latitudes: latitudes,
      rings: rings,
    );
  }

  List<_Polygon> _validatePolygons(
    List<_RawPolygon> rawPolygons,
    List<_Ring> rings,
    int expectedRingCount,
  ) {
    final polygons = <_Polygon>[];
    var referencedRings = 0;
    for (var index = 0; index < rawPolygons.length; index += 1) {
      final raw = rawPolygons[index];
      final outer = rings[raw.firstRing];
      if (outer.minimumX != raw.minimumX ||
          outer.minimumY != raw.minimumY ||
          outer.maximumX != raw.maximumX ||
          outer.maximumY != raw.maximumY) {
        _invalid('Polygon $index bounds do not match its outer ring');
      }
      for (var ringIndex = raw.firstRing + 1;
          ringIndex < raw.firstRing + raw.ringCount;
          ringIndex += 1) {
        final hole = rings[ringIndex];
        if (hole.minimumX < raw.minimumX ||
            hole.minimumY < raw.minimumY ||
            hole.maximumX > raw.maximumX ||
            hole.maximumY > raw.maximumY) {
          _invalid('Polygon $index has a hole outside its outer bounds');
        }
      }
      polygons.add(
        _Polygon(
          codeIndex: raw.codeIndex,
          firstRing: raw.firstRing,
          ringCount: raw.ringCount,
          minimumX: raw.minimumX,
          minimumY: raw.minimumY,
          maximumX: raw.maximumX,
          maximumY: raw.maximumY,
          centerX: raw.centerX,
        ),
      );
      referencedRings += raw.ringCount;
    }
    if (referencedRings != expectedRingCount) {
      _invalid('Parsed polygons do not consume every ring');
    }
    return polygons;
  }

  _SpatialIndex _parseIndex(
    int offsetsOffset,
    int referencesOffset,
    int cellCount,
    int referenceCount,
    int polygonCount,
  ) {
    final offsets = Uint32List(cellCount + 1);
    for (var index = 0; index <= cellCount; index += 1) {
      offsets[index] = _uint32(offsetsOffset + index * 4);
      if (offsets[index] > referenceCount ||
          (index > 0 && offsets[index] < offsets[index - 1])) {
        _invalid('Spatial-index cell offsets are invalid',
            offsetsOffset + index * 4);
      }
    }
    if (offsets[0] != 0 || offsets[cellCount] != referenceCount) {
      _invalid(
          'Spatial-index offsets do not cover every reference', offsetsOffset);
    }

    final references = Uint32List(referenceCount);
    for (var cell = 0; cell < cellCount; cell += 1) {
      var previous = -1;
      for (var index = offsets[cell]; index < offsets[cell + 1]; index += 1) {
        final polygonIndex = _uint32(referencesOffset + index * 4);
        if (polygonIndex >= polygonCount || polygonIndex <= previous) {
          _invalid('Spatial-index cell references are invalid',
              referencesOffset + index * 4);
        }
        references[index] = polygonIndex;
        previous = polygonIndex;
      }
    }
    return _SpatialIndex(offsets: offsets, references: references);
  }

  void _validateIndexReferences(
    Uint32List offsets,
    Uint32List references,
    List<_Polygon> polygons,
    int gridWidth,
    int gridHeight,
    int scale,
  ) {
    final cellWidth = 360 * scale ~/ gridWidth;
    final cellHeight = 180 * scale ~/ gridHeight;
    final world = 360 * scale;
    for (var cell = 0; cell < gridWidth * gridHeight; cell += 1) {
      final row = cell ~/ gridWidth;
      final column = cell % gridWidth;
      final minimumY = -90 * scale + row * cellHeight;
      final maximumY = minimumY + cellHeight;
      final canonicalMinimumX = -180 * scale + column * cellWidth;
      final canonicalMaximumX = canonicalMinimumX + cellWidth;
      final canonicalCenterX = (canonicalMinimumX + canonicalMaximumX) ~/ 2;
      for (var index = offsets[cell]; index < offsets[cell + 1]; index += 1) {
        final polygon = polygons[references[index]];
        final shift = _nearestQuotient(
          polygon.centerX - canonicalCenterX,
          world,
        );
        final minimumX = canonicalMinimumX + shift * world;
        final maximumX = canonicalMaximumX + shift * world;
        if (maximumY < polygon.minimumY ||
            minimumY > polygon.maximumY ||
            maximumX < polygon.minimumX ||
            minimumX > polygon.maximumX) {
          _invalid(
              'Spatial-index reference does not intersect its polygon bounds');
        }
      }
    }
  }

  void _validateMetadata(
    int offset,
    int length, {
    required int formatVersion,
    required int scale,
    required int gridCells,
    required List<String> codes,
    required int polygonCount,
    required int ringCount,
    required int pointCount,
    required int referenceCount,
  }) {
    Object? decoded;
    try {
      decoded = jsonDecode(
          utf8.decode(Uint8List.sublistView(bytes, offset, offset + length)));
    } on FormatException catch (error) {
      throw CountryCodeDataException(
          'Country boundary metadata is invalid: ${error.message}');
    }
    if (decoded is! Map<String, Object?>) {
      _invalid('Country boundary metadata must be a JSON object', offset);
    }
    if (decoded['binary_format_version'] != formatVersion) {
      _invalid('Country boundary metadata format version does not match');
    }
    final quantization = decoded['quantization'];
    if (quantization is! Map<String, Object?> ||
        quantization['scale'] != scale) {
      _invalid('Country boundary metadata quantization does not match');
    }
    final metadataCodes = decoded['codes'];
    if (metadataCodes is! List<Object?> ||
        metadataCodes.length != codes.length ||
        !_sameCodes(metadataCodes, codes)) {
      _invalid('Country boundary metadata code list does not match');
    }
    final counts = decoded['counts'];
    if (counts is! Map<String, Object?> ||
        counts['asset_codes'] != codes.length ||
        counts['grid_cells'] != gridCells ||
        counts['index_references'] != referenceCount ||
        counts['points'] != pointCount ||
        counts['polygons'] != polygonCount ||
        counts['rings'] != ringCount) {
      _invalid('Country boundary metadata counts do not match');
    }
  }

  bool _sameCodes(List<Object?> metadataCodes, List<String> codes) {
    for (var index = 0; index < codes.length; index += 1) {
      if (metadataCodes[index] != codes[index]) {
        return false;
      }
    }
    return true;
  }

  void _validateBounds(
    String owner,
    int minimumX,
    int minimumY,
    int maximumX,
    int maximumY,
    int scale,
  ) {
    if (minimumX > maximumX ||
        minimumY > maximumY ||
        minimumY < -90 * scale ||
        maximumY > 90 * scale ||
        minimumX < -540 * scale ||
        maximumX > 540 * scale) {
      _invalid('$owner has invalid bounds');
    }
  }

  int _uint16(int offset) => data.getUint16(offset, Endian.little);

  int _uint32(int offset) => data.getUint32(offset, Endian.little);

  int _int32(int offset) => data.getInt32(offset, Endian.little);

  Never _invalid(String message, [int? offset]) {
    throw CountryCodeDataException(message, null, offset);
  }
}

final class _VarintCursor {
  _VarintCursor(this.bytes, this.offset, this.end);

  final Uint8List bytes;
  int offset;
  final int end;

  int read() {
    var result = 0;
    var shift = 0;
    for (var byteIndex = 0; byteIndex < 5; byteIndex += 1) {
      if (offset >= end) {
        throw CountryCodeDataException(
            'Country boundary point stream is truncated', null, offset);
      }
      final byte = bytes[offset];
      offset += 1;
      if (byteIndex == 4 && (byte & 0xf0) != 0) {
        throw CountryCodeDataException(
            'Country boundary point varint overflows 32 bits',
            null,
            offset - 1);
      }
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) {
        return result;
      }
      shift += 7;
    }
    throw CountryCodeDataException(
        'Country boundary point varint is too long', null, offset);
  }
}

final class _RawPolygon {
  const _RawPolygon({
    required this.codeIndex,
    required this.firstRing,
    required this.ringCount,
    required this.minimumX,
    required this.minimumY,
    required this.maximumX,
    required this.maximumY,
    required this.centerX,
  });

  final int codeIndex;
  final int firstRing;
  final int ringCount;
  final int minimumX;
  final int minimumY;
  final int maximumX;
  final int maximumY;
  final int centerX;
}

final class _Polygon {
  const _Polygon({
    required this.codeIndex,
    required this.firstRing,
    required this.ringCount,
    required this.minimumX,
    required this.minimumY,
    required this.maximumX,
    required this.maximumY,
    required this.centerX,
  });

  final int codeIndex;
  final int firstRing;
  final int ringCount;
  final int minimumX;
  final int minimumY;
  final int maximumX;
  final int maximumY;
  final int centerX;
}

final class _RawRing {
  const _RawRing({
    required this.pointOffset,
    required this.pointCount,
    required this.minimumX,
    required this.minimumY,
    required this.maximumX,
    required this.maximumY,
  });

  final int pointOffset;
  final int pointCount;
  final int minimumX;
  final int minimumY;
  final int maximumX;
  final int maximumY;
}

final class _Ring {
  const _Ring({
    required this.firstPoint,
    required this.pointCount,
    required this.minimumX,
    required this.minimumY,
    required this.maximumX,
    required this.maximumY,
  });

  final int firstPoint;
  final int pointCount;
  final int minimumX;
  final int minimumY;
  final int maximumX;
  final int maximumY;
}

final class _DecodedPoints {
  const _DecodedPoints({
    required this.longitudes,
    required this.latitudes,
    required this.rings,
  });

  final Int32List longitudes;
  final Int32List latitudes;
  final List<_Ring> rings;
}

final class _SpatialIndex {
  const _SpatialIndex({required this.offsets, required this.references});

  final Uint32List offsets;
  final Uint32List references;
}

enum _PointLocation { outside, inside, boundary }

int _unzigzag(int value) {
  final magnitude = value ~/ 2;
  return value.isEven ? magnitude : -magnitude - 1;
}

int _nearestQuotient(int numerator, int denominator) => numerator >= 0
    ? (numerator + denominator ~/ 2) ~/ denominator
    : -((-numerator + denominator ~/ 2) ~/ denominator);

bool _insideBounds(
  int x,
  int y,
  int minimumX,
  int minimumY,
  int maximumX,
  int maximumY,
) =>
    x >= minimumX && x <= maximumX && y >= minimumY && y <= maximumY;

int _minimum(int first, int second) => first < second ? first : second;

int _maximum(int first, int second) => first > second ? first : second;
