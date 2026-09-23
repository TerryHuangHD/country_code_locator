# Performance measurements

The 1.0.0 device run and 1.1.0 development run below are observations, not
guaranteed thresholds. Compare results only when device, OS, Flutter version,
build mode, workload, and asset digest are recorded.

## 1.0.0 baseline

Measured 2026-09-23 on a physical Pixel 10 (`android-arm64`) running Android 17
(API 37), with Flutter 3.44.9 / Dart 3.12.2 in profile mode.

| Metric | Result |
| --- | ---: |
| Asset size | 2,570,639 bytes (2.45 MiB) |
| Cold `OfflineCountryCode.load()` | 55,345 µs (55.345 ms) |
| Warm lookup average | 8,874.824 ns (8.875 µs) |
| Process RSS after load | 184,496,128 bytes |
| Process RSS delta across load | 14,348,288 bytes (13.69 MiB) |
| Process maximum RSS after load | 183,353,344 bytes |
| Process maximum-RSS delta | 14,155,776 bytes (13.50 MiB) |

Method:

1. start a fresh profile-mode Flutter process;
2. sample `ProcessInfo.currentRss` and `ProcessInfo.maxRss`;
3. time the first `OfflineCountryCode.load()` including bundle loading,
   integrity validation, decoding, and index construction;
4. sample RSS again;
5. warm up 50,000 lookups over four land points, one ocean point, and Kosovo;
6. time 1,000,000 lookups over the same rotating coordinate set; and
7. divide elapsed lookup time by the iteration count.

Process RSS includes the Flutter engine, Dart runtime, application, and test
harness—not only the library. The delta is an approximation of initialization
cost; allocator behavior and prior high-water marks affect it. Average lookup
latency includes loop and coordinate-selection overhead and does not describe
tail latency.

## 1.1.0 development observation

Measured 2026-09-24 on an Apple M1 Max (`darwin-arm64`, Darwin 27.0.0),
Flutter 3.44.9 / Dart 3.12.2, in the Flutter test VM. Version 2 asset SHA-256:
`8c2c0176d801323386ee9602ac7df1c0a449e4437af338211b6b658d98f84478`.
One cold load, 10,000 warm-up lookups of each format, then 250,000 queries per
format over six rotating coordinates:

| Metric | Result |
| --- | ---: |
| Asset size | 2,573,123 bytes |
| Cold `OfflineCountryCode.load()` | 83,069 µs |
| Warm Alpha-2 lookup average | 16,063.648 ns |
| Warm Alpha-3 lookup average | 15,872.248 ns |
| Process RSS delta across load | 12,664,832 bytes |
| Process maximum-RSS delta | 36,847,616 bytes |

The test VM is not a profile-mode mobile device. Do not compare these timings
to the Android 1.0.0 baseline or claim a speedup from this single run.

## Development benchmark

The committed benchmark uses the same coordinates for both Alpha-2 and
Alpha-3 queries. It emits one machine-readable `BENCHMARK_RESULT` line with
separate warm lookup averages for each format:

```shell
flutter test benchmark/lookup_benchmark_test.dart
```

This command runs in the Flutter test environment and is useful for regression
comparison, not as a substitute for profile/release measurements on a physical
mobile device. The 1.0.0 device measurements above cover Alpha-2 and the version
1 asset; they are not measurements of the version 2 asset or Alpha-3 lookup.
Before publishing a data or runtime change, repeat the method on representative
Android and/or iOS hardware and update this document only with observed output.
