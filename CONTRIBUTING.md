# Contributing

Changes must preserve the public contract and the deterministic data pipeline.
Open an issue before proposing a different boundary source, political policy,
binary format, or public API.

## Setup

The repository pins Flutter 3.44.9 in `.fvmrc`. Use FVM when available:

```shell
fvm use
fvm flutter pub get
```

Equivalent commands with a compatible Flutter SDK also work.

## Verify a change

```shell
dart format --output=none --set-exit-if-changed lib test example benchmark
flutter analyze
flutter test
python3 tool/generate_boundaries.py --check
flutter pub publish --dry-run
```

Run the example's analyzer separately after changing it:

```shell
cd example
flutter pub get
flutter analyze
```

Behavior changes need a focused regression that would fail for the plausible
bug. Do not add source-text, field-copy, or mock-echo assertions.

## Data changes

Read `doc/DATA.md` before changing a pin or generator. Never hand-edit the binary
asset or generated metadata. Review all reported code, geometry, island, and
size differences, then rerun the fixed-coordinate suite and physical-device
benchmark.

## Pull requests

Keep changes scoped, explain policy or format decisions, update the changelog
when user-visible behavior changes, and include exact verification commands and
results. By contributing, you agree that your code is licensed under MIT.
