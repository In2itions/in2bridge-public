# Install in2bridge

This document describes the intended public installation flow.

## Ubuntu/Debian

```bash
sudo ./install/install-in2bridge.sh
```

The installer will:

1. Install MariaDB/MySQL packages from the OS repository.
2. Install the in2bridge runtime package.
3. Install the in2bridge engine package.
4. Write `/etc/in2bridge/in2bridge.env` if it does not exist.
5. Enable and start `in2bridge-engine.service`.

## Runtime policy

The installer must use in2bridge-provided FFmpeg, SRT, and RIST runtime files
under `/opt/in2bridge/runtime`. Distro versions are not used for transport or
preview behavior.

## License

Customer packages do not include a license generator. Offline licenses are
generated internally and imported through the management UI or API.

