#!/usr/bin/env bash
set -euo pipefail
# -------------------------------------------------------------
# Create an IAM user with SES send email permissions (idempotent)
# Usage:
#   bash create-aws-email-user.sh <app-name> [profile-name]
#
# Environment:
#   AWS_REGION (optional) - defaults to us-east-1
# -------------------------------------------------------------
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <app-name> [profile-name]"
  exit 1
fi

APP_NAME="$1"
PROFILE="${2:-admin}"
REGION="${AWS_REGION:-us-east-1}"
IAM_USER="ses-${APP_NAME}-sender"
VERIFIED_IDENTITY="hotosm.org"  # SES verified domain

echo "========================================="
echo "👤 IAM User: $IAM_USER"
echo "🌎 Region: $REGION"
echo "👔 Profile: $PROFILE"
echo "📧 SES Verified Identity: $VERIFIED_IDENTITY"
echo "========================================="

# -------------------------------------------------------------
# 1. Create IAM user (idempotent)
# -------------------------------------------------------------
if aws iam get-user --user-name "$IAM_USER" --profile "$PROFILE" >/dev/null 2>&1; then
  echo "User $IAM_USER already exists, skipping creation."
else
  echo "Creating IAM user..."
  aws iam create-user --user-name "$IAM_USER" --profile "$PROFILE"
fi

# -------------------------------------------------------------
# 2. Attach SES send email policy (idempotent)
# -------------------------------------------------------------
POLICY_NAME="${IAM_USER}-policy"
POLICY_DOCUMENT=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ses:SendEmail",
        "ses:SendRawEmail"
      ],
      "Resource": "arn:aws:ses:${REGION}:*:identity/${VERIFIED_IDENTITY}"
    }
  ]
}
EOF
)

# Check if policy exists
if aws iam get-user-policy --user-name "$IAM_USER" --policy-name "$POLICY_NAME" --profile "$PROFILE" >/dev/null 2>&1; then
  echo "Updating existing SES policy..."
else
  echo "Attaching new SES policy..."
fi

aws iam put-user-policy \
  --user-name "$IAM_USER" \
  --policy-name "$POLICY_NAME" \
  --policy-document "$POLICY_DOCUMENT" \
  --profile "$PROFILE"

# -------------------------------------------------------------
# 3. Create or reuse access keys (idempotent)
# -------------------------------------------------------------
EXISTING_KEY=$(aws iam list-access-keys --user-name "$IAM_USER" --profile "$PROFILE" \
  | jq -r '.AccessKeyMetadata[0].AccessKeyId // empty')

if [[ -n "$EXISTING_KEY" ]]; then
  echo "Existing access key found, reusing..."
  AWS_ACCESS_KEY_ID="$EXISTING_KEY"
  # Retrieve secret from previous run is not possible, so warn user
  echo "⚠️ Existing key reused, secret access key cannot be retrieved. Create a new key if needed."
  AWS_SECRET_ACCESS_KEY="REPLACE_WITH_NEW_KEY_IF_NEEDED"
else
  echo "Creating new access key..."
  CREDS_JSON=$(aws iam create-access-key --user-name "$IAM_USER" --profile "$PROFILE")
  AWS_ACCESS_KEY_ID=$(echo "$CREDS_JSON" | jq -r .AccessKey.AccessKeyId)
  AWS_SECRET_ACCESS_KEY=$(echo "$CREDS_JSON" | jq -r .AccessKey.SecretAccessKey)
fi

# -------------------------------------------------------------
# 4. Output credentials
# -------------------------------------------------------------
echo
echo "✅ Done!"
echo "-----------------------------------------"
echo "Generated credentials for IAM user: $IAM_USER"
echo "-----------------------------------------"
cat <<EOF
[default]
aws_access_key_id=${AWS_ACCESS_KEY_ID}
aws_secret_access_key=${AWS_SECRET_ACCESS_KEY}
EOF
echo "-----------------------------------------"
echo
echo "💡 Tip: Save this as './credentials' and use it in your app's Kubernetes Secret for SES access."
echo
