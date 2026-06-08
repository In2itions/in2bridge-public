#!/usr/bin/env bash
set -euo pipefail

DOMAIN=""
RESTART_SERVICE=false

usage() {
  cat <<'EOF'
Usage:
  sudo configure-letsencrypt-management-https.sh <domain> [--restart]

Prepares a Let's Encrypt certificate for the in2bridge management HTTPS
listener. The script keeps the original certbot renewal paths, grants the
in2bridge service user read access, verifies readability, and prints the paths
that should be used in the General > Management access settings.

Options:
  --restart    Restart in2bridge-engine.service after applying permissions.

Examples:
  sudo configure-letsencrypt-management-https.sh in2bridge1.in2itions.com
  sudo configure-letsencrypt-management-https.sh in2bridge2.in2itions.com --restart
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

  if [ "${RESTART_SERVICE}" = true ]; then
    restart_service
  fi

  print_result
}

main "$@"
