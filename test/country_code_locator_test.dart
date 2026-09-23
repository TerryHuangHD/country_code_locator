import 'package:country_code_locator/country_code_locator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late OfflineCountryCode locator;

  setUpAll(() async {
    locator = await OfflineCountryCode.load();
  });

  group('bundled Natural Earth data', () {
    const landCases = <({double latitude, double longitude, String code})>[
      (latitude: 25.0330, longitude: 121.5654, code: 'TW'),
      (latitude: 35.6812, longitude: 139.7671, code: 'JP'),
      (latitude: 40.7128, longitude: -74.0060, code: 'US'),
      (latitude: 22.3193, longitude: 114.1694, code: 'HK'),
      (latitude: 13.4443, longitude: 144.7937, code: 'GU'),
      (latitude: -17.5516, longitude: -149.5585, code: 'PF'),
      (latitude: 21.3069, longitude: -157.8583, code: 'US'),
      (latitude: -29.3158, longitude: 27.4869, code: 'LS'),
      (latitude: 41.9029, longitude: 12.4534, code: 'VA'),
      (latitude: -18.1416, longitude: 178.4419, code: 'FJ'),
      (latitude: -13.8507, longitude: -171.7514, code: 'WS'),
    ];

    for (final testCase in landCases) {
      test('resolves ${testCase.code} at its fixed acceptance coordinate', () {
        expect(
          locator.lookup(
            latitude: testCase.latitude,
            longitude: testCase.longitude,
          ),
          testCase.code,
        );
      });
    }

    test('returns null for open ocean', () {
      expect(locator.lookup(latitude: 0, longitude: -140), isNull);
    });

    test('returns null for Kosovo because XK is not officially assigned', () {
      expect(locator.lookup(latitude: 42.6629, longitude: 21.1655), isNull);
    });

    test('returns null for an uncoded Natural Earth map unit', () {
      expect(locator.lookup(latitude: 35.25, longitude: 33.6), isNull);
    });

    test('treats -180 and 180 as the same meridian', () {
      final west = locator.lookup(latitude: -80, longitude: -180);
      final east = locator.lookup(latitude: -80, longitude: 180);
      expect(east, west);
    });
  });

  group('coordinate validation', () {
    test('rejects non-finite latitude', () {
      for (final value in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity
      ]) {
        expect(
          () => locator.lookup(latitude: value, longitude: 0),
          throwsArgumentError,
        );
      }
    });

    test('rejects non-finite longitude', () {
      for (final value in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity
      ]) {
        expect(
          () => locator.lookup(latitude: 0, longitude: value),
          throwsArgumentError,
        );
      }
    });

    test('rejects coordinates outside WGS 84 ranges', () {
      expect(
        () => locator.lookup(latitude: -90.000001, longitude: 0),
        throwsArgumentError,
      );
      expect(
        () => locator.lookup(latitude: 90.000001, longitude: 0),
        throwsArgumentError,
      );
      expect(
        () => locator.lookup(latitude: 0, longitude: -180.000001),
        throwsArgumentError,
      );
      expect(
        () => locator.lookup(latitude: 0, longitude: 180.000001),
        throwsArgumentError,
      );
    });
  });
}
