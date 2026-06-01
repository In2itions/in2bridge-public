# Runtime components

The following runtime components are shipped by in2bridge and pinned per
release:

- FFmpeg
- FFprobe
- SRT libraries/tools
- RIST libraries/tools

These components are installed under `/opt/in2bridge/runtime`.

The systemd service must prefer these paths:

```bash
IN2BRIDGE_FFMPEG_BIN=/opt/in2bridge/runtime/bin/ffmpeg
IN2BRIDGE_FFPROBE_BIN=/opt/in2bridge/runtime/bin/ffprobe
LD_LIBRARY_PATH=/opt/in2bridge/runtime/lib
PATH=/opt/in2bridge/runtime/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

Database packages may come from the OS repository. Transport/media behavior
must not depend on OS repository versions.

