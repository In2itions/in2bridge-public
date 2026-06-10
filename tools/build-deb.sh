#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:-0.0.17}"
ARCH="${ARCH:-amd64}"
CARGO_BIN="${CARGO:-cargo}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${RELEASE_ROOT}/.." && pwd)"
PACKAGES_DIR="${RELEASE_ROOT}/packages"
BUILD_ROOT="${RELEASE_ROOT}/build/deb"
RUNTIME_ROOT="${BUILD_ROOT}/in2bridge-runtime"
ENGINE_ROOT="${BUILD_ROOT}/in2bridge-engine"
RUNTIME_INSTALL_ROOT="/opt/in2bridge/runtime"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

copy_linked_libs() {
  local binary="$1"
  local target_lib_dir="$2"

  if [ -z "${binary}" ] || [ ! -e "${binary}" ]; then
    return 0
  fi

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
        copy_runtime_lib "${lib}" "${target_lib_dir}"
        if [ -L "${lib}" ]; then
          local resolved_lib
          resolved_lib="$(readlink -f "${lib}" || true)"
          if [ -n "${resolved_lib}" ] && [ -f "${resolved_lib}" ]; then
            copy_runtime_lib "${resolved_lib}" "${target_lib_dir}"
          fi
        fi
      done
}

copy_runtime_lib() {
  local lib="$1"
  local target_lib_dir="$2"
  local target="${target_lib_dir}/$(basename "${lib}")"
  local source_real
  local target_real

  [ -f "${lib}" ] || [ -L "${lib}" ] || return 0

  source_real="$(readlink -f "${lib}" || true)"
  target_real="$(readlink -f "${target}" 2>/dev/null || true)"
  if [ -n "${source_real}" ] && [ -n "${target_real}" ] && [ "${source_real}" = "${target_real}" ]; then
    return 0
  fi

  if [ -L "${lib}" ]; then
    if [ -n "${source_real}" ] && [ -f "${source_real}" ]; then
      copy_runtime_lib "${source_real}" "${target_lib_dir}"
      ln -sfn "$(basename "${source_real}")" "${target}"
    fi
  else
    cp -a "${lib}" "${target_lib_dir}/"
  fi
}

copy_media_library_family() {
  local binary="$1"
  local target_lib_dir="$2"
  local binary_dir
  local lib_dir

  if [ -z "${binary}" ] || [ ! -x "${binary}" ]; then
    return 0
  fi

  binary_dir="$(dirname "$(readlink -f "${binary}")")"

  for lib_dir in "${binary_dir}" /usr/lib /usr/lib64 /usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu; do
    [ -d "${lib_dir}" ] || continue
    find "${lib_dir}" -maxdepth 1 -type f,l \
      \( -name 'libav*.so*' -o -name 'libsw*.so*' -o -name 'libpostproc*.so*' \) \
      | while read -r media_lib; do
          copy_runtime_lib "${media_lib}" "${target_lib_dir}"
        done
  done
}

copy_linked_lib_closure() {
  local target_lib_dir="$1"
  local scan_dir="$2"
  local before
  local after

  while true; do
    before="$(find "${target_lib_dir}" -maxdepth 1 -type f,l | wc -l)"
    find "${scan_dir}" "${target_lib_dir}" -maxdepth 1 -type f,l 2>/dev/null \
      | while read -r item; do
          [[ "$(basename "${item}")" == *.so* ]] || [ -x "${item}" ] || continue
          LD_LIBRARY_PATH="${target_lib_dir}:${LD_LIBRARY_PATH:-}" copy_linked_libs "${item}" "${target_lib_dir}"
        done
    after="$(find "${target_lib_dir}" -maxdepth 1 -type f,l | wc -l)"
    [ "${after}" -gt "${before}" ] || break
  done
}

write_runtime_wrapper() {
  local wrapper_path="$1"
  local real_name="$2"

  cat >"${wrapper_path}" <<EOF
#!/usr/bin/env bash
set -e
export LD_LIBRARY_PATH="${RUNTIME_INSTALL_ROOT}/lib:\${LD_LIBRARY_PATH:-}"
exec "${RUNTIME_INSTALL_ROOT}/libexec/${real_name}" "\$@"
EOF
  chmod 0755 "${wrapper_path}"
}

