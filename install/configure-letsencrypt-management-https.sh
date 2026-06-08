#!/usr/bin/env bash
set -euo pipefail

DOMAIN=""
APPLY_DB=false
RESTART_SERVICE=false

usage() {
  cat <<'EOF'
Usage:
  sudo configure-letsencrypt-management-https.sh <domain> [--apply-db] [--restart]

Prepares a Let's Encrypt certificate for the in2bridge management HTTPS
listener. The script keeps the original certbot renewal paths, grants the
in2bridge service user read access, verifies readability, and prints the paths
that should be used in the General > Management access settings.

Options:
  --apply-db   Save the HTTPS settings directly into the in2bridge MySQL
               app_settings row named "general".
  --restart    Restart in2bridge-engine.service after applying permissions or DB.

Examples:
  sudo configure-letsencrypt-management-https.sh in2bridge1.in2itions.com
  sudo configure-letsencrypt-management-https.sh in2bridge2.in2itions.com --apply-db --restart
EOF
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo $0 <domain>" >&2
    exit 1
  fi
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --apply-db)
        APPLY_DB=true
        ;;
      --restart)
        RESTART_SERVICE=true
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -*)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 1
        ;;
      *)
        if [ -n "${DOMAIN}" ]; then
          echo "Only one domain can be specified." >&2
          usage >&2
          exit 1
        fi
        DOMAIN="$1"
        ;;
    esac
    shift
  done

  if [ -z "${DOMAIN}" ]; then
    usage >&2
    exit 1
  fi

  case "${DOMAIN}" in
    *[!A-Za-z0-9.-]*|.*|*-|*-.|*..*)
      echo "Invalid domain name: ${DOMAIN}" >&2
      exit 1
      ;;
  esac
}

require_cert_files() {
  local live_dir="/etc/letsencrypt/live/${DOMAIN}"
  local archive_dir="/etc/letsencrypt/archive/${DOMAIN}"

  for path in \
    "${live_dir}/fullchain.pem" \
    "${live_dir}/privkey.pem" \
    "${live_dir}/chain.pem" \
    "${archive_dir}"; do
    if [ ! -e "${path}" ]; then
      echo "Missing Let's Encrypt path: ${path}" >&2
      echo "Create the certificate first with certbot, then rerun this script." >&2
      exit 1
    fi
  done
}

ensure_service_user() {
  if ! id in2bridge >/dev/null 2>&1; then
    echo "User 'in2bridge' does not exist. Install in2bridge first." >&2
    exit 1
  fi
}

configure_permissions() {
  groupadd -r ssl-cert >/dev/null 2>&1 || true
  usermod -aG ssl-cert in2bridge

  chgrp ssl-cert /etc/letsencrypt
  chgrp ssl-cert /etc/letsencrypt/live
  chgrp ssl-cert /etc/letsencrypt/archive

  chmod 750 /etc/letsencrypt
  chmod 750 /etc/letsencrypt/live
  chmod 750 /etc/letsencrypt/archive

  chgrp -R ssl-cert "/etc/letsencrypt/live/${DOMAIN}"
  chgrp -R ssl-cert "/etc/letsencrypt/archive/${DOMAIN}"

  chmod 750 "/etc/letsencrypt/live/${DOMAIN}"
  chmod 750 "/etc/letsencrypt/archive/${DOMAIN}"
  chmod 640 "/etc/letsencrypt/archive/${DOMAIN}"/privkey*.pem
  chmod 640 "/etc/letsencrypt/archive/${DOMAIN}"/fullchain*.pem
  chmod 640 "/etc/letsencrypt/archive/${DOMAIN}"/chain*.pem
}

verify_readability() {
  local cert="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
  local key="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
  local chain="/etc/letsencrypt/live/${DOMAIN}/chain.pem"

  if ! runuser -u in2bridge -- test -r "${cert}"; then
    echo "in2bridge cannot read certificate: ${cert}" >&2
    namei -l "${cert}" >&2 || true
    exit 1
  fi
  if ! runuser -u in2bridge -- test -r "${key}"; then
    echo "in2bridge cannot read private key: ${key}" >&2
    namei -l "${key}" >&2 || true
    exit 1
  fi
  if ! runuser -u in2bridge -- test -r "${chain}"; then
    echo "in2bridge cannot read CA chain: ${chain}" >&2
    namei -l "${chain}" >&2 || true
    exit 1
  fi
}

