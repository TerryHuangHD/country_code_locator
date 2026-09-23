import 'dart:convert';
import 'dart:io';

import 'package:country_code_locator/country_code_locator.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reports cold load, warm lookup, memory, and asset size', () async {
    final rssBefore = ProcessInfo.currentRss;
    final maxRssBefore = ProcessInfo.maxRss;
    final loadWatch = Stopwatch()..start();
    final locator = await OfflineCountryCode.load();
    loadWatch.stop();
    final rssAfterLoad = ProcessInfo.currentRss;
    final maxRssAfterLoad = ProcessInfo.maxRss;
    final asset = await rootBundle.load(OfflineCountryCode.assetKey);

    const coordinates = <({double latitude, double longitude})>[
      (latitude: 35.6812, longitude: 139.7671),
      (latitude: 25.0330, longitude: 121.5654),
      (latitude: 40.7128, longitude: -74.0060),
      (latitude: -17.5516, longitude: -149.5585),
      (latitude: 0, longitude: -140),
      (latitude: 42.6629, longitude: 21.1655),
    ];

    var checksum = 0;
    for (var index = 0; index < 10000; index += 1) {
      final coordinate = coordinates[index % coordinates.length];
      final code = locator.lookup(
        latitude: coordinate.latitude,
        longitude: coordinate.longitude,
      );
      checksum ^= code?.codeUnitAt(0) ?? 0;
    }

    const iterations = 250000;
    final lookupWatch = Stopwatch()..start();
    for (var index = 0; index < iterations; index += 1) {
      final coordinate = coordinates[index % coordinates.length];
      final code = locator.lookup(
        latitude: coordinate.latitude,
        longitude: coordinate.longitude,
      );
      checksum ^= code?.codeUnitAt(1) ?? 0;
    }
    lookupWatch.stop();

    final result = <String, Object>{
      'asset_bytes': asset.lengthInBytes,
      'cold_load_microseconds': loadWatch.elapsedMicroseconds,
      'iterations': iterations,
      'max_rss_after_load_bytes': maxRssAfterLoad,
      'max_rss_delta_bytes': maxRssAfterLoad - maxRssBefore,
      'process_rss_after_load_bytes': rssAfterLoad,
      'process_rss_delta_bytes': rssAfterLoad - rssBefore,
      'warm_lookup_nanoseconds_average':
          lookupWatch.elapsedMicroseconds * 1000 / iterations,
    };
    // One machine-readable line makes device runs easy to archive.
    // ignore: avoid_print
    print('BENCHMARK_RESULT ${jsonEncode(result)}');
    expect(checksum, isNonNegative);
  });
}
