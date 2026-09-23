/// Thrown when bundled country-boundary data is unsupported or invalid.
final class CountryCodeDataException extends FormatException {
  /// Creates an exception describing invalid country-boundary data.
  const CountryCodeDataException(super.message, [super.source, super.offset]);
}
