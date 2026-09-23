# Security policy

## Supported versions

Security fixes are provided for the latest published major version.

## Report a vulnerability

Use GitHub's private vulnerability reporting for this repository. Do not open a
public issue for a suspected data-integrity bypass, malformed-asset denial of
service, or dependency/workflow credential exposure.

Include the affected version, platform, minimal reproduction, impact, and any
suggested mitigation. Maintainers will acknowledge a report as soon as
practicable and coordinate disclosure after a fix is available.

The bundled CRC-32 detects accidental corruption; it is not a cryptographic
signature and does not make attacker-controlled assets trusted. Applications
loading custom bytes must establish their own source authenticity before
calling `OfflineCountryCode.fromBytes`.
