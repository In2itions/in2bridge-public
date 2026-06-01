#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:-0.0.8}"
ARCH="${ARCH:-amd64}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${RELEASE_ROOT}/.." && pwd)"
PACKAGES_DIR="${RELEASE_ROOT}/packages"
BUILD_ROOT="${RELEASE_ROOT}/build/deb"
RUNTIME_ROOT="${BUILD_ROOT}/in2bridge-runtime"
ENGINE_ROOT="${BUILD_ROOT}/in2bridge-engine"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

copy_binary_with_libs() {
  local binary="$1"
  local target_bin_dir="$2"
  local target_lib_dir="$3"

  if [ -z "${binary}" ] || [ ! -x "${binary}" ]; then
    return 0
  fi

  install -m 0755 "${binary}" "${target_bin_dir}/$(basename "${binary}")"

  ldd "${binary}" 2>/dev/null \
    | awk '
      /=> \// { print $3 }
      /^[[:space:]]*\// { print $1 }
    ' \
    | sort -u \
    | while read -r lib; do
        [ -n "${lib}" ] || continue
        [ -f "${lib}" ] || continue
        case "${lib}" in
          /lib/x86_64-linux-gnu/libc.so.*|\
          /lib/x86_64-linux-gnu/libm.so.*|\
          /lib/x86_64-linux-gnu/libdl.so.*|\
          /lib/x86_64-linux-gnu/libpthread.so.*|\
          /lib/x86_64-linux-gnu/librt.so.*|\
          /lib/x86_64-linux-gnu/ld-linux-x86-64.so.*|\
          /lib64/ld-linux-x86-64.so.*)
            continue
            ;;
        esac
        cp -a "${lib}" "${target_lib_dir}/"
      done
}

write_control() {
  local package_root="$1"
  local package_name="$2"
  local description="$3"

  install -d -m 0755 "${package_root}/DEBIAN"
  cat >"${package_root}/DEBIAN/control" <<EOF
Package: ${package_name}
Version: ${VERSION}
Section: video
Priority: optional
Architecture: ${ARCH}
Maintainer: In2itions <support@in2itions.com>
Description: ${description}
EOF
}

build_runtime_package() {
  local root="${RUNTIME_ROOT}"
  local bin_dir="${root}/opt/in2bridge/runtime/bin"
  local lib_dir="${root}/opt/in2bridge/runtime/lib"

  rm -rf "${root}"
  install -d -m 0755 "${bin_dir}" "${lib_dir}"
  write_control "${root}" "in2bridge-runtime" "Pinned in2bridge FFmpeg, SRT, and RIST runtime"

  copy_binary_with_libs "$(command -v ffmpeg || true)" "${bin_dir}" "${lib_dir}"
  copy_binary_with_libs "$(command -v ffprobe || true)" "${bin_dir}" "${lib_dir}"
  copy_binary_with_libs "$(command -v srt-live-transmit || true)" "${bin_dir}" "${lib_dir}"
  copy_binary_with_libs "$(command -v srt-file-transmit || true)" "${bin_dir}" "${lib_dir}"
  copy_binary_with_libs "$(command -v srt-tunnel || true)" "${bin_dir}" "${lib_dir}"
  copy_binary_with_libs "$(command -v ristsender || true)" "${bin_dir}" "${lib_dir}"
  copy_binary_with_libs "$(command -v ristreceiver || true)" "${bin_dir}" "${lib_dir}"

  cat >"${root}/opt/in2bridge/runtime/VERSIONS" <<EOF
in2bridge-runtime ${VERSION}
ffmpeg: $(ffmpeg -version 2>/dev/null | head -n 1 || echo "not found")
ffprobe: $(ffprobe -version 2>/dev/null | head -n 1 || echo "not found")
srt-live-transmit: $(srt-live-transmit -version 2>&1 | head -n 1 || echo "not found")
ristsender: $(ristsender --version 2>&1 | head -n 1 || echo "not found")
ristreceiver: $(ristreceiver --version 2>&1 | head -n 1 || echo "not found")
EOF

  dpkg-deb --build --root-owner-group "${root}" "${PACKAGES_DIR}/in2bridge-runtime_${VERSION}_${ARCH}.deb"
}

