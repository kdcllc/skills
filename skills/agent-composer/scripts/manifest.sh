#!/usr/bin/env bash
# Usage: manifest.sh write <project-root> <spec.crew.yaml>
#        manifest.sh status <project-root> <spec.crew.yaml>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON="${AGENT_COMPOSER_PYTHON:-python3}"
COMPOSER="${SCRIPT_DIR}/composer.py"

if ! command -v "${PYTHON}" >/dev/null 2>&1; then
  echo "python3 -m pip install pyyaml" >&2
  exit 3
fi

exec "${PYTHON}" "${COMPOSER}" manifest "$@"
