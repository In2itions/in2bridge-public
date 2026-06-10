# in2bridge public releases

This folder is the staging area for public/customer release artifacts. It is
intended to be mirrored or copied to a separate public GitHub repository later.

Do not put private source code, internal license generators, development
secrets, or customer-specific configs here.

## Layout

- `install/` - public bootstrap installers.
- `packages/` - generated `.deb`, `.rpm`, checksums, and release manifests.
- `runtime/` - version-pinned third-party runtime payloads shipped by in2bridge.
- `tools/` - release packaging helpers.
- `docs/` - public install and upgrade documentation.

## Build Debian packages

On an Ubuntu build host with Rust, Node.js, npm, FFmpeg, SRT, and RIST tools
installed:

```bash
VERSION=0.0.15 public-releases/tools/build-deb.sh
```

Generated packages are written to `public-releases/packages/`.

## Release policy

- Database packages may be installed from the operating system repository.
- Transport/media runtime must be shipped by in2bridge with fixed tested
  versions. Do not rely on distro FFmpeg, SRT, or RIST behavior.
- Customer packages must not include the license generator.
- The installed engine must use `/opt/in2bridge/runtime` before system paths.

## Target install paths

- `/usr/bin/in2bridge-engine`
- `/opt/in2bridge/gui`
- `/opt/in2bridge/db`
- `/opt/in2bridge/runtime/bin`
- `/opt/in2bridge/runtime/lib`
- `/etc/in2bridge/in2bridge.env`
- `/etc/systemd/system/in2bridge-engine.service`
