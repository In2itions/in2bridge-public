# Releases

## 0.0.16

Public release package refresh for SRT listener multi-client output.

### Included

- Allows SRT listener outputs to serve multiple connected callers at the same time.
- Fixes Analyzer preview getting stuck when VLC or another receiver is already joined to the same SRT output.
- Keeps output counters based on source packets rather than multiplying bitrate by the number of connected SRT clients.
- Adds Linux regression coverage proving one SRT listener output can feed two simultaneous callers.
- Bootstrap installer defaulting to `v0.0.16`.

## 0.0.15

Public release package refresh for stream lifecycle and analyzer preview stability.

### Included

- Waits for aborted stream workers to finish cleanup before returning from stop operations.
- Prevents config apply/start from racing against stale SRT listeners on unchanged or restarted outputs.
- Adds regression coverage proving stop waits for worker cleanup before replacement can proceed.
- Bootstrap installer defaulting to `v0.0.15`.

## 0.0.14

Public release package refresh for SRT analyzer preview with IP allowlists.

### Included

- Allows internal analyzer preview clients through SRT listener source allowlists using node-local listener addresses.
- Uses a concrete bind interface for wildcard SRT listener previews.
- Adds regression coverage for allowlisted SRT listener previews.
- Bootstrap installer defaulting to `v0.0.14`.

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
