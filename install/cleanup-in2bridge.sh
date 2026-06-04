#!/usr/bin/env bash
set -euo pipefail

DROP_DATABASE=false
DB_NAME="${IN2BRIDGE_DB_NAME:-in2bridge}"
DB_USER="${IN2BRIDGE_DB_USER:-in2bridge}"

usage() {
  cat <<'EOF'
Usage: sudo ./cleanup-in2bridge.sh [--drop-database]

Removes in2bridge from a test node:
  - stops and disables in2bridge-engine.service
  - purges in2bridge-engine and in2bridge-runtime packages
  - removes /etc/in2bridge, /var/lib/in2bridge, /var/log/in2bridge, /opt/in2bridge
  - removes local downloaded public installer scripts from the current directory

With --drop-database it also drops the in2bridge database and application users.
Override DB/user with IN2BRIDGE_DB_NAME and IN2BRIDGE_DB_USER.
EOF
}

require_root() {
  if [ "${EUID}" -ne 0 ]; then
    echo "Run this script as root or with sudo." >&2
    exit 1
  fi
}

sql_escape() {
  printf "%s" "$1" | sed "s/'/''/g"
}

drop_database() {
  if ! command -v mysql >/dev/null 2>&1; then
    echo "mysql client not found; skipping database cleanup."
    return
  fi

  local escaped_name
  local escaped_user
  escaped_name="$(sql_escape "${DB_NAME}")"
  escaped_user="$(sql_escape "${DB_USER}")"

  mysql --protocol=socket -uroot <<SQL
DROP DATABASE IF EXISTS \`${escaped_name}\`;
DROP USER IF EXISTS '${escaped_user}'@'localhost';
DROP USER IF EXISTS '${escaped_user}'@'%';
FLUSH PRIVILEGES;
SQL
}

main() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --drop-database)
        DROP_DATABASE=true
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
    shift
  done

  require_root

  systemctl stop in2bridge-engine.service >/dev/null 2>&1 || true
  systemctl disable in2bridge-engine.service >/dev/null 2>&1 || true

  if command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get purge -y in2bridge-engine in2bridge-runtime >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get autoremove -y >/dev/null 2>&1 || true
  fi

  rm -rf /etc/in2bridge /var/lib/in2bridge /var/log/in2bridge /opt/in2bridge /root/in2bridge
  rm -f /etc/systemd/system/in2bridge-engine.service
  rm -f /usr/local/bin/in2bridge-engine
  rm -f ./install-in2bridge.sh ./setup-database.sh ./configure-app-database.sh ./cleanup-in2bridge.sh

  if [ "${DROP_DATABASE}" = true ]; then
    drop_database
  fi

  systemctl daemon-reload >/dev/null 2>&1 || true
  echo "in2bridge cleanup completed."
}

main "$@"
