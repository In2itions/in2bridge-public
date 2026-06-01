# Releases

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

- Final `.deb` package artifacts.
- Final bundled FFmpeg/SRT/RIST runtime payloads.
- RPM package support.
- Internal license generator.
