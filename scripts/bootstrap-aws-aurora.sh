#!/usr/bin/env bash
# Read AWS keys from SAVY-Ops.local.md, configure CLI, provision Aurora, apply schema, migrate.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OPS="$ROOT/SAVY-Ops.local.md"

if [[ ! -f "$OPS" ]]; then
  echo "Missing $OPS — paste your AWS keys there first."
  exit 1
fi

read_ops_var() {
  local key="$1"
  grep -E "^${key}=" "$OPS" | head -1 | cut -d= -f2- | tr -d '\r'
}

KEY_ID="$(read_ops_var AWS_ACCESS_KEY_ID)"
SECRET="$(read_ops_var AWS_SECRET_ACCESS_KEY)"
REGION="$(read_ops_var AWS_REGION)"
REGION="${REGION:-us-west-2}"

if [[ -z "$KEY_ID" || "$KEY_ID" == "PASTE_HERE" || -z "$SECRET" || "$SECRET" == "PASTE_HERE" ]]; then
  echo "Edit $OPS and replace PASTE_HERE with your real AWS access key + secret."
  exit 1
fi

mkdir -p ~/.aws
chmod 700 ~/.aws
aws configure set aws_access_key_id "$KEY_ID"
aws configure set aws_secret_access_key "$SECRET"
aws configure set region "$REGION"
aws configure set output json

echo "AWS identity:"
aws sts get-caller-identity

export AWS_REGION="$REGION"
export SAVY_AURORA_MASTER_PASSWORD="${SAVY_AURORA_MASTER_PASSWORD:-$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)}"

echo ""
echo "Installing gateway deps…"
(cd "$ROOT/gateway" && npm install --silent)

echo "Provisioning Aurora…"
"$ROOT/scripts/provision-aurora.sh"

export AWS_ACCESS_KEY_ID="$KEY_ID"
export AWS_SECRET_ACCESS_KEY="$SECRET"
export AWS_REGION="$REGION"

echo "Applying Aurora schema…"
(cd "$ROOT/gateway" && node ../scripts/apply-aurora-schema.mjs)

echo "Migrating Supabase → Aurora…"
(cd "$ROOT/gateway" && node ../scripts/migrate-supabase-to-aurora.mjs)

echo ""
echo "Done. Next: add AURORA_HOST + AWS keys to Vercel production env and redeploy gateway."
