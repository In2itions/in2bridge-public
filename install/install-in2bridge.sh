#!/usr/bin/env bash
set -euo pipefail

RELEASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGES_DIR="${RELEASE_DIR}/packages"
VERSION="${IN2BRIDGE_VERSION:-0.0.12}"
PUBLIC_REPO="${IN2BRIDGE_PUBLIC_REPO:-In2itions/in2bridge-public}"
DOWNLOAD_DIR=""

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

install_prerequisites() {
  local os_id="$1"
  case "${os_id}" in
    ubuntu|debian)
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-client ca-certificates curl
      ;;
    *)
      echo "Unsupported OS for automatic installation: ${os_id}" >&2
      exit 1
      ;;
  esac
}

download_release_script() {
  local script_name="$1"
  local script_path="${RELEASE_DIR}/install/${script_name}"

  if [ -f "${script_path}" ]; then
    printf "%s" "${script_path}"
    return
  fi

  DOWNLOAD_DIR="${DOWNLOAD_DIR:-$(mktemp -d)}"
  script_path="${DOWNLOAD_DIR}/${script_name}"
  curl -fL "https://github.com/${PUBLIC_REPO}/releases/download/v${VERSION}/${script_name}" -o "${script_path}"
  chmod 0755 "${script_path}"
  printf "%s" "${script_path}"
}

ensure_database_defaults() {
  local setup_env="/root/in2bridge/database.env"
  local setup_script
  local configure_local_db

  if [ -r "${setup_env}" ]; then
    return
  fi

  read -r -p "No local database credentials found. Configure local MariaDB now? [Y/n]: " configure_local_db
  case "${configure_local_db:-Y}" in
    y|Y|yes|YES)
      setup_script="$(download_release_script setup-database.sh)"
      bash "${setup_script}"
      ;;
    *)
      echo "Skipping local database setup. The application database step will ask for external DB credentials."
      ;;
  esac
}

run_ldconfig() {
  rm -f /etc/ld.so.conf.d/in2bridge-runtime.conf
  if command -v ldconfig >/dev/null 2>&1; then
    ldconfig
  fi
}

verify_engine_linkage() {
  local missing

  if [ ! -x /usr/bin/in2bridge-engine ]; then
    echo "Engine binary was not installed at /usr/bin/in2bridge-engine." >&2
    exit 1
  fi

  missing="$(LD_LIBRARY_PATH=/opt/in2bridge/runtime/lib ldd /usr/bin/in2bridge-engine 2>&1 | awk '/not found/ { print }')"
  if [ -n "${missing}" ]; then
    echo "Engine shared-library check failed:" >&2
    echo "${missing}" >&2
    echo "Runtime libraries should resolve from /opt/in2bridge/runtime/lib." >&2
    exit 1
  fi
}

verify_runtime_tools() {
  local tool

  for tool in ffmpeg ffprobe; do
    if [ ! -x "/opt/in2bridge/runtime/bin/${tool}" ]; then
      echo "Runtime tool missing: /opt/in2bridge/runtime/bin/${tool}" >&2
      exit 1
    fi

    if ! "/opt/in2bridge/runtime/bin/${tool}" -version >/dev/null 2>&1; then
      echo "Runtime tool failed to start: /opt/in2bridge/runtime/bin/${tool}" >&2
      echo "Check /opt/in2bridge/runtime/lib and runtime package contents." >&2
      exit 1
    fi
  done
}

