# Publishing to pub.dev

## First publication

1. Merge the verified `1.0.0` release to `main` and confirm CI is green.
2. Sign in to pub.dev with the Google account that will own the package
   (or transfer it to a verified publisher after publication).
3. From the repository root, run `flutter pub publish --dry-run`, inspect the
   file list, then run `flutter pub publish` interactively. This first upload
   creates the package on pub.dev; it cannot be bootstrapped by the tag workflow.
4. Confirm the package page, API documentation, example, archive contents, and
   repository links. Do **not** push `v1.0.0` afterward: the tag workflow would
   try to publish the already-published version again.

## One-time automated publishing setup

1. On the published package's pub.dev **Admin** tab, enable publishing from
   GitHub Actions for `TerryHuangHD/country_code_locator` with tag pattern
   `v{{version}}`.
2. Create the GitHub Actions environment named `pub.dev` and require reviewer
   approval. Require that same environment in pub.dev's automated-publishing
   settings.
3. Protect the `v*` tag namespace and `main` branch, and enable GitHub private
   vulnerability reporting.

The release workflow requests only `contents: read` and `id-token: write`; it
uses pub.dev's short-lived GitHub OIDC credential and stores no publish token.

## Subsequent releases

1. Update `version` in `pubspec.yaml` using semantic versioning (for example,
   `1.0.1`); add a dated `CHANGELOG.md` section.
2. If data changed, follow every review step in `doc/DATA.md`.
3. Run and record a profile/release benchmark on representative mobile hardware.
4. Run:

   ```shell
   dart format --output=none --set-exit-if-changed lib test example benchmark
   flutter analyze
   flutter test
   python3 tool/generate_boundaries.py --check
   flutter pub publish --dry-run
   ```

5. Inspect the dry-run file list: the binary asset, metadata, license, readme,
   changelog, example, and provenance docs must be present; caches and local
   source archives must be absent.
6. Commit the release, merge through CI, and create an annotated `vX.Y.Z` tag
   matching `pubspec.yaml` exactly.
7. Push the tag. `.github/workflows/publish.yml` reruns analysis, tests, and
   deterministic generation before invoking `flutter pub publish --force`.
8. Verify the pub.dev package page, API documentation, example, archive
   contents, and repository links.

Never republish changed bytes under an existing version. If publication fails
after the version is accepted, increment the version before retrying with
modified contents.
