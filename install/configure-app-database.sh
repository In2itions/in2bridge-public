#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${IN2BRIDGE_ENV_FILE:-/etc/in2bridge/in2bridge.env}"
SETUP_ENV_FILE="${IN2BRIDGE_SETUP_ENV_FILE:-/root/in2bridge/database.env}"
MIGRATIONS_DIR="${IN2BRIDGE_MIGRATIONS_DIR:-/opt/in2bridge/db/migrations}"
DB_HOST="${IN2BRIDGE_DB_HOST:-localhost}"
DB_PORT="${IN2BRIDGE_DB_PORT:-3306}"
DB_NAME="${IN2BRIDGE_DB_NAME:-in2bridge}"
DB_USER="${IN2BRIDGE_DB_USER:-in2bridge}"
DB_PASSWORD="${IN2BRIDGE_DB_PASSWORD:-}"
DB_PASSWORD_SOURCE="prompt"
NODE_ID="${IN2BRIDGE_NODE_ID:-}"

require_root() {
  if [ "${EUID}" -ne 0 ]; then
    echo "Run this script as root or with sudo." >&2
    exit 1
  fi
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

read_existing_env_value() {
  local key="$1"
  if [ -r "${ENV_FILE}" ]; then
    awk -F= -v key="${key}" '$1 == key { print substr($0, length(key) + 2); exit }' "${ENV_FILE}"
  fi
}

read_setup_env_value() {
  local key="$1"
  if [ -r "${SETUP_ENV_FILE}" ]; then
    awk -F= -v key="${key}" '$1 == key { print substr($0, length(key) + 2); exit }' "${SETUP_ENV_FILE}"
  fi
}

prompt_value() {
  local label="$1"
  local default_value="$2"
  local value
  if [ "${IN2BRIDGE_NONINTERACTIVE:-}" = "1" ] || [ ! -t 0 ]; then
    printf "%s" "${default_value}"
    return
  fi
  if ! read -r -p "${label} [${default_value}]: " value; then
    value=""
    echo >&2
  fi
  printf "%s" "${value:-${default_value}}"
}

prompt_password() {
  local value
  read -r -s -p "Database password: " value
  echo >&2
  printf "%s" "${value}"
}

is_placeholder_password() {
  case "${1:-}" in
    ""|"change-this-password"|"set-during-install")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

load_existing_defaults() {
  local env_password
  local setup_password

  DB_HOST="${IN2BRIDGE_DB_HOST:-$(read_setup_env_value IN2BRIDGE_DB_HOST || true)}"
  DB_PORT="${IN2BRIDGE_DB_PORT:-$(read_setup_env_value IN2BRIDGE_DB_PORT || true)}"
  DB_NAME="${IN2BRIDGE_DB_NAME:-$(read_setup_env_value IN2BRIDGE_DB_NAME || true)}"
  DB_USER="${IN2BRIDGE_DB_USER:-$(read_setup_env_value IN2BRIDGE_DB_USER || true)}"
  setup_password="${IN2BRIDGE_DB_PASSWORD:-$(read_setup_env_value IN2BRIDGE_DB_PASSWORD || true)}"

  DB_HOST="${DB_HOST:-$(read_existing_env_value IN2BRIDGE_DB_HOST || true)}"
  DB_PORT="${DB_PORT:-$(read_existing_env_value IN2BRIDGE_DB_PORT || true)}"
  DB_NAME="${DB_NAME:-$(read_existing_env_value IN2BRIDGE_DB_NAME || true)}"
  DB_USER="${DB_USER:-$(read_existing_env_value IN2BRIDGE_DB_USER || true)}"
  env_password="$(read_existing_env_value IN2BRIDGE_DB_PASSWORD || true)"

  if ! is_placeholder_password "${setup_password}"; then
    DB_PASSWORD="${setup_password}"
    DB_PASSWORD_SOURCE="${SETUP_ENV_FILE}"
  elif ! is_placeholder_password "${IN2BRIDGE_DB_PASSWORD:-}"; then
    DB_PASSWORD="${IN2BRIDGE_DB_PASSWORD}"
    DB_PASSWORD_SOURCE="environment"
  elif ! is_placeholder_password "${env_password}"; then
    DB_PASSWORD="${env_password}"
    DB_PASSWORD_SOURCE="${ENV_FILE}"
  else
    DB_PASSWORD=""
    DB_PASSWORD_SOURCE="prompt"
  fi

  DB_HOST="${DB_HOST:-localhost}"
  DB_PORT="${DB_PORT:-3306}"
  DB_NAME="${DB_NAME:-in2bridge}"
  DB_USER="${DB_USER:-in2bridge}"
  NODE_ID="${NODE_ID:-$(hostname)}"
}

test_database_connection() {
  MYSQL_PWD="${DB_PASSWORD}" mysql \
    --host="${DB_HOST}" \
    --port="${DB_PORT}" \
    --user="${DB_USER}" \
    --database="${DB_NAME}" \
    --execute="SELECT 1;" >/dev/null
}

run_migrations() {
  if [ ! -d "${MIGRATIONS_DIR}" ]; then
    echo "Missing migrations directory: ${MIGRATIONS_DIR}" >&2
    exit 1
  fi

  shopt -s nullglob
  local migration
  for migration in "${MIGRATIONS_DIR}"/*.sql; do
    echo "Applying migration $(basename "${migration}")"
    MYSQL_PWD="${DB_PASSWORD}" mysql \
      --host="${DB_HOST}" \
      --port="${DB_PORT}" \
      --user="${DB_USER}" \
      --database="${DB_NAME}" \
      <"${migration}"
  done
  shopt -u nullglob
}

write_env_file() {
  if ! getent group in2bridge >/dev/null; then
    addgroup --system in2bridge >/dev/null
  fi

  install -d -m 0750 -o root -g in2bridge /etc/in2bridge
  cat >"${ENV_FILE}" <<EOF
RUST_LOG=in2bridge_engine=info,info
IN2BRIDGE_CONFIG_FROM_DB=true
IN2BRIDGE_LOG_DIR=/var/log/in2bridge
IN2BRIDGE_GUI_DIST=/opt/in2bridge/gui/dist
IN2BRIDGE_PREVIEW_DIR=/var/lib/in2bridge/preview
IN2BRIDGE_MANAGEMENT_LISTEN_ADDRESS=0.0.0.0:8090
IN2BRIDGE_DB_HOST=${DB_HOST}
IN2BRIDGE_DB_PORT=${DB_PORT}
IN2BRIDGE_DB_NAME=${DB_NAME}
IN2BRIDGE_DB_USER=${DB_USER}
IN2BRIDGE_DB_PASSWORD=${DB_PASSWORD}
IN2BRIDGE_FFMPEG_BIN=/opt/in2bridge/runtime/bin/ffmpeg
IN2BRIDGE_FFPROBE_BIN=/opt/in2bridge/runtime/bin/ffprobe
IN2BRIDGE_HA_ALLOW_VIP=1
IN2BRIDGE_NODE_ID=${NODE_ID}
LD_LIBRARY_PATH=/opt/in2bridge/runtime/lib
PATH=/opt/in2bridge/runtime/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EOF
  chown root:in2bridge "${ENV_FILE}"
  chmod 0640 "${ENV_FILE}"
}

main() {
  require_root
  require_cmd mysql
  load_existing_defaults

  echo "in2bridge application database configuration"
  DB_HOST="$(prompt_value "Database host" "${DB_HOST}")"
  DB_PORT="$(prompt_value "Database port" "${DB_PORT}")"
  DB_NAME="$(prompt_value "Database name" "${DB_NAME}")"
  DB_USER="$(prompt_value "Database user" "${DB_USER}")"
  if [ -z "${DB_PASSWORD}" ]; then
    DB_PASSWORD="$(prompt_password)"
  else
    if [ "${IN2BRIDGE_NONINTERACTIVE:-}" = "1" ] || [ ! -t 0 ]; then
      reuse="Y"
    elif ! read -r -p "Reuse database password from ${DB_PASSWORD_SOURCE}? [Y/n]: " reuse; then
      reuse="Y"
      echo >&2
    fi
    case "${reuse:-Y}" in
      y|Y|yes|YES) ;;
      *) DB_PASSWORD="$(prompt_password)" ;;
    esac
  fi

  test_database_connection
  run_migrations
  write_env_file

  echo "Application database configured."
  echo "Env file: ${ENV_FILE}"
}

main "$@"
