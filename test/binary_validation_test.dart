import 'dart:typed_data';

import 'package:country_code_locator/country_code_locator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_asset_builder.dart';

void main() {
  late Uint8List validAsset;

  setUpAll(() {
    validAsset = buildTestAsset(<TestPolygon>[
      TestPolygon(
        code: 'JP',
        rings: <List<TestPoint>>[
          const <TestPoint>[
            TestPoint(130, 30),
            TestPoint(150, 30),
            TestPoint(150, 45),
            TestPoint(130, 45),
          ],
        ],
      ),
    ]);
  });

  test('accepts a complete supported asset', () {
    final locator = OfflineCountryCode.fromBytes(validAsset);
    expect(locator.lookup(latitude: 35, longitude: 140), 'JP');
  });

  test('rejects a truncated asset', () {
    final truncated =
        Uint8List.sublistView(validAsset, 0, validAsset.length - 1);
    expect(
      () => OfflineCountryCode.fromBytes(truncated),
      throwsA(isA<CountryCodeDataException>()),
    );
  });

  test('rejects an invalid magic number', () {
    final corrupted = Uint8List.fromList(validAsset)..[0] ^= 0xff;
    expect(
      () => OfflineCountryCode.fromBytes(corrupted),
      throwsA(isA<CountryCodeDataException>()),
    );
  });

  test('rejects an unsupported format version', () {
    final unsupported = Uint8List.fromList(validAsset);
    ByteData.sublistView(unsupported).setUint16(8, 2, Endian.little);
    expect(
      () => OfflineCountryCode.fromBytes(unsupported),
      throwsA(
        isA<CountryCodeDataException>().having(
          (error) => error.message,
          'message',
          contains('Unsupported'),
        ),
      ),
    );
  });

  test('rejects payload corruption', () {
    final corrupted = Uint8List.fromList(validAsset)
      ..[validAsset.length - 1] ^= 0xff;
    expect(
      () => OfflineCountryCode.fromBytes(corrupted),
      throwsA(
        isA<CountryCodeDataException>().having(
          (error) => error.message,
          'message',
          contains('checksum'),
        ),
      ),
    );
  });
}