copy_binary_with_libs() {
  local binary="$1"
  local target_bin_dir="$2"
  local target_lib_dir="$3"
  local target_exec_dir="${4:-${target_bin_dir}}"
  local name

  if [ -z "${binary}" ] || [ ! -x "${binary}" ]; then
    return 0
  fi

  name="$(basename "${binary}")"
  install -m 0755 "${binary}" "${target_exec_dir}/${name}"
  if [ "${target_exec_dir}" != "${target_bin_dir}" ]; then
    write_runtime_wrapper "${target_bin_dir}/${name}" "${name}"
  fi
  copy_linked_libs "${binary}" "${target_lib_dir}"
  copy_media_library_family "${binary}" "${target_lib_dir}"
}

write_control() {
  local package_root="$1"
  local package_name="$2"
  local description="$3"
  local depends="${4:-}"

  install -d -m 0755 "${package_root}/DEBIAN"
  cat >"${package_root}/DEBIAN/control" <<EOF
Package: ${package_name}
Version: ${VERSION}
Section: video
Priority: optional
Architecture: ${ARCH}
Maintainer: In2itions <support@in2itions.com>
EOF
  if [ -n "${depends}" ]; then
    cat >>"${package_root}/DEBIAN/control" <<EOF
Depends: ${depends}
EOF
  fi
  cat >>"${package_root}/DEBIAN/control" <<EOF
Description: ${description}
EOF
}

