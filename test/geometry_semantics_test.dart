import 'package:country_code_locator/country_code_locator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_asset_builder.dart';

void main() {
  final polygons = <TestPolygon>[
    TestPolygon(
      code: 'US',
      rings: <List<TestPoint>>[
        _square(-10, -10, 10, 10),
        _square(-3, -3, 3, 3),
      ],
    ),
    TestPolygon(code: 'CA', rings: <List<TestPoint>>[_square(-1, -1, 1, 1)]),
    TestPolygon(code: 'JP', rings: <List<TestPoint>>[_square(10, -10, 20, 10)]),
    TestPolygon(code: 'US', rings: <List<TestPoint>>[_square(30, -5, 35, 5)]),
    TestPolygon(
      code: 'AU',
      rings: const <List<TestPoint>>[
        <TestPoint>[
          TestPoint(170, -5),
          TestPoint(190, -5),
          TestPoint(190, 5),
          TestPoint(170, 5),
        ],
      ],
    ),
    TestPolygon(code: null, rings: <List<TestPoint>>[_square(40, -5, 50, 5)]),
  ];
  final locator = OfflineCountryCode.fromBytes(buildTestAsset(polygons));

  group('polygon semantics', () {
    test('matches an outer-ring interior and a single-code boundary', () {
      expect(locator.lookup(latitude: 8, longitude: 0), 'US');
      expect(locator.lookup(latitude: 0, longitude: -10), 'US');
    });

    test('excludes a hole and continues to another candidate', () {
      expect(locator.lookup(latitude: 0, longitude: 2), isNull);
      expect(locator.lookup(latitude: 0, longitude: 0), 'CA');
    });

    test('treats a hole ring as the owning polygon boundary', () {
      expect(locator.lookup(latitude: 0, longitude: 3), 'US');
    });

    test('resolves another polygon with the same code as a MultiPolygon member',
        () {
      expect(locator.lookup(latitude: 0, longitude: 32), 'US');
    });

    test('returns null on a shared boundary between different codes', () {
      expect(locator.lookup(latitude: 0, longitude: 10), isNull);
    });

    test('uses the asset quantization rule for boundary decisions', () {
      expect(locator.lookup(latitude: 0, longitude: 9.9996), isNull);
      expect(locator.lookup(latitude: 0, longitude: 9.9994), 'US');
    });

    test('returns null when uncoded source geometry is hit', () {
      expect(locator.lookup(latitude: 0, longitude: 45), isNull);
    });
  });

  group('antimeridian semantics', () {
    test('projects both sides into one unwrapped polygon', () {
      expect(locator.lookup(latitude: 0, longitude: 179), 'AU');
      expect(locator.lookup(latitude: 0, longitude: -179), 'AU');
    });

    test('treats -180 and 180 as the same in-polygon meridian', () {
      expect(locator.lookup(latitude: 0, longitude: -180), 'AU');
      expect(locator.lookup(latitude: 0, longitude: 180), 'AU');
    });
  });

  test('shared-boundary results do not depend on polygon order', () {
    final reversed = OfflineCountryCode.fromBytes(
      buildTestAsset(polygons.reversed.toList(growable: false)),
    );
    expect(reversed.lookup(latitude: 0, longitude: 10), isNull);
  });
}

List<TestPoint> _square(int west, int south, int east, int north) =>
    <TestPoint>[
      TestPoint(west, south),
      TestPoint(east, south),
      TestPoint(east, north),
      TestPoint(west, north),
    ];