build_engine_package() {
  local root="${ENGINE_ROOT}"

  rm -rf "${root}"
  install -d -m 0755 \
    "${root}/DEBIAN" \
    "${root}/usr/bin" \
    "${root}/opt/in2bridge/gui" \
    "${root}/opt/in2bridge/db" \
    "${root}/etc/in2bridge" \
    "${root}/lib/systemd/system" \
    "${root}/var/lib/in2bridge" \
    "${root}/var/log/in2bridge"

  write_control "${root}" "in2bridge-engine" "in2bridge transport engine and management UI"

  install -m 0755 "${REPO_ROOT}/target/release/in2bridge-engine" "${root}/usr/bin/in2bridge-engine"
  cp -a "${REPO_ROOT}/gui/dist" "${root}/opt/in2bridge/gui/"
  cp -a "${REPO_ROOT}/db/migrations" "${root}/opt/in2bridge/db/"

  cat >"${root}/etc/in2bridge/in2bridge.env.example" <<'EOF'
RUST_LOG=in2bridge_engine=info,info
IN2BRIDGE_CONFIG_FROM_DB=true
IN2BRIDGE_LOG_DIR=/var/log/in2bridge
IN2BRIDGE_GUI_DIST=/opt/in2bridge/gui/dist
IN2BRIDGE_PREVIEW_DIR=/var/lib/in2bridge/preview
IN2BRIDGE_DB_HOST=localhost
IN2BRIDGE_DB_PORT=3306
IN2BRIDGE_DB_NAME=in2bridge
IN2BRIDGE_DB_USER=in2bridge
IN2BRIDGE_DB_PASSWORD=change-this-password
IN2BRIDGE_FFMPEG_BIN=/opt/in2bridge/runtime/bin/ffmpeg
IN2BRIDGE_FFPROBE_BIN=/opt/in2bridge/runtime/bin/ffprobe
IN2BRIDGE_HA_ALLOW_VIP=1
LD_LIBRARY_PATH=/opt/in2bridge/runtime/lib
PATH=/opt/in2bridge/runtime/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EOF

  cat >"${root}/lib/systemd/system/in2bridge-engine.service" <<'EOF'
[Unit]
Description=in2bridge transport engine
After=network-online.target mariadb.service mysql.service
Wants=network-online.target

[Service]
Type=simple
User=in2bridge
Group=in2bridge
WorkingDirectory=/var/lib/in2bridge
EnvironmentFile=-/etc/in2bridge/in2bridge.env
ExecStart=/usr/bin/in2bridge-engine --config-from-db
Restart=always
RestartSec=3
LimitNOFILE=1048576
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW
NoNewPrivileges=false

[Install]
WantedBy=multi-user.target
EOF

  cat >"${root}/DEBIAN/postinst" <<'EOF'
#!/usr/bin/env bash
set -e

if ! getent group in2bridge >/dev/null; then
  addgroup --system in2bridge >/dev/null
fi

if ! id in2bridge >/dev/null 2>&1; then
  adduser --system --ingroup in2bridge --home /var/lib/in2bridge --no-create-home in2bridge >/dev/null
fi

install -d -o in2bridge -g in2bridge -m 0750 /var/lib/in2bridge /var/lib/in2bridge/preview /var/log/in2bridge
install -d -o root -g in2bridge -m 0750 /etc/in2bridge

if [ ! -f /etc/in2bridge/in2bridge.env ]; then
  cp /etc/in2bridge/in2bridge.env.example /etc/in2bridge/in2bridge.env
  chown root:in2bridge /etc/in2bridge/in2bridge.env
  chmod 0640 /etc/in2bridge/in2bridge.env
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || true
fi
EOF

  cat >"${root}/DEBIAN/prerm" <<'EOF'
#!/usr/bin/env bash
set -e

if [ "$1" = "remove" ] && command -v systemctl >/dev/null 2>&1; then
  systemctl stop in2bridge-engine.service >/dev/null 2>&1 || true
fi
EOF

  cat >"${root}/DEBIAN/postrm" <<'EOF'
#!/usr/bin/env bash
set -e

if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || true
fi
EOF

  chmod 0755 "${root}/DEBIAN/postinst" "${root}/DEBIAN/prerm" "${root}/DEBIAN/postrm"

  dpkg-deb --build --root-owner-group "${root}" "${PACKAGES_DIR}/in2bridge-engine_${VERSION}_${ARCH}.deb"
}

main() {
  require_cmd cargo
  require_cmd npm
  require_cmd dpkg-deb
  require_cmd ldd

  install -d -m 0755 "${PACKAGES_DIR}" "${BUILD_ROOT}"

  echo "Building GUI..."
  (cd "${REPO_ROOT}/gui" && npm run build)

  echo "Building engine..."
  (cd "${REPO_ROOT}" && cargo build -p in2bridge-engine --release)

  echo "Building runtime package..."
  build_runtime_package

  echo "Building engine package..."
  build_engine_package

  echo "Packages created:"
  ls -lh "${PACKAGES_DIR}"/in2bridge-*_"${VERSION}"_"${ARCH}".deb
}

main "$@"

