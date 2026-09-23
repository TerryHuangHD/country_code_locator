import 'package:country_code_locator/src/country_data.dart';
import 'package:flutter/services.dart';

/// An initialized, immutable offline country-code locator.
///
/// Create one with [load]. Loading validates the bundled data and builds the
/// in-memory spatial index once. Every subsequent [lookup] is synchronous and
/// performs no I/O.
final class OfflineCountryCode {
  OfflineCountryCode._(this._data);

  /// Natural Earth release represented by the bundled asset.
  static const String dataVersion = '5.1.1';

  /// Binary container format version understood by this release.
  static const int binaryFormatVersion = 2;

  /// Flutter asset key used by [load].
  static const String assetKey =
      'packages/country_code_locator/assets/country_boundaries.bin';

  final CountryData _data;

  /// Loads and validates the bundled country-boundary data.
  ///
  /// Pass an [AssetBundle] to control loading in tests or custom Flutter
  /// embedders. The default is [rootBundle]. Missing assets surface the bundle's
  /// loading error; invalid data throws `CountryCodeDataException`.
  static Future<OfflineCountryCode> load({AssetBundle? bundle}) async {
    final byteData = await (bundle ?? rootBundle).load(assetKey);
    final bytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    return fromBytes(bytes);
  }

  /// Builds a locator from an already loaded binary asset.
  ///
  /// The bytes are fully validated and decoded during this call. The locator
  /// does not retain or mutate [bytes]. This entry point is useful when an
  /// application owns its asset-loading layer.
  static OfflineCountryCode fromBytes(Uint8List bytes) {
    return OfflineCountryCode._(CountryData.parse(bytes));
  }

  /// Returns the officially assigned ISO 3166-1 code at a coordinate.
  ///
  /// Returns `null` for ocean, uncovered or uncoded land, and ambiguous shared
  /// boundaries. A point on a boundary belonging to exactly one code matches
  /// that code. `-180` and `180` are the same meridian.
  /// [format] selects Alpha-2 (the default) or Alpha-3 without changing the
  /// boundary or ambiguity rules.
  ///
  /// Throws [ArgumentError] when either coordinate is non-finite or outside its
  /// WGS 84 range.
  String? lookup({
    required double latitude,
    required double longitude,
    CountryCodeFormat format = CountryCodeFormat.alpha2,
  }) {
    return _data.lookup(
      latitude: latitude,
      longitude: longitude,
      format: format,
    );
  }
}
