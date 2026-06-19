#!/usr/bin/env bash
# Deploys the Cognito Pre Sign-up Lambda and wires it to the SAVY user pool.
#
# Requires IAM permissions: lambda:*, cognito-idp:UpdateUserPool, iam:CreateRole, iam:PassRole
# blair.ai.ops cannot create IAM roles. If this script fails with AccessDenied on CreateRole,
# use the AWS Console instead (logged in as root/admin):
#   Cognito → User pools → us-west-2_sqayHoHrK → Extensions → Lambda triggers → Pre sign-up
#   → Create Lambda function → paste scripts/cognito/pre-signup-auto-confirm/index.mjs
#
# Faster alternative: IAM → Users → blair.ai.ops → Add permissions → AmazonCognitoPowerUser
# That lets the gateway call AdminConfirmSignUp after sign-up (no Lambda required).
set -euo pipefail

REGION="${AWS_REGION:-us-west-2}"
POOL_ID="${COGNITO_USER_POOL_ID:-us-west-2_sqayHoHrK}"
FUNCTION_NAME="${COGNITO_PRESIGNUP_LAMBDA:-savy-cognito-pre-signup}"
ROLE_NAME="${COGNITO_PRESIGNUP_ROLE:-savy-cognito-pre-signup-role}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIP="/tmp/savy-cognito-pre-signup.zip"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

echo "==> Packaging Lambda"
rm -f "$ZIP"
(cd "$SCRIPT_DIR/pre-signup-auto-confirm" && zip -q "$ZIP" index.mjs)

if ! aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  echo "==> Creating IAM role $ROLE_NAME"
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Principal": { "Service": "lambda.amazonaws.com" },
        "Action": "sts:AssumeRole"
      }]
    }' >/dev/null
  aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
  sleep 10
fi

if aws lambda get-function --function-name "$FUNCTION_NAME" --region "$REGION" >/dev/null 2>&1; then
  echo "==> Updating Lambda code"
  aws lambda update-function-code \
    --function-name "$FUNCTION_NAME" \
    --region "$REGION" \
    --zip-file "fileb://$ZIP" >/dev/null
else
  echo "==> Creating Lambda $FUNCTION_NAME"
  aws lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --region "$REGION" \
    --runtime nodejs20.x \
    --role "$ROLE_ARN" \
    --handler index.handler \
    --zip-file "fileb://$ZIP" \
    --timeout 5 >/dev/null
fi

LAMBDA_ARN="$(aws lambda get-function --function-name "$FUNCTION_NAME" --region "$REGION" --query Configuration.FunctionArn --output text)"

echo "==> Allowing Cognito to invoke Lambda"
aws lambda add-permission \
  --function-name "$FUNCTION_NAME" \
  --region "$REGION" \
  --statement-id "cognito-presignup-${POOL_ID}" \
  --action lambda:InvokeFunction \
  --principal cognito-idp.amazonaws.com \
  --source-arn "arn:aws:cognito-idp:${REGION}:${ACCOUNT_ID}:userpool/${POOL_ID}" \
  2>/dev/null || true

echo "==> Attaching Pre Sign-up trigger to pool $POOL_ID"
aws cognito-idp update-user-pool \
  --region "$REGION" \
  --user-pool-id "$POOL_ID" \
  --lambda-config "PreSignUp=${LAMBDA_ARN}"

echo "Done. Pre Sign-up Lambda: $LAMBDA_ARN"
echo "New sign-ups will be auto-confirmed. Existing UNCONFIRMED users still need manual confirm in Cognito console."
