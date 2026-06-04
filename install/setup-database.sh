#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${IN2BRIDGE_DB_NAME:-in2bridge}"
DB_USER="${IN2BRIDGE_DB_USER:-in2bridge}"
DB_PASSWORD="${IN2BRIDGE_DB_PASSWORD:-}"

require_root() {
  if [ "${EUID}" -ne 0 ]; then
    echo "Run this script as root or with sudo." >&2
    exit 1
  fi
}

detect_os_id() {
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    echo "${ID:-unknown}"
    return
  fi
  echo "unknown"
}

prompt_value() {
  local label="$1"
  local default_value="$2"
  local value
  if ! read -r -p "${label} [${default_value}]: " value; then
    value=""
    echo >&2
  fi
  printf "%s" "${value:-${default_value}}"
}

prompt_password() {
  local first
  local second
  while true; do
    read -r -s -p "Database password: " first
    echo >&2
    read -r -s -p "Confirm database password: " second
    echo >&2
    if [ -n "${first}" ] && [ "${first}" = "${second}" ]; then
      printf "%s" "${first}"
      return
    fi
    echo "Passwords are empty or do not match. Try again." >&2
  done
}

sql_escape() {
  printf "%s" "$1" | sed "s/'/''/g"
}

install_database_server() {
  local os_id
  os_id="$(detect_os_id)"
  case "${os_id}" in
    ubuntu|debian)
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server mariadb-client
      systemctl enable --now mariadb.service
      ;;
    *)
      echo "Unsupported OS for automatic database installation: ${os_id}" >&2
      exit 1
      ;;
  esac
}

create_database_and_user() {
  local escaped_name
  local escaped_user
  local escaped_password

  escaped_name="$(sql_escape "${DB_NAME}")"
  escaped_user="$(sql_escape "${DB_USER}")"
  escaped_password="$(sql_escape "${DB_PASSWORD}")"

  mysql --protocol=socket -uroot <<SQL
CREATE DATABASE IF NOT EXISTS \`${escaped_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${escaped_user}'@'localhost' IDENTIFIED BY '${escaped_password}';
CREATE USER IF NOT EXISTS '${escaped_user}'@'%' IDENTIFIED BY '${escaped_password}';
ALTER USER '${escaped_user}'@'localhost' IDENTIFIED BY '${escaped_password}';
ALTER USER '${escaped_user}'@'%' IDENTIFIED BY '${escaped_password}';
GRANT ALL PRIVILEGES ON \`${escaped_name}\`.* TO '${escaped_user}'@'localhost';
GRANT ALL PRIVILEGES ON \`${escaped_name}\`.* TO '${escaped_user}'@'%';
FLUSH PRIVILEGES;
SQL
}

test_database_user() {
  MYSQL_PWD="${DB_PASSWORD}" mysql \
    --host=localhost \
    --port=3306 \
    --user="${DB_USER}" \
    --database="${DB_NAME}" \
    --execute="SELECT 1;" >/dev/null
}

main() {
  require_root

  echo "in2bridge database setup"
  DB_NAME="$(prompt_value "Database name" "${DB_NAME}")"
  DB_USER="$(prompt_value "Database user" "${DB_USER}")"
  if [ -z "${DB_PASSWORD}" ]; then
    DB_PASSWORD="$(prompt_password)"
  fi

  install_database_server
  create_database_and_user
  test_database_user

  install -d -m 0700 /root/in2bridge
  cat >/root/in2bridge/database.env <<EOF
IN2BRIDGE_DB_HOST=localhost
IN2BRIDGE_DB_PORT=3306
IN2BRIDGE_DB_NAME=${DB_NAME}
IN2BRIDGE_DB_USER=${DB_USER}
IN2BRIDGE_DB_PASSWORD=${DB_PASSWORD}
EOF
  chmod 0600 /root/in2bridge/database.env

  echo "Database server configured."
  echo "Credentials saved for root in /root/in2bridge/database.env"
}

main "$@"