env_value() {
  local key="$1"
  local file="/etc/in2bridge/in2bridge.env"
  if [ ! -f "${file}" ]; then
    return 1
  fi
  grep -E "^${key}=" "${file}" | tail -n 1 | sed -E "s/^${key}=//"
}

apply_db_settings() {
  if ! command -v mysql >/dev/null 2>&1; then
    echo "mysql client is required for --apply-db." >&2
    exit 1
  fi

  local db_host db_port db_name db_user db_password
  db_host="$(env_value IN2BRIDGE_DB_HOST || echo localhost)"
  db_port="$(env_value IN2BRIDGE_DB_PORT || echo 3306)"
  db_name="$(env_value IN2BRIDGE_DB_NAME || echo in2bridge)"
  db_user="$(env_value IN2BRIDGE_DB_USER || echo in2bridge)"
  db_password="$(env_value IN2BRIDGE_DB_PASSWORD || true)"

  if [ -z "${db_password}" ]; then
    echo "IN2BRIDGE_DB_PASSWORD is empty or missing in /etc/in2bridge/in2bridge.env." >&2
    exit 1
  fi

  local cert="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
  local key="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
  local chain="/etc/letsencrypt/live/${DOMAIN}/chain.pem"

  MYSQL_PWD="${db_password}" mysql \
    --batch \
    --skip-column-names \
    -h "${db_host}" \
    -P "${db_port}" \
    -u "${db_user}" \
    "${db_name}" \
    -e "
UPDATE app_settings
SET payload = JSON_SET(
  payload,
  '$.management_https_enabled', true,
  '$.management_tls_cert_path', '${cert}',
  '$.management_tls_key_path', '${key}',
  '$.management_tls_ca_path', '${chain}'
)
WHERE setting_key='general' AND JSON_VALID(payload)=1;
SELECT COUNT(*)
FROM app_settings
WHERE setting_key='general'
  AND JSON_VALID(payload)=1
  AND JSON_EXTRACT(payload, '$.management_https_enabled') = true
  AND JSON_UNQUOTE(JSON_EXTRACT(payload, '$.management_tls_cert_path')) = '${cert}'
  AND JSON_UNQUOTE(JSON_EXTRACT(payload, '$.management_tls_key_path')) = '${key}'
  AND JSON_UNQUOTE(JSON_EXTRACT(payload, '$.management_tls_ca_path')) = '${chain}';
" | {
    read -r configured || configured=0
    if [ "${configured}" = "0" ]; then
      echo "Could not verify HTTPS settings in app_settings row 'general'." >&2
      echo "Use the GUI to enable HTTPS manually, or inspect app_settings payload JSON." >&2
      exit 1
    fi
  }
}

restart_service() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart in2bridge-engine.service
  else
    echo "systemctl not available; restart in2bridge-engine.service manually." >&2
  fi
}

print_result() {
  cat <<EOF
Let's Encrypt management HTTPS permissions are ready.

Use these values in General > Management access:

Certificate chain path: /etc/letsencrypt/live/${DOMAIN}/fullchain.pem
Private key path:       /etc/letsencrypt/live/${DOMAIN}/privkey.pem
CA certificate path:    /etc/letsencrypt/live/${DOMAIN}/chain.pem

Verify after restart:
  curl -vk https://127.0.0.1:8090/api/health
  curl -vk https://${DOMAIN}:8090/api/health
EOF
}

main() {
  parse_args "$@"
  require_root
  ensure_service_user
  require_cert_files
  configure_permissions
  verify_readability

  if [ "${APPLY_DB}" = true ]; then
    apply_db_settings
  fi

  if [ "${RESTART_SERVICE}" = true ]; then
    restart_service
  fi

  print_result
}

main "$@"
