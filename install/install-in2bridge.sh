#!/usr/bin/env bash
set -euo pipefail

RELEASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGES_DIR="${RELEASE_DIR}/packages"

require_root() {
  if [ "${EUID}" -ne 0 ]; then
    echo "Run this installer as root or with sudo." >&2
    exit 1
  fi
}

detect_os() {
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    echo "${ID:-unknown}:${VERSION_ID:-unknown}"
    return
  fi
  echo "unknown:unknown"
}

install_database_packages() {
  local os_id="$1"
  case "${os_id}" in
    ubuntu|debian)
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server mariadb-client ca-certificates curl
      ;;
    *)
      echo "Unsupported OS for automatic database installation: ${os_id}" >&2
      echo "Install MySQL or MariaDB manually, then rerun with database env configured." >&2
      exit 1
      ;;
  esac
}

install_deb_packages() {
  local runtime_deb
  local engine_deb
  runtime_deb="$(ls "${PACKAGES_DIR}"/in2bridge-runtime_*.deb 2>/dev/null | sort | tail -n 1 || true)"
  engine_deb="$(ls "${PACKAGES_DIR}"/in2bridge-engine_*.deb 2>/dev/null | sort | tail -n 1 || true)"

  if [ -z "${runtime_deb}" ] || [ -z "${engine_deb}" ]; then
    echo "Missing release packages in ${PACKAGES_DIR}." >&2
    echo "Expected in2bridge-runtime_*.deb and in2bridge-engine_*.deb." >&2
    exit 1
  fi

  apt-get install -y "${runtime_deb}" "${engine_deb}"
}

write_default_env() {
  install -d -m 0750 /etc/in2bridge
  if [ ! -f /etc/in2bridge/in2bridge.env ]; then
    cat >/etc/in2bridge/in2bridge.env <<'EOF'
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
    chmod 0640 /etc/in2bridge/in2bridge.env
  fi
}

main() {
  require_root

  local os
  local os_id
  os="$(detect_os)"
  os_id="${os%%:*}"

  case "${os_id}" in
    ubuntu|debian)
      install_database_packages "${os_id}"
      install_deb_packages
      write_default_env
      systemctl daemon-reload
      systemctl enable --now in2bridge-engine.service
      ;;
    *)
      echo "Unsupported OS: ${os}" >&2
      exit 1
      ;;
  esac

  echo "in2bridge installation completed."
  echo "Open the management UI on the node management IP, port 8090."
}

main "$@"

