# Releases

## 0.0.13

Public release package refresh for analyzer preview reliability.

### Included

- Fixes SRT analyzer preview URI normalization.
- Preview sessions now resolve DB endpoint settings before starting FFmpeg, so SRT previews include stored passphrases and key length.
- Output previews for SRT listener endpoints connect as callers instead of trying to bind the already-owned listener port.
- Bootstrap installer defaulting to `v0.0.13`.

## 0.0.12

Public release package refresh for current in2bridge engine and management UI.

### Included

- Updated engine and GUI package payloads.
- Runtime package with pinned FFmpeg, SRT, and RIST runtime libraries.
- Bootstrap installer defaulting to `v0.0.12`.
- Database setup, application database configuration, and cleanup scripts.
- Transport socket buffer sysctl defaults for UDP/SRT/RIST workloads.
- HA VIP enablement in the installed service environment.

### Notes

- Database packages may still be installed from OS repositories.
- Customer packages do not include internal license generation tooling.
- Installed services use `/opt/in2bridge/runtime` before system media paths.

## 0.0.8

Initial public release scaffolding for in2bridge customer packaging.

This release channel contains installer, runtime, packaging, and documentation
structure only. It does not contain private source code or internal license
generation tooling.

### Included

- Public bootstrap installer skeleton for Ubuntu/Debian.
- Public runtime packaging policy.
- Runtime manifest for in2bridge-provided FFmpeg, SRT, and RIST payloads.
- Release staging helper.
- Install and runtime documentation.

### Runtime policy

- Database packages may be installed from OS repositories.
- FFmpeg, SRT, and RIST runtime components must be shipped by in2bridge with
  pinned tested versions.
- Customer installs must use `/opt/in2bridge/runtime` before system paths.

### Not Included Yet

- RPM package support.
- Internal license generator.
