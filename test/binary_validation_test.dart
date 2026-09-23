import 'dart:typed_data';

import 'package:country_code_locator/country_code_locator.dart';
import 'package:country_code_locator/src/crc32.dart';
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
    ByteData.sublistView(unsupported).setUint16(8, 1, Endian.little);
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

  test('rejects an official Alpha-3 code paired with the wrong Alpha-2', () {
    final corrupted = Uint8List.fromList(validAsset);
    // Keep the payload checksum valid so the pairing check must catch this.
    corrupted.setAll(82, 'USA'.codeUnits); // JP -> USA instead of JPN.
    ByteData.sublistView(corrupted).setUint32(
      16,
      crc32(corrupted, 80, corrupted.length),
      Endian.little,
    );
    expect(
      () => OfflineCountryCode.fromBytes(corrupted),
      throwsA(
        isA<CountryCodeDataException>().having(
          (error) => error.message,
          'message',
          contains('Alpha-3 pairing'),
        ),
      ),
    );
  });

  test('rejects a metadata Alpha-3 list different from the code table', () {
    final corrupted = Uint8List.fromList(validAsset);
    final metadataOffset =
        ByteData.sublistView(corrupted).getUint32(72, Endian.little);
    const marker = '"alpha3_codes":["';
    final metadata = String.fromCharCodes(corrupted, metadataOffset);
    final codeOffset =
        metadataOffset + metadata.indexOf(marker) + marker.length;
    corrupted.setAll(codeOffset, 'USA'.codeUnits);
    ByteData.sublistView(corrupted).setUint32(
      16,
      crc32(corrupted, 80, corrupted.length),
      Endian.little,
    );
    expect(
      () => OfflineCountryCode.fromBytes(corrupted),
      throwsA(
        isA<CountryCodeDataException>().having(
          (error) => error.message,
          'message',
          contains('metadata Alpha-3'),
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
