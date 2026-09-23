# Performance measurements

These values are measurements of one pinned release, not guaranteed thresholds.
Do not compare or publish results without recording device, OS, Flutter version,
build mode, workload, and asset digest.

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

## Development benchmark

The committed benchmark uses the same workload and emits one machine-readable
`BENCHMARK_RESULT` line:

```shell
flutter test benchmark/lookup_benchmark_test.dart
```

This command runs in the Flutter test environment and is useful for regression
comparison, not as a substitute for profile/release measurements on a physical
mobile device. Before publishing a data or runtime change, repeat the method on
representative Android and/or iOS hardware and update this document only with
observed output.
