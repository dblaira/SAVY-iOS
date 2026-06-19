#!/usr/bin/env bash
set -euo pipefail

REGION="${AWS_REGION:-us-west-2}"
POOL_NAME="${SAVY_COGNITO_POOL_NAME:-savy-users}"
CLIENT_NAME="${SAVY_COGNITO_CLIENT_NAME:-savy-ios}"
ENV_FILE="${1:-$(dirname "$0")/../gateway/.env.local}"

echo "Creating Cognito user pool: $POOL_NAME in $REGION"

POOL_ID=$(aws cognito-idp create-user-pool \
  --region "$REGION" \
  --pool-name "$POOL_NAME" \
  --auto-verified-attributes email \
  --username-attributes email \
  --policies "PasswordPolicy={MinimumLength=8,RequireUppercase=false,RequireLowercase=false,RequireNumbers=false,RequireSymbols=false}" \
  --query 'UserPool.Id' \
  --output text)

CLIENT_ID=$(aws cognito-idp create-user-pool-client \
  --region "$REGION" \
  --user-pool-id "$POOL_ID" \
  --client-name "$CLIENT_NAME" \
  --explicit-auth-flows ALLOW_USER_PASSWORD_AUTH ALLOW_REFRESH_TOKEN_AUTH ALLOW_USER_SRP_AUTH \
  --prevent-user-existence-errors ENABLED \
  --query 'UserPoolClient.ClientId' \
  --output text)

echo "User pool: $POOL_ID"
echo "Client ID: $CLIENT_ID"

append_env() {
  local key="$1"
  local value="$2"
  if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
    sed -i '' "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
  else
    printf '\n%s=%s\n' "$key" "$value" >> "$ENV_FILE"
  fi
}

append_env COGNITO_USER_POOL_ID "$POOL_ID"
append_env COGNITO_CLIENT_ID "$CLIENT_ID"
append_env COGNITO_REGION "$REGION"

echo "Saved Cognito vars to $ENV_FILE"
