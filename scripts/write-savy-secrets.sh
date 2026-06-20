#!/bin/bash
# Back-compat wrapper — use scripts/setup-savy-secrets.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "$ROOT/scripts/setup-savy-secrets.sh" "$@"