install_deb_packages() {
  local runtime_deb
  local engine_deb
  runtime_deb="$(ls "${PACKAGES_DIR}"/in2bridge-runtime_*.deb 2>/dev/null | sort | tail -n 1 || true)"
  engine_deb="$(ls "${PACKAGES_DIR}"/in2bridge-engine_*.deb 2>/dev/null | sort | tail -n 1 || true)"

  if [ -z "${runtime_deb}" ] || [ -z "${engine_deb}" ]; then
    DOWNLOAD_DIR="$(mktemp -d)"
    runtime_deb="${DOWNLOAD_DIR}/in2bridge-runtime_${VERSION}_amd64.deb"
    engine_deb="${DOWNLOAD_DIR}/in2bridge-engine_${VERSION}_amd64.deb"

    echo "Local release packages not found in ${PACKAGES_DIR}; downloading v${VERSION} from GitHub."
    curl -fL "https://github.com/${PUBLIC_REPO}/releases/download/v${VERSION}/in2bridge-runtime_${VERSION}_amd64.deb" -o "${runtime_deb}"
    curl -fL "https://github.com/${PUBLIC_REPO}/releases/download/v${VERSION}/in2bridge-engine_${VERSION}_amd64.deb" -o "${engine_deb}"
  fi

  dpkg -i "${runtime_deb}" "${engine_deb}"
  apt-get -f install -y
  run_ldconfig
  verify_runtime_tools
  verify_engine_linkage
}

cleanup() {
  if [ -n "${DOWNLOAD_DIR}" ] && [ -d "${DOWNLOAD_DIR}" ]; then
    rm -rf "${DOWNLOAD_DIR}"
  fi
}

trap cleanup EXIT

read_setup_env_value() {
  local key="$1"
  local setup_env="$2"
  awk -F= -v key="${key}" '$1 == key { print substr($0, length(key) + 2); exit }' "${setup_env}"
}

export_setup_database_defaults() {
  local setup_env="$1"

  export IN2BRIDGE_DB_HOST
  export IN2BRIDGE_DB_PORT
  export IN2BRIDGE_DB_NAME
  export IN2BRIDGE_DB_USER
  export IN2BRIDGE_DB_PASSWORD

  IN2BRIDGE_DB_HOST="$(read_setup_env_value IN2BRIDGE_DB_HOST "${setup_env}")"
  IN2BRIDGE_DB_PORT="$(read_setup_env_value IN2BRIDGE_DB_PORT "${setup_env}")"
  IN2BRIDGE_DB_NAME="$(read_setup_env_value IN2BRIDGE_DB_NAME "${setup_env}")"
  IN2BRIDGE_DB_USER="$(read_setup_env_value IN2BRIDGE_DB_USER "${setup_env}")"
  IN2BRIDGE_DB_PASSWORD="$(read_setup_env_value IN2BRIDGE_DB_PASSWORD "${setup_env}")"
}

configure_app_database() {
  local db_script="${RELEASE_DIR}/install/configure-app-database.sh"
  local setup_env="/root/in2bridge/database.env"

  if [ ! -f "${db_script}" ]; then
    db_script="/opt/in2bridge/install/configure-app-database.sh"
  fi

  if [ ! -f "${db_script}" ]; then
    DOWNLOAD_DIR="${DOWNLOAD_DIR:-$(mktemp -d)}"
    db_script="${DOWNLOAD_DIR}/configure-app-database.sh"
    curl -fL "https://github.com/${PUBLIC_REPO}/releases/download/v${VERSION}/configure-app-database.sh" -o "${db_script}"
    chmod 0755 "${db_script}"
  fi

  if [ -r "${setup_env}" ]; then
    echo "Using database defaults from ${setup_env}."
    export_setup_database_defaults "${setup_env}"
  else
    echo "No ${setup_env} found. You can run setup-database.sh first for a local database."
  fi

  bash "${db_script}"
}

start_and_verify_service() {
  systemctl daemon-reload
  systemctl reset-failed in2bridge-engine.service >/dev/null 2>&1 || true
  systemctl enable in2bridge-engine.service
  systemctl restart in2bridge-engine.service
  sleep 2

  if ! systemctl is-active --quiet in2bridge-engine.service; then
    echo "in2bridge-engine.service did not start successfully." >&2
    journalctl -u in2bridge-engine.service -n 80 --no-pager >&2 || true
    exit 1
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
      install_prerequisites "${os_id}"
      ensure_database_defaults
      install_deb_packages
      configure_app_database
      start_and_verify_service
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