build_runtime_package() {
  local root="${RUNTIME_ROOT}"
  local bin_dir="${root}/opt/in2bridge/runtime/bin"
  local exec_dir="${root}/opt/in2bridge/runtime/libexec"
  local lib_dir="${root}/opt/in2bridge/runtime/lib"

  rm -rf "${root}"
  install -d -m 0755 "${bin_dir}" "${exec_dir}" "${lib_dir}"
  write_control "${root}" "in2bridge-runtime" "Pinned in2bridge FFmpeg, SRT, and RIST runtime"

  copy_binary_with_libs "$(command -v ffmpeg || true)" "${bin_dir}" "${lib_dir}" "${exec_dir}"
  copy_binary_with_libs "$(command -v ffprobe || true)" "${bin_dir}" "${lib_dir}" "${exec_dir}"
  copy_binary_with_libs "$(command -v srt-live-transmit || true)" "${bin_dir}" "${lib_dir}" "${exec_dir}"
  copy_binary_with_libs "$(command -v srt-file-transmit || true)" "${bin_dir}" "${lib_dir}" "${exec_dir}"
  copy_binary_with_libs "$(command -v srt-tunnel || true)" "${bin_dir}" "${lib_dir}" "${exec_dir}"
  copy_binary_with_libs "$(command -v ristsender || true)" "${bin_dir}" "${lib_dir}" "${exec_dir}"
  copy_binary_with_libs "$(command -v ristreceiver || true)" "${bin_dir}" "${lib_dir}" "${exec_dir}"
  copy_linked_libs "${REPO_ROOT}/target/release/in2bridge-engine" "${lib_dir}"
  copy_linked_lib_closure "${lib_dir}" "${exec_dir}"

  cat >"${root}/opt/in2bridge/runtime/VERSIONS" <<EOF
in2bridge-runtime ${VERSION}
ffmpeg: $(ffmpeg -version 2>/dev/null | head -n 1 || echo "not found")
ffprobe: $(ffprobe -version 2>/dev/null | head -n 1 || echo "not found")
srt-live-transmit: $(srt-live-transmit -version 2>&1 | head -n 1 || echo "not found")
ristsender: $(ristsender --version 2>&1 | head -n 1 || echo "not found")
ristreceiver: $(ristreceiver --version 2>&1 | head -n 1 || echo "not found")
EOF

  cat >"${root}/DEBIAN/postinst" <<'EOF'
#!/usr/bin/env bash
set -e

rm -f /etc/ld.so.conf.d/in2bridge-runtime.conf

if command -v ldconfig >/dev/null 2>&1; then
  ldconfig || true
fi
EOF

  cat >"${root}/DEBIAN/postrm" <<'EOF'
#!/usr/bin/env bash
set -e

rm -f /etc/ld.so.conf.d/in2bridge-runtime.conf

if command -v ldconfig >/dev/null 2>&1; then
  ldconfig || true
fi
EOF

  chmod 0755 "${root}/DEBIAN/postinst" "${root}/DEBIAN/postrm"

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
    "${root}/opt/in2bridge/install" \
    "${root}/etc/in2bridge" \
    "${root}/etc/sysctl.d" \
    "${root}/lib/systemd/system" \
    "${root}/var/lib/in2bridge" \
    "${root}/var/log/in2bridge"

  write_control "${root}" "in2bridge-engine" "in2bridge transport engine and management UI" "in2bridge-runtime (= ${VERSION})"

  install -m 0755 "${REPO_ROOT}/target/release/in2bridge-engine" "${root}/usr/bin/in2bridge-engine"
  cp -a "${REPO_ROOT}/gui/dist" "${root}/opt/in2bridge/gui/"
  cp -a "${REPO_ROOT}/db/migrations" "${root}/opt/in2bridge/db/"
  install -m 0755 "${REPO_ROOT}/public-releases/install/setup-database.sh" "${root}/opt/in2bridge/install/setup-database.sh"
  install -m 0755 "${REPO_ROOT}/public-releases/install/configure-app-database.sh" "${root}/opt/in2bridge/install/configure-app-database.sh"
  install -m 0755 "${REPO_ROOT}/public-releases/install/configure-letsencrypt-management-https.sh" "${root}/opt/in2bridge/install/configure-letsencrypt-management-https.sh"
  install -m 0755 "${REPO_ROOT}/public-releases/install/cleanup-in2bridge.sh" "${root}/opt/in2bridge/install/cleanup-in2bridge.sh"

  cat >"${root}/etc/in2bridge/in2bridge.env.example" <<'EOF'
RUST_LOG=in2bridge_engine=info,info
IN2BRIDGE_CONFIG_FROM_DB=true
IN2BRIDGE_LOG_DIR=/var/log/in2bridge
IN2BRIDGE_GUI_DIST=/opt/in2bridge/gui/dist
IN2BRIDGE_PREVIEW_DIR=/var/lib/in2bridge/preview
IN2BRIDGE_MANAGEMENT_LISTEN_ADDRESS=0.0.0.0:8090
IN2BRIDGE_DB_HOST=localhost
IN2BRIDGE_DB_PORT=3306
IN2BRIDGE_DB_NAME=in2bridge
IN2BRIDGE_DB_USER=in2bridge
IN2BRIDGE_DB_PASSWORD=set-during-install
IN2BRIDGE_FFMPEG_BIN=/opt/in2bridge/runtime/bin/ffmpeg
IN2BRIDGE_FFPROBE_BIN=/opt/in2bridge/runtime/bin/ffprobe
IN2BRIDGE_HA_ALLOW_VIP=1
LD_LIBRARY_PATH=/opt/in2bridge/runtime/lib
PATH=/opt/in2bridge/runtime/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EOF

  cat >"${root}/etc/sysctl.d/90-in2bridge-transport.conf" <<'EOF'
# in2bridge transport receive buffers.
# UDP multicast and high-bitrate TS inputs need more than the Linux default
# 212 KB socket buffer to avoid avoidable kernel drops during bursts.
net.core.rmem_max = 67108864
net.core.rmem_default = 8388608
net.core.wmem_max = 67108864
net.core.wmem_default = 8388608
net.core.netdev_max_backlog = 10000
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

if grep -q '^IN2BRIDGE_HA_ALLOW_VIP=' /etc/in2bridge/in2bridge.env; then
  sed -i 's/^IN2BRIDGE_HA_ALLOW_VIP=.*/IN2BRIDGE_HA_ALLOW_VIP=1/' /etc/in2bridge/in2bridge.env
else
  printf '\nIN2BRIDGE_HA_ALLOW_VIP=1\n' >> /etc/in2bridge/in2bridge.env
fi
chown root:in2bridge /etc/in2bridge/in2bridge.env
chmod 0640 /etc/in2bridge/in2bridge.env

if command -v sysctl >/dev/null 2>&1; then
  sysctl --system >/dev/null 2>&1 || true
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
  require_cmd "${CARGO_BIN}"
  require_cmd npm
  require_cmd dpkg-deb
  require_cmd ldd

  install -d -m 0755 "${PACKAGES_DIR}" "${BUILD_ROOT}"

  echo "Building GUI..."
  (cd "${REPO_ROOT}/gui" && npm run build)

  echo "Building engine..."
  (cd "${REPO_ROOT}" && "${CARGO_BIN}" build -p in2bridge-engine --release)

  echo "Building runtime package..."
  build_runtime_package

  echo "Building engine package..."
  build_engine_package

  echo "Packages created:"
  ls -lh "${PACKAGES_DIR}"/in2bridge-*_"${VERSION}"_"${ARCH}".deb
}

main "$@"
