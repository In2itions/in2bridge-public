#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
installer="${repo_root}/public-releases/install/install-in2bridge.sh"

while IFS= read -r script; do
  if python3 - "$script" <<'PY'
from pathlib import Path
import sys
raise SystemExit(0 if b"\r\n" not in Path(sys.argv[1]).read_bytes() else 1)
PY
  then
    :
  else
    echo "${script} must use LF line endings; CRLF breaks Linux shebang execution." >&2
    exit 1
  fi
done < <(find "${repo_root}/public-releases/install" -maxdepth 1 -type f -name '*.sh' | sort)
if grep -q 'sort | tail' "${installer}"; then
  echo "install-in2bridge.sh must not select packages with sort | tail; it can pick 0.0.9 over 0.0.14." >&2
  exit 1
fi

grep -q 'in2bridge-runtime_${VERSION}_amd64\.deb' "${installer}" \
  || { echo "install-in2bridge.sh must select the runtime package by exact VERSION." >&2; exit 1; }

grep -q 'in2bridge-engine_${VERSION}_amd64\.deb' "${installer}" \
  || { echo "install-in2bridge.sh must select the engine package by exact VERSION." >&2; exit 1; }

echo "install script package selection check passed"
