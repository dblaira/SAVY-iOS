#!/usr/bin/env bash
# Provision SAVY Aurora PostgreSQL (express configuration — AWS Free Tier).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/gateway/.env.local"

CLUSTER_ID="${SAVY_AURORA_CLUSTER_ID:-savy-aurora}"
DB_NAME="${SAVY_AURORA_DB_NAME:-postgres}"
MASTER_USER="${SAVY_AURORA_MASTER_USER:-postgres}"
AWS_REGION="${AWS_REGION:-us-west-2}"

if ! command -v aws >/dev/null 2>&1; then
  echo "AWS CLI not found. Install: brew install awscli"
  exit 1
fi

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "AWS CLI is not authenticated."
  exit 1
fi

echo "Using region: $AWS_REGION"
echo "Cluster: $CLUSTER_ID (express configuration)"

if ! aws rds describe-db-clusters --db-cluster-identifier "$CLUSTER_ID" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "Creating Aurora express cluster…"
  aws rds create-db-cluster \
    --region "$AWS_REGION" \
    --db-cluster-identifier "$CLUSTER_ID" \
    --engine aurora-postgresql \
    --master-username "$MASTER_USER" \
    --with-express-configuration

  echo "Waiting for cluster to become available…"
  aws rds wait db-cluster-available \
    --region "$AWS_REGION" \
    --db-cluster-identifier "$CLUSTER_ID"
else
  echo "Cluster $CLUSTER_ID already exists."
fi

ENDPOINT="$(aws rds describe-db-clusters \
  --region "$AWS_REGION" \
  --db-cluster-identifier "$CLUSTER_ID" \
  --query 'DBClusters[0].Endpoint' \
  --output text)"

touch "$ENV_FILE"
for key in AURORA_HOST AURORA_DB AURORA_USER AWS_REGION; do
  grep -v "^${key}=" "$ENV_FILE" > "${ENV_FILE}.tmp" 2>/dev/null || true
  mv "${ENV_FILE}.tmp" "$ENV_FILE" 2>/dev/null || true
done

{
  echo ""
  echo "# Aurora express (IAM auth — added by provision-aurora.sh)"
  echo "AURORA_HOST=$ENDPOINT"
  echo "AURORA_DB=$DB_NAME"
  echo "AURORA_USER=$MASTER_USER"
  echo "AWS_REGION=$AWS_REGION"
} >> "$ENV_FILE"

echo ""
echo "Aurora endpoint: $ENDPOINT"
echo "Database: $DB_NAME"
echo "Auth: IAM (uses AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY on gateway)"
echo ""
echo "Saved AURORA_* vars to $ENV_FILE"
